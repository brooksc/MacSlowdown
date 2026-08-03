import Darwin
import Foundation
import Metrics
import Observation

/// How fresh the displayed readings are.
///
/// FR-002 requires stale or unavailable values to be labeled, and FR-032 requires
/// the app to stay usable under severe load — which is exactly when sampling falls
/// behind. Showing a stale number as though it were current would be the kind of
/// unsupported claim FR-038 forbids, so freshness is part of the state.
enum Freshness: Equatable {
    case current
    /// The last complete reading, with its age. Nothing is estimated forward.
    case stale(age: Duration)

    var isStale: Bool { if case .stale = self { true } else { false } }
}

/// Overall condition, for the compact status surface (FR-001).
///
/// Severity is never conveyed by colour alone (FR-034), so each case carries a
/// word and a symbol as well.
enum Severity: Int, Comparable, CaseIterable {
    case normal, elevated, severe

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .severe: "Severe"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "gauge.with.dots.needle.33percent"
        case .elevated: "gauge.with.dots.needle.67percent"
        case .severe: "gauge.with.dots.needle.100percent"
        }
    }

    /// Derived from the share of total machine capacity in use. Thresholds are
    /// provisional; FR-006's configurable, hysteresis-backed detection is m-2 work.
    static func forBusyShareOfMachine(_ share: Double) -> Severity {
        switch share {
        case ..<0.6: .normal
        case ..<0.85: .elevated
        default: .severe
        }
    }
}

/// Observable state for the whole app.
///
/// Owns the sampling loop and every state transition; views read from it and never
/// sample, compute or cache on their own.
@MainActor
@Observable
final class MonitorStore {
    /// Shared because the app delegate starts monitoring at launch, independently
    /// of any view. Tying the sampling loop to a view's lifecycle meant that
    /// hiding the menu bar item stopped monitoring altogether.
    static let shared = MonitorStore()

    private(set) var attribution: CPUAttribution?
    private(set) var families: [ProcessFamily] = []
    private(set) var freshness: Freshness = .current
    /// Whether the process table could be read at all. An empty inventory means
    /// opposite things depending on this.
    private(set) var enumeration: EnumerationOutcome = .succeeded
    /// The incident currently open, if any (FR-011).
    private(set) var openIncident: Incident?
    /// Incidents that have closed, most recent first. Bounded.
    private(set) var recentIncidents: [Incident] = []
    /// Current sampling cadence, exposed so the user can inspect it (FR-031).
    private(set) var cadence: SamplingCadence?
    private(set) var memoryPressure: MemoryPressureLevel = .normal
    private(set) var thermalState: ThermalState = .nominal
    private(set) var power: PowerContext = PowerSignals.current()
    private(set) var pagingRates: PagingRates = .zero
    private(set) var diskRates: DiskRates = .zero
    /// Our own cost, measured the same way we measure anything else.
    ///
    /// The headless OverheadHarness reports ~16 MB, but that runs no SwiftUI. The
    /// real app measured 92 MB against FR-030's 100 MB budget, so the figure the
    /// budget actually applies to has to come from the app itself.
    private(set) var ownResidentBytes: UInt64 = 0
    private(set) var ownCPUPercentOfOneCore: Double = 0
    private(set) var mute: MuteState = .notMuted

    /// FR-030 self-report, as the design's Now screen shows it.
    var selfCost: String {
        let memory = ByteCountFormatStyle().format(Int64(ownResidentBytes))
        return String(format: "MacSlowdown itself: %.1f%% CPU, %@",
                      ownCPUPercentOfOneCore, memory as NSString)
    }

    var isWithinMemoryBudget: Bool { ownResidentBytes <= FR030Budget.residentBytes }

    /// Aggregate disk throughput, with the per-application limitation stated
    /// alongside it rather than left as a silent omission (FR-009).
    var diskThroughput: String {
        let read = ByteCountFormatStyle().format(Int64(diskRates.readBytesPerSecond))
        let write = ByteCountFormatStyle().format(Int64(diskRates.writeBytesPerSecond))
        return "\(read)/s read · \(write)/s write"
    }

