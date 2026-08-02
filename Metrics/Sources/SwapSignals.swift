import Darwin
import Foundation

/// Swap file usage, as macOS reports it.
public struct SwapUsage: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let available: UInt64
    public let encrypted: Bool

    /// Swap existing is not itself a problem — macOS swaps opportunistically and a
    /// non-zero figure on a healthy Mac is normal. What matters is whether it is
    /// *growing*, which needs two samples.
    public var isInUse: Bool { used > 0 }
}

/// Cumulative paging counters. **Monotonic totals, never rates.**
///
/// Every field here is a lifetime count since boot. Presenting one as a current
/// rate is the specific error FR-008 forbids, which is why the type name says
/// "counters" and the rate type is separate.
public struct PagingCounters: Sendable, Equatable {
    public let pageIns: UInt64
    public let pageOuts: UInt64
    public let swapIns: UInt64
    public let swapOuts: UInt64
    public let compressions: UInt64
    public let decompressions: UInt64
}

/// Per-second rates, which only ever come from the difference between two
/// `PagingCounters` over a measured interval.
public struct PagingRates: Sendable, Equatable {
    public let pageInsPerSecond: Double
    public let pageOutsPerSecond: Double
    public let swapInsPerSecond: Double
    public let swapOutsPerSecond: Double
    public let compressionsPerSecond: Double
    public let decompressionsPerSecond: Double

    /// True when the machine is moving memory to or from disk, which is the
    /// activity that actually correlates with a slowdown.
    public var isSwapping: Bool { swapInsPerSecond > 0 || swapOutsPerSecond > 0 }

    public static let zero = PagingRates(
        pageInsPerSecond: 0, pageOutsPerSecond: 0,
        swapInsPerSecond: 0, swapOutsPerSecond: 0,
        compressionsPerSecond: 0, decompressionsPerSecond: 0)
}

public enum SwapSignals {
    /// Swap usage via `sysctl vm.swapusage`. Available under App Sandbox.
    public static func swapUsage() -> SwapUsage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0 else { return nil }
        return SwapUsage(
            total: usage.xsu_total,
            used: usage.xsu_used,
            available: usage.xsu_avail,
            encrypted: usage.xsu_encrypted != 0
        )
    }

    /// Cumulative paging counters from `host_statistics64`.
    public static func pagingCounters() -> PagingCounters? {
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return PagingCounters(
            pageIns: stats.pageins,
            pageOuts: stats.pageouts,
            swapIns: stats.swapins,
            swapOuts: stats.swapouts,
            compressions: stats.compressions,
            decompressions: stats.decompressions
        )
    }

    /// Rates between two counter readings.
    ///
    /// Returns `nil` for a non-positive interval rather than dividing by zero.
    /// A counter that has gone *backwards* means the machine rebooted or the
    /// counter wrapped; that field reports zero rather than a spike, because a
    /// wrapped delta is not a measurement and must not be shown as one.
    public static func rates(
        from earlier: PagingCounters,
        to later: PagingCounters,
        seconds: Double
    ) -> PagingRates? {
        guard seconds > 0 else { return nil }

        func rate(_ old: UInt64, _ new: UInt64) -> Double {
            guard new >= old else { return 0 }  // reset or wrap: not a measurement
            return Double(new - old) / seconds
        }

        return PagingRates(
            pageInsPerSecond: rate(earlier.pageIns, later.pageIns),
            pageOutsPerSecond: rate(earlier.pageOuts, later.pageOuts),
            swapInsPerSecond: rate(earlier.swapIns, later.swapIns),
            swapOutsPerSecond: rate(earlier.swapOuts, later.swapOuts),
            compressionsPerSecond: rate(earlier.compressions, later.compressions),
            decompressionsPerSecond: rate(earlier.decompressions, later.decompressions)
        )
    }
}
