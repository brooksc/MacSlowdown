import Darwin
import Foundation

/// Machine-wide CPU tick counters, summed across all cores.
public struct HostCPUSample: Sendable {
    /// user + system + nice ticks.
    public let busy: UInt64
    /// busy + idle ticks.
    public let total: UInt64
}

public enum HostCPU {
    /// Aggregate CPU counters. Available under App Sandbox — `host_processor_info`
    /// is a host-level call and is not subject to the per-process restrictions.
    public static func sample() -> HostCPUSample? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount
        ) == KERN_SUCCESS, let info else { return nil }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return HostCPUSample(busy: busy, total: total)
    }

    /// Fraction of total machine capacity that was busy between two samples, 0...1.
    ///
    /// A rate from the difference of two cumulative counters, never from a single
    /// reading. Returns nil when the interval carries no ticks.
    public static func busyFraction(from earlier: HostCPUSample, to later: HostCPUSample) -> Double? {
        let busyDelta = later.busy >= earlier.busy ? later.busy - earlier.busy : 0
        let totalDelta = later.total >= earlier.total ? later.total - earlier.total : 0
        guard totalDelta > 0 else { return nil }
        return min(1.0, Double(busyDelta) / Double(totalDelta))
    }
}