    /// Swap activity, described without implying memory can be freed (FR-036).
    var swapActivity: String {
        pagingRates.isSwapping
            ? "macOS is moving memory to and from disk"
            : "No swapping"
    }

    /// An evidence-based account of the open incident, or the most recent one.
    var currentSummary: IncidentSummary? {
        guard let incident = openIncident ?? recentIncidents.first else { return nil }
        return IncidentSummarizer.summarize(incident: incident, attribution: attribution)
    }
    private(set) var lastUpdate: Date?
    private(set) var isRunning = false
    let machine = MachineContext.current()

    var severity: Severity {
        guard let attribution else { return .normal }
        let share = attribution.totalBusyPercentOfOneCore / (Double(machine.logicalCores) * 100)
        return .forBusyShareOfMachine(share)
    }

    /// One row of the inventory: a family with its aggregated usage.
    struct FamilyRow: Identifiable {
        let family: ProcessFamily
        let percentOfOneCore: Double
        let residentBytes: UInt64
        var id: String { family.id }
    }

    /// Families with measurable usage, largest first, for the inventory view.
    var rankedFamilies: [FamilyRow] {
        families.map { family in
            let usage = family.members.reduce(into: (cpu: 0.0, memory: UInt64(0))) { totals, member in
                if let contribution = contribution(for: member.record.identity) {
                    totals.cpu += contribution
                }
                totals.memory += member.record.measurements?.residentBytes ?? 0
            }
            return FamilyRow(family: family, percentOfOneCore: usage.cpu, residentBytes: usage.memory)
        }
        .filter { $0.percentOfOneCore > 0 || $0.residentBytes > 0 }
        .sorted { $0.percentOfOneCore > $1.percentOfOneCore }
    }

    private var contributionIndex: [ProcessIdentity: Double] = [:]
    private func contribution(for identity: ProcessIdentity) -> Double? {
        contributionIndex[identity]
    }

    private let sampler = ProcessSampler()
    private let resolver = ProcessIdentityResolver()
    private let history: MetricsHistory
    private let baseCadence: Duration
    private var task: Task<Void, Never>?

    private let detector: IncidentDetector
    private var detectorState = IncidentDetector.State()
    private let cadenceController: CadenceController
    private var cadenceState = CadenceController.State()
    private let pressureMonitor = MemoryPressureMonitor()
    private let notificationGate = NotificationGate()
    private var notificationState = NotificationGate.State()
    let notifications = NotificationDelivery()
    private var previousPaging: PagingCounters?
    private var previousDisk: DiskCounters?
    private var previousOwn: UInt64?

    /// Kept small: FR-005 bounds retained evidence, and the UI shows recent
    /// history rather than an archive.
    private static let retainedIncidents = 20

    init(cadence: Duration = MetricsHistory.defaultCadence,
         history: MetricsHistory = MetricsHistory(),
         policy: IncidentPolicy = .default) {
        self.baseCadence = cadence
        self.history = history
        self.detector = IncidentDetector(policy: policy)
        self.cadenceController = CadenceController(normalInterval: cadence)
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        // A dispatch source catches pressure transitions between samples, which
        // the cadence alone could not guarantee within FR-007's 2 seconds.
        pressureMonitor.start()
        task = Task { [weak self] in await self?.run() }
    }

    /// FR-015: muting suppresses interruption only. Monitoring continues, which is
    /// why this touches `mute` and nothing else.
    func mute(forMinutes minutes: Int) {
        mute = MuteState(until: Date().addingTimeInterval(Double(minutes) * 60))
    }

    func clearMute() { mute = .notMuted }

    func stop() {
        task?.cancel()
        task = nil
        pressureMonitor.stop()
        isRunning = false
    }

