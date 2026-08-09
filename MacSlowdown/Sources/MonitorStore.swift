import AppKit
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
    /// Aggregate disk throughput, or nil when there is no rate to report (FR-009).
    ///
    /// Optional rather than `.zero` deliberately. A driver that will not report its
    /// statistics and a genuinely idle disk are different facts, and defaulting to
    /// zero presented the first as the second — the unavailable-reported-as-measured
    /// failure FR-002 and FR-010 forbid. Nil also covers the first sample, where no
    /// delta exists yet: a rate needs two readings.
    private(set) var diskRates: DiskRates?
    /// Whether the startup volume is currently below the low-storage warning line
    /// (FR-041, FR-042).
    ///
    /// Scoped to the startup volume deliberately: it is the one whose exhaustion
    /// degrades the machine. A full external disk is a problem for the user's files,
    /// not a cause of the slowdown this app exists to explain, and raising an
    /// incident for it would be a claim we cannot support.
    ///
    /// False when the startup volume did not report its capacity. That is "no
    /// measurement", not "plenty of room" — but it is also not evidence of a
    /// shortage, and FR-002 forbids inventing one.
    private(set) var isLowStorage = false
    /// When the volumes were last read, or nil before the first read.
    private(set) var lastStorageCheck: Date?

    /// The startup volume's capacity as the sampling loop last read it, or nil if
    /// it has not been read yet or did not report.
    ///
    /// Exposed so every surface quotes the same figure. Two views calling
    /// `StorageSignals.snapshot()` independently would read at different moments
    /// and could disagree about free space, which a user would reasonably read as
    /// one of them being wrong.
    var startupVolume: VolumeCapacity? { storage.startupVolume?.capacity }
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
        Presentation.selfCost(cpuPercentOfOneCore: ownCPUPercentOfOneCore,
                              residentBytes: ownResidentBytes)
    }

    var isWithinMemoryBudget: Bool { ownResidentBytes <= FR030Budget.residentBytes }

    /// Aggregate disk throughput, with the per-application limitation stated
    /// alongside it rather than left as a silent omission (FR-009).
    var diskThroughput: String { Presentation.diskThroughput(diskRates) }

    /// Swap activity, described without implying memory can be freed (FR-036).
    var swapActivity: String { Presentation.swapActivity(pagingRates) }

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
        return .forBusyShareOfMachine(Presentation.busyShareOfMachine(
            percentOfOneCore: attribution.totalBusyPercentOfOneCore,
            logicalCores: machine.logicalCores))
    }

    /// One row of the inventory: a family with its aggregated usage.
    struct FamilyRow: Identifiable {
        let family: ProcessFamily
        let percentOfOneCore: Double
        let residentBytes: UInt64
        var id: String { family.id }
        /// Exposed as a stored-looking value so the table can sort on it with a
        /// key path; `members.count` is not reachable as one.
        var processCount: Int { family.members.count }
    }

    /// Families with measurable usage, largest first, for the inventory view.
    var rankedFamilies: [FamilyRow] {
        Presentation.rankedFamilies(families, contributions: contributionIndex)
    }

    /// The inventory as a tree: families with their processes beneath them, plus
    /// the processes we are not permitted to measure collected into one group.
    var inventory: [InventoryRow] {
        Presentation.inventory(
            families, contributions: contributionIndex,
            unattributedPercentOfOneCore: attribution?.unattributedPercentOfOneCore ?? 0)
    }

    private var contributionIndex: [ProcessIdentity: Double] = [:]

    /// A recognisable name for a contributor (FR-003, FR-013).
    ///
    /// Served from the identity resolver's cache, so this costs a dictionary
    /// lookup rather than filesystem work. Views call it; nothing computes a name
    /// of its own, or the popover, the table and the notification would drift
    /// apart — which is exactly how the popover came to show "Spotify Helper (".
    func displayName(for usage: ProcessCPUUsage) -> String { usage.label }

    /// The application's own icon, or nil. Nil means "no icon", never a generic
    /// placeholder standing in for one (FR-002).
    func icon(for usage: ProcessCPUUsage) -> NSImage? {
        icons.icon(forExecutablePath: resolver.identity(for: usage.identity).executablePath)
    }

    func icon(for family: ProcessFamily) -> NSImage? {
        icons.icon(forExecutablePath: family.members.first?.resolved.executablePath)
    }

    func icon(forExecutablePath path: String?) -> NSImage? {
        icons.icon(forExecutablePath: path)
    }

    func accessibilityName(for usage: ProcessCPUUsage) -> String {
        usage.displayName ?? ProcessNaming.accessibilityLabel(command: usage.command)
    }

    private let sampler = ProcessSampler()
    private let resolver = ProcessIdentityResolver()
    private let history: MetricsHistory
    private let baseCadence: Duration
    private var task: Task<Void, Never>?

    // MARK: - Retained history (FR-005)

    /// The retained series, for a view that wants to draw what we actually kept.
    ///
    /// Read access only. `MetricsHistory` is a reference type with `record` and
    /// `removeAll` on it, so handing the object itself to a view would let the UI
    /// write to the evidence; the sampling loop is the only thing that records.
    ///
    /// A view drawing these samples draws the same series FR-005 retains, rather
    /// than accumulating a second one of its own — which would diverge the moment
    /// the view appeared later than the store, or refreshed at a different rate.
    var retainedSamples: [HistorySample] { history.samples }

    /// The wall-clock span actually retained, which is never assumed to be the
    /// retention window: the app may only have been running for a minute.
    var retainedHistorySpan: Duration { history.coveredDuration }

    /// The retained samples covering a closed or open incident, with a margin
    /// either side so the run-up and the recovery are visible.
    ///
    /// Empty when the incident predates anything we still hold — the caller is
    /// expected to say so rather than draw a shorter window as if it were the whole
    /// episode.
    func retainedSamples(around incident: Incident, margin: Duration = .seconds(120))
        -> [HistorySample] {
        let from = incident.beganAt.addingTimeInterval(-margin.totalSeconds)
        let to = (incident.closedAt ?? Date()).addingTimeInterval(margin.totalSeconds)
        return history.samples.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    private let detector: IncidentDetector
    private var detectorState = IncidentDetector.State()
    private let cadenceController: CadenceController
    private var cadenceState = CadenceController.State()
    private let icons = ProcessIconCache()
    private let pressureMonitor = MemoryPressureMonitor()
    private let notificationGate = NotificationGate()
    private var notificationState = NotificationGate.State()
    let notifications = NotificationDelivery()
    private var previousPaging: PagingCounters?
    private var previousDisk: DiskCounters?
    private var previousOwn: UInt64?

    /// Volume capacity, read on the sampling loop rather than by the storage screen.
    ///
    /// Driven from here so the capacity series accumulates whether or not anyone is
    /// looking at it: a fortnight-long trend that only advances while the screen is
    /// open would never fill in. The screen shares this model, so opening it shows
    /// history already gathered instead of starting a new series.
    private let storage: StorageScreenModel
    private var lastStorageCheckAt: ContinuousClock.Instant?

    private let lifecycle = LifecycleTracker()
    /// Launches and exits observed since the app started, bounded to the tracker's
    /// own window (FR-045, FR-046-as-narrowed).
    private(set) var lifecycleEvents: [LifecycleEvent] = []
    /// When monitoring began, so "no relaunches" can be told apart from "we have
    /// not been watching long enough for that to mean anything".
    private(set) var monitoringStartedAt: Date?

    /// How often volume capacity is re-read.
    ///
    /// Not every sample: capacity reads touch the filesystem, and at a 2 s cadence
    /// that is filesystem work on the measurement path FR-030 budgets. Half a minute
    /// is well inside the 60 s the low-storage condition must be sustained for, so
    /// nothing is missed by reading it this way — a shortage is still seen within
    /// 30 s of appearing.
    static let storageCheckInterval: Duration = .seconds(30)

    /// Kept small: FR-005 bounds retained evidence, and the UI shows recent
    /// history rather than an archive.
    static let retainedIncidents = 20

    // MARK: - User policies (FR-016)

    /// The app's rules about applications. One store for the whole app: a policy is
    /// about an application, not about a window, so setting it in the inspector and
    /// reading it in Settings has to be the same fact. A second store would disagree
    /// with this one and the disagreement would be invisible.
    let policies: PolicyStore

    /// The single on-disk policy store, at the location the inspector already used.
    static let defaultPolicies: PolicyStore = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
        return PolicyStore(url: base?
            .appendingPathComponent("MacSlowdown", isDirectory: true)
            .appendingPathComponent("policies.json"))
    }()

    init(cadence: Duration = MetricsHistory.defaultCadence,
         history: MetricsHistory = MetricsHistory(),
         policy: IncidentPolicy = .default,
         policies: PolicyStore = MonitorStore.defaultPolicies,
         storage: StorageScreenModel = .shared) {
        self.baseCadence = cadence
        self.history = history
        self.detector = IncidentDetector(policy: policy)
        self.cadenceController = CadenceController(normalInterval: cadence)
        self.policies = policies
        self.storage = storage
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        monitoringStartedAt = Date()
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
                from: previous, to: snapshot, hostEarlier: earlierHost, hostLater: host,
                // Served from the resolver's (pid, start time) cache, so this adds
                // a dictionary lookup per contributor, not filesystem work.
                naming: { [resolver] in resolver.identity(for: $0).friendlyName })
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
            refreshStorageIfDue(now: now)
            let observation = SystemObservation(
                at: Date(),
                cpuBusyFraction: result.totalBusyPercentOfOneCore
                    / (Double(machine.logicalCores) * 100),
                memoryPressure: memoryPressure,
                thermalState: thermalState,
                lowStorage: isLowStorage)

            let event = detector.observe(observation, state: &detectorState)
            switch event {
            case .opened(let incident), .updated(let incident):
                openIncident = incident
                // The gate decides; delivery only carries out an approved decision.
                let leadingContributor = result.contributors.first?.label
                let decision = notificationGate.decide(
                    incident: incident,
                    leadingContributor: leadingContributor,
                    mute: mute,
                    // `focusActive` is deliberately left at its default. No public
                    // API reports the current Focus mode to a sandboxed app, and
                    // guessing would be a fabricated measurement. Focus is still
                    // respected — macOS enforces it at delivery, which is why this
                    // is a gap in our reasoning rather than in the behaviour. The
                    // gate's own check stands ready for a signal we can measure.
                    context: InterruptionContext(
                        audioActive: AudioSignals.isAnyProcessPlaying(),
                        audioApplication: AudioSignals.firstActiveProcessName()),
                    state: &notificationState)
                Task { [notifications] in
                    await notifications.deliver(
                        decision: decision, incident: incident,
                        leadingContributor: leadingContributor)
                }
            case .closed(let incident):
                openIncident = nil
                recentIncidents = Presentation.retained(
                    [incident] + recentIncidents, limit: Self.retainedIncidents)
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

            recordLifecycle(from: previous, to: snapshot)

            history.record(result)
            resolver.prune(keeping: Set(snapshot.records.keys))
            // Persisting history is best-effort: it is evidence, not configuration,
            // and a write failure must never interrupt monitoring.
            _ = try? history.flushIfNeeded()

            previous = snapshot
            previousHost = host
        }
    }

    // MARK: - Storage (FR-041, FR-042)

    /// Re-reads volume capacity if enough time has passed, records it, and updates
    /// the low-storage condition the detector is given.
    func refreshStorageIfDue(now: ContinuousClock.Instant) {
        if let last = lastStorageCheckAt,
           now - last < Self.storageCheckInterval { return }
        lastStorageCheckAt = now

        // `refresh` reads the volumes and appends to the capacity history, which
        // coalesces to its own quarter-hour interval. Driving it from here rather
        // than from the storage screen is what makes the fortnight trend continuous.
        storage.refresh()
        lastStorageCheck = storage.lastChecked
        isLowStorage = Self.isLowStorage(
            startupVolume: storage.startupVolume?.capacity, detector: storage.detector)
    }

    /// Whether a startup-volume reading breaches the low-storage line.
    ///
    /// No reading means no claim either way — false, because absence of a
    /// measurement is not evidence of a shortage (FR-002). Leaving a stale `true`
    /// standing would keep an incident open on evidence we no longer hold.
    nonisolated static func isLowStorage(
        startupVolume: VolumeCapacity?, detector: LowStorageDetector
    ) -> Bool {
        guard let startupVolume else { return false }
        return detector.isBelowThreshold(startupVolume)
    }

    // MARK: - Lifecycle (FR-045, FR-046 as narrowed)

    /// Records launches and exits between two consecutive snapshots.
    ///
    /// This is the real `LifecycleTracker`, keyed on `(pid, start time)`, so a
    /// recycled PID reads as one exit and one launch rather than as continuity.
    /// Nothing here implies a hang: TASK-27 established that macOS reports a stalled
    /// application exactly as it reports a healthy one.
    func recordLifecycle(from earlier: ProcessSnapshot, to later: ProcessSnapshot) {
        let events = lifecycle.events(from: earlier, to: later)
        guard !events.isEmpty || !lifecycleEvents.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-lifecycle.window.totalSeconds)
        lifecycleEvents = (lifecycleEvents + events).filter { $0.at >= cutoff }
    }

    /// How long monitoring has been running, which bounds every claim above.
    var observedDuration: Duration {
        guard let monitoringStartedAt else { return .zero }
        return .seconds(Date().timeIntervalSince(monitoringStartedAt))
    }

    /// Whether we have watched long enough for a count of zero to mean anything.
    /// Before that, zero means "we have not been looking" (FR-002).
    func hasObservedLongEnough(minimum: Duration = .seconds(120)) -> Bool {
        observedDuration.totalSeconds >= minimum.totalSeconds
    }

    /// Relaunches observed for any of these commands within the tracker's window.
    ///
    /// A relaunch is an exit *matched by* a launch of the same command, counted as
    /// `min(exits, launches)`. Exits alone would overstate it: an application the
    /// user quit and did not reopen exited once and relaunched never, and reporting
    /// that as a relaunch would be a claim the events do not support.
    ///
    /// Commands rather than identities, because a relaunched process has a new PID
    /// by construction. `p_comm` is truncated to 16 bytes, so two applications whose
    /// commands truncate to the same fragment are counted together — the
    /// low-confidence case `RelaunchPattern` already names.
    func relaunchCount(forCommands commands: Set<String>) -> Int {
        var exits: [String: Int] = [:]
        var launches: [String: Int] = [:]
        for event in lifecycleEvents where commands.contains(event.command) {
            switch event {
            case .exited: exits[event.command, default: 0] += 1
            case .launched: launches[event.command, default: 0] += 1
            }
        }
        return exits.reduce(0) { $0 + min($1.value, launches[$1.key] ?? 0) }
    }

    /// Repeated exits that rise to a pattern, for the commands given (FR-046).
    func relaunchPatterns(forCommands commands: Set<String>) -> [RelaunchPattern] {
        lifecycle.relaunchPatterns(
            in: lifecycleEvents.filter { commands.contains($0.command) })
    }
}
