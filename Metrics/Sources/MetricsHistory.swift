import Foundation
import Synchronization

/// One retained sample of the machine's state.
///
/// Deliberately small and flat. FR-005 asks for aggregate and *leading-contributor*
/// metrics, not the whole process table — retaining every process every interval
/// would blow both the memory and disk budgets in FR-030 for evidence nobody reads.
public struct HistorySample: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let totalBusyPercentOfOneCore: Double
    public let attributedPercentOfOneCore: Double
    public let unattributedPercentOfOneCore: Double
    public let topContributors: [ContributorSummary]

    public init(
        timestamp: Date,
        totalBusyPercentOfOneCore: Double,
        attributedPercentOfOneCore: Double,
        unattributedPercentOfOneCore: Double,
        topContributors: [ContributorSummary]
    ) {
        self.timestamp = timestamp
        self.totalBusyPercentOfOneCore = totalBusyPercentOfOneCore
        self.attributedPercentOfOneCore = attributedPercentOfOneCore
        self.unattributedPercentOfOneCore = unattributedPercentOfOneCore
        self.topContributors = topContributors
    }
}

public struct ContributorSummary: Sendable, Codable, Equatable {
    public let pid: pid_t
    public let startTime: UInt64
    public let command: String
    public let percentOfOneCore: Double
    public let residentBytes: UInt64

    public init(pid: pid_t, startTime: UInt64, command: String,
                percentOfOneCore: Double, residentBytes: UInt64) {
        self.pid = pid
        self.startTime = startTime
        self.command = command
        self.percentOfOneCore = percentOfOneCore
        self.residentBytes = residentBytes
    }

    public init(_ usage: ProcessCPUUsage) {
        self.init(
            pid: usage.identity.pid,
            startTime: usage.identity.startTime,
            command: usage.command,
            percentOfOneCore: usage.percentOfOneCore,
            residentBytes: usage.residentBytes
        )
    }
}

public enum HistoryPersistence: Sendable, Equatable {
    /// History is lost on quit. Writes nothing to disk (FR-029 default-local, and
    /// the cheapest option against the FR-030 disk budget).
    case memoryOnly
    /// History survives a restart, flushed no more often than `flushInterval`.
    case acrossRestarts(url: URL, flushInterval: Duration)

    /// Persistence at the default flush interval, which is sized to the FR-030
    /// disk budget.
    public static func acrossRestarts(url: URL) -> HistoryPersistence {
        .acrossRestarts(url: url, flushInterval: MetricsHistory.defaultFlushInterval)
    }
}

/// Bounded rolling history of aggregate and leading-contributor metrics (FR-005).
///
/// A fixed-capacity ring: appending past capacity evicts the oldest sample, so
/// memory is bounded by construction rather than by a policy that has to be
/// enforced elsewhere.
public final class MetricsHistory: Sendable {
    public static let defaultRetention: Duration = .seconds(15 * 60)
    public static let defaultCadence: Duration = .seconds(2)
    public static let defaultTopContributorCount = 5

    /// How often persisted history is rewritten.
    ///
    /// Chosen against the FR-030 budget rather than by taste. Persisting is a
    /// whole-file rewrite, and a full 15-minute window encodes to roughly 300 KB,
    /// so flushing every minute would cost ~19 MB/hour — nearly double the 10 MB
    /// allowed. At five minutes it is ~3.6 MB/hour, comfortably inside it.
    ///
    /// The cost of the longer interval is losing at most five minutes of history
    /// to an unclean termination. That is acceptable for evidence: the app flushes
    /// on quit, and history is not configuration.
    public static let defaultFlushInterval: Duration = .seconds(5 * 60)

    private struct State {
        var samples: [HistorySample] = []
        var lastFlush: Date?
        var pendingWrite = false
    }

    private let state = Mutex(State())
    public let capacity: Int
    public let retention: Duration
    public let topContributorCount: Int
    public let persistence: HistoryPersistence

    public init(
        retention: Duration = MetricsHistory.defaultRetention,
        cadence: Duration = MetricsHistory.defaultCadence,
        topContributorCount: Int = MetricsHistory.defaultTopContributorCount,
        persistence: HistoryPersistence = .memoryOnly
    ) {
        self.retention = retention
        self.topContributorCount = topContributorCount
        self.persistence = persistence
        // +1 so the buffer spans the full retention window rather than one sample
        // short of it.
        self.capacity = max(1, Int((retention.totalSeconds / cadence.totalSeconds).rounded()) + 1)
    }

    public var sampleCount: Int { state.withLock { $0.samples.count } }
    public var samples: [HistorySample] { state.withLock { $0.samples } }

    /// Wall-clock span currently retained.
    public var coveredDuration: Duration {
        state.withLock { state in
            guard let first = state.samples.first, let last = state.samples.last else {
                return .zero
            }
            return .seconds(last.timestamp.timeIntervalSince(first.timestamp))
        }
    }

    public func append(_ sample: HistorySample) {
        state.withLock { state in
            state.samples.append(sample)
            if state.samples.count > capacity {
                state.samples.removeFirst(state.samples.count - capacity)
            }
        }
    }

    /// Records an attribution result, keeping only the leading contributors.
    public func record(_ attribution: CPUAttribution, at timestamp: Date = Date()) {
        append(HistorySample(
            timestamp: timestamp,
            totalBusyPercentOfOneCore: attribution.totalBusyPercentOfOneCore,
            attributedPercentOfOneCore: attribution.attributedPercentOfOneCore,
            unattributedPercentOfOneCore: attribution.unattributedPercentOfOneCore,
            topContributors: attribution.contributors
                .prefix(topContributorCount)
                .map(ContributorSummary.init)
        ))
    }

    public func removeAll() {
        state.withLock { $0.samples.removeAll() }
    }

    // MARK: - Persistence

    /// Writes history to disk if persistence is enabled and the flush interval has
    /// elapsed.
    ///
    /// Batched deliberately: writing every sample would multiply disk traffic by
    /// the sample rate for no benefit, and FR-030 caps writes at 10 MB/hour absent
    /// incidents. Returns the number of bytes written, or zero if skipped.
    @discardableResult
    public func flushIfNeeded(now: Date = Date()) throws -> Int {
        guard case .acrossRestarts(let url, let interval) = persistence else { return 0 }

        let due = state.withLock { state -> Bool in
            guard let last = state.lastFlush else { return true }
            return now.timeIntervalSince(last) >= interval.totalSeconds
        }
        guard due else { return 0 }

        let snapshot = samples
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        state.withLock { $0.lastFlush = now }
        return data.count
    }

    /// Restores history written by a previous run. Missing or unreadable state is
    /// not an error — history is evidence, not configuration, and losing it must
    /// never block startup.
    public func restore() {
        guard case .acrossRestarts(let url, _) = persistence,
              let data = try? Data(contentsOf: url),
              let restored = try? JSONDecoder().decode([HistorySample].self, from: data)
        else { return }

        state.withLock { state in
            state.samples = Array(restored.suffix(capacity))
        }
    }
}