    private func run() async {
        var previous = sampler.snapshot()
        var previousHost = HostCPU.sample()
        let clock = ContinuousClock()
        var lastSampleAt = clock.now

        while !Task.isCancelled {
            try? await Task.sleep(for: self.cadence?.interval ?? baseCadence)
            if Task.isCancelled { return }

            let snapshot = sampler.snapshot()
            let host = HostCPU.sample()
            let now = clock.now

            // If the interval ran materially long the machine was too busy to
            // sample on time; surface that rather than presenting a late reading
            // as current.
            let elapsed = now - lastSampleAt
            let expected = self.cadence?.interval ?? baseCadence
            let overdue = elapsed.totalSeconds > expected.totalSeconds * 2
            lastSampleAt = now

            guard let earlierHost = previousHost, let host else {
                previous = snapshot
                previousHost = host
                continue
            }

            let result = CPUAttributionCalculator.attribution(
                from: previous, to: snapshot, hostEarlier: earlierHost, hostLater: host)
            let grouped = FamilyGrouper.group(snapshot: snapshot, resolver: resolver)

            attribution = result
            families = grouped
            contributionIndex = Dictionary(
                result.contributors.map { ($0.identity, $0.percentOfOneCore) },
                uniquingKeysWith: { first, _ in first })
            // We are in our own snapshot, so measuring ourselves costs nothing extra.
            let ownIdentity = snapshot.records.values.first { $0.identity.pid == getpid() }
            if let metrics = ownIdentity?.measurements {
                ownResidentBytes = metrics.residentBytes
                if let previousOwn, metrics.cpuTicks >= previousOwn {
                    let deltaNanos = MachTime.nanos(fromTicks: metrics.cpuTicks - previousOwn)
                    ownCPUPercentOfOneCore = deltaNanos / (elapsed.totalSeconds * 1e9) * 100
                }
                previousOwn = metrics.cpuTicks
            }

            enumeration = snapshot.enumeration
            freshness = overdue ? .stale(age: elapsed) : .current
            lastUpdate = Date()

            // MARK: Incident detection (FR-011)

            memoryPressure = pressureMonitor.level
            thermalState = .current
            power = PowerSignals.current()

            // Rates only ever from deltas over the measured interval.
            let seconds = elapsed.totalSeconds
            if let counters = SwapSignals.pagingCounters() {
                if let previous = previousPaging,
                   let rates = SwapSignals.rates(from: previous, to: counters, seconds: seconds) {
                    pagingRates = rates
                }
                previousPaging = counters
            }
            if let counters = DiskSignals.counters() {
                if let previous = previousDisk,
                   let rates = DiskSignals.rates(from: previous, to: counters, seconds: seconds) {
                    diskRates = rates
                }
                previousDisk = counters
            }
            let observation = SystemObservation(
                at: Date(),
                cpuBusyFraction: result.totalBusyPercentOfOneCore
                    / (Double(machine.logicalCores) * 100),
                memoryPressure: memoryPressure,
                thermalState: thermalState)

            let event = detector.observe(observation, state: &detectorState)
            switch event {
            case .opened(let incident), .updated(let incident):
                openIncident = incident
                // The gate decides; delivery only carries out an approved decision.
                let decision = notificationGate.decide(
                    incident: incident,
                    leadingContributor: result.contributors.first?.command,
                    mute: mute,
                    context: InterruptionContext(
                        audioActive: AudioSignals.isAnyProcessPlaying(),
                        audioApplication: AudioSignals.firstActiveProcessName()),
                    state: &notificationState)
                Task { [notifications] in
                    await notifications.deliver(
                        decision: decision, incident: incident,
                        leadingContributor: result.contributors.first?.command)
                }
            case .closed(let incident):
                openIncident = nil
                recentIncidents.insert(incident, at: 0)
                if recentIncidents.count > Self.retainedIncidents {
                    recentIncidents.removeLast(recentIncidents.count - Self.retainedIncidents)
                }
            case nil:
                break
            }

            // MARK: Adaptive cadence (FR-031)

            let breaching = IncidentCondition.allCases.contains {
                observation.breaches($0, policy: detector.policy)
            }
            self.cadence = cadenceController.cadence(
                at: Date(), incidentOpen: openIncident != nil,
                conditionBreaching: breaching, state: &cadenceState)

            history.record(result)
            resolver.prune(keeping: Set(snapshot.records.keys))
            // Persisting history is best-effort: it is evidence, not configuration,
            // and a write failure must never interrupt monitoring.
            _ = try? history.flushIfNeeded()

            previous = snapshot
            previousHost = host
        }
    }
}
