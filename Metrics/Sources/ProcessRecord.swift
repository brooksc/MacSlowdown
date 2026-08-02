import Darwin
import Foundation

/// Stable identity for a process.
///
/// PIDs are reused, so a PID alone is not an identity — a short-lived process can
/// hand its number to an unrelated one within a single sampling interval. Pairing
/// the PID with its start time is what lets application-family history survive PID
/// replacement (FR-043, FR-045) and prevents two unrelated processes being merged.
public struct ProcessIdentity: Hashable, Sendable {
    public let pid: pid_t
    /// Start time in microseconds since the epoch, from `kinfo_proc.kp_proc.p_starttime`.
    public let startTime: UInt64

    public init(pid: pid_t, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

/// Per-process resource measurements, in the units the kernel reports them.
public struct ProcessMetrics: Sendable, Equatable {
    /// Cumulative user + system CPU time in **mach absolute time units**, not
    /// nanoseconds. Convert with `MachTime`. This is a monotonic counter — a rate
    /// only ever comes from the difference between two samples.
    public let cpuTicks: UInt64
    /// Resident size. Not phys_footprint, which needs `proc_pid_rusage` and is
    /// denied under App Sandbox. Activity Monitor's "Memory" column shows
    /// footprint, so these numbers legitimately differ from it.
    public let residentBytes: UInt64

    public init(cpuTicks: UInt64, residentBytes: UInt64) {
        self.cpuTicks = cpuTicks
        self.residentBytes = residentBytes
    }
}

/// Why a process has no measurements.
///
/// FR-002 requires unavailable values to be labeled rather than omitted, so this
/// is an explicit case rather than an optional. A denied process still has a name,
/// PID, parent and start time — we can say what is running even when we cannot say
/// what it is using.
public enum MetricsResult: Sendable, Equatable {
    case measured(ProcessMetrics)
    /// `EPERM`. Owned by another user, typically a protected system process such as
    /// WindowServer, mds_stores, backupd or launchd. Denied identically whether or
    /// not we are sandboxed — the limit is uid, not the sandbox.
    case notPermitted
    /// `ESRCH`. The process exited between enumeration and the metrics read.
    case exited
    /// The call failed for some other reason; the raw errno is preserved so it can
    /// be reported rather than silently treated as zero.
    case failed(errno: Int32)
}

/// One process as observed in a single sweep.
public struct ProcessRecord: Sendable {
    public let identity: ProcessIdentity
    /// `p_comm` from the process table. Truncated to 16 bytes by the kernel, but
    /// always available — including for processes whose metrics are denied.
    public let command: String
    public let uid: uid_t
    public let ppid: pid_t
    public let metrics: MetricsResult

    public var measurements: ProcessMetrics? {
        if case .measured(let m) = metrics { return m }
        return nil
    }

    /// True when this process contributes to attributed totals. Everything else is
    /// visible by name but its usage belongs in the unattributed bucket.
    public var isMeasurable: Bool { measurements != nil }
}

/// One complete pass over the process table.
public struct ProcessSnapshot: Sendable {
    public let records: [ProcessIdentity: ProcessRecord]
    /// Monotonic instant the sweep began. Rates use this, never wall clock, which
    /// can jump.
    public let takenAt: ContinuousClock.Instant
    /// How long the sweep itself took — the number FR-030's overhead budget is
    /// measured against.
    public let sweepDuration: Duration

    public init(
        records: [ProcessIdentity: ProcessRecord],
        takenAt: ContinuousClock.Instant,
        sweepDuration: Duration
    ) {
        self.records = records
        self.takenAt = takenAt
        self.sweepDuration = sweepDuration
    }

    public var measurableCount: Int { records.values.count(where: \.isMeasurable) }
    public var notMeasurableCount: Int { records.count - measurableCount }
}
