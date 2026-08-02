import Darwin
import Foundation

/// CPU usage for one process over an interval.
public struct ProcessCPUUsage: Sendable {
    public let identity: ProcessIdentity
    public let command: String
    /// Share of a single core. 100% means one core fully busy; a process using two
    /// cores reads 200%. Divide by the logical core count for a machine-relative
    /// figure (FR-004).
    public let percentOfOneCore: Double
    public let residentBytes: UInt64
}

public enum CPUUsage {
    /// CPU usage between two snapshots.
    ///
    /// Rates come only from the difference between two cumulative counters over a
    /// measured interval — a cumulative total is never itself a rate (FR-006,
    /// FR-009). Processes are matched on `ProcessIdentity`, so a reused PID cannot
    /// be mistaken for continuity of the same process.
    ///
    /// Processes absent from either snapshot, or whose metrics were denied in
    /// either, are excluded: their usage is real but unattributable, and belongs in
    /// the unattributed bucket rather than being silently counted as zero.
    public static func between(
        _ earlier: ProcessSnapshot,
        _ later: ProcessSnapshot
    ) -> [ProcessCPUUsage] {
        let elapsed = (later.takenAt - earlier.takenAt).totalSeconds
        guard elapsed > 0 else { return [] }
        let elapsedNanos = elapsed * 1e9

        var usage: [ProcessCPUUsage] = []
        usage.reserveCapacity(later.records.count)

        for (identity, new) in later.records {
            guard let old = earlier.records[identity],
                  let newMetrics = new.measurements,
                  let oldMetrics = old.measurements
            else { continue }

            // Counters are monotonic for a live process. A decrease means the
            // identity was somehow reused or the kernel reset the counter; treat it
            // as no measurable work rather than emitting a negative or wrapped rate.
            guard newMetrics.cpuTicks >= oldMetrics.cpuTicks else { continue }

            let deltaNanos = MachTime.nanos(fromTicks: newMetrics.cpuTicks - oldMetrics.cpuTicks)
            usage.append(ProcessCPUUsage(
                identity: identity,
                command: new.command,
                percentOfOneCore: deltaNanos / elapsedNanos * 100,
                residentBytes: newMetrics.residentBytes
            ))
        }
        return usage
    }
}

/// Machine topology needed to present CPU numbers correctly (FR-004).
public enum MachineTopology {
    public static let logicalCoreCount: Int = {
        var count = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname("hw.logicalcpu", &count, &size, nil, 0) == 0, count > 0 else {
            return 1
        }
        return count
    }()
}
