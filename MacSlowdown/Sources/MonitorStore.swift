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
    private(set) var attribution: CPUAttribution?
    private(set) var families: [ProcessFamily] = []
    private(set) var freshness: Freshness = .current
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
    private let cadence: Duration
    private var task: Task<Void, Never>?

    init(cadence: Duration = MetricsHistory.defaultCadence,
         history: MetricsHistory = MetricsHistory()) {
        self.cadence = cadence
        self.history = history
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func run() async {
        var previous = sampler.snapshot()
        var previousHost = HostCPU.sample()
        let clock = ContinuousClock()
        var lastSampleAt = clock.now

        while !Task.isCancelled {
            try? await Task.sleep(for: cadence)
            if Task.isCancelled { return }

            let snapshot = sampler.snapshot()
            let host = HostCPU.sample()
            let now = clock.now

            // If the interval ran materially long the machine was too busy to
            // sample on time; surface that rather than presenting a late reading
            // as current.
            let elapsed = now - lastSampleAt
            let overdue = elapsed.totalSeconds > cadence.totalSeconds * 2
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
            freshness = overdue ? .stale(age: elapsed) : .current
            lastUpdate = Date()

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
