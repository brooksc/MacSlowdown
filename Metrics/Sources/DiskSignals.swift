import Foundation
import IOKit
import IOKit.storage

/// Cumulative disk byte counters, summed across block storage drivers.
///
/// **Lifetime totals, never rates.** Per-process I/O is not obtainable at all —
/// `proc_pid_rusage` is denied under App Sandbox — so this is machine-wide only,
/// and FR-009 was narrowed to match in spec v1.2.
public struct DiskCounters: Sendable, Equatable {
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    /// How many block storage drivers contributed. Zero means we could read none.
    ///
    /// Part of what makes two readings comparable: the counters are a sum across
    /// devices, so a different set of devices is a different sum (see `rates`).
    public let deviceCount: Int

    public init(bytesRead: UInt64, bytesWritten: UInt64, deviceCount: Int) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.deviceCount = deviceCount
    }
}

public struct DiskRates: Sendable, Equatable {
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double

    public static let zero = DiskRates(readBytesPerSecond: 0, writeBytesPerSecond: 0)
}

public enum DiskSignals {
    /// Aggregate byte counters from the IORegistry.
    ///
    /// Returns nil if no block storage driver could be read at all, which is the
    /// honest answer rather than reporting zero bytes — zero would mean an idle
    /// disk, not an unavailable measurement (FR-002).
    public static func counters() -> DiskCounters? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var devices = 0

        while case let drive = IOIteratorNext(iterator), drive != 0 {
            defer { IOObjectRelease(drive) }

            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                drive, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                let statistics = properties[kIOBlockStorageDriverStatisticsKey] as? [String: Any]
            else { continue }

            // Absent keys mean this driver does not report that direction, which is
            // not the same as reporting zero; skip rather than invent a value.
            if let value = statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber {
                read += value.uint64Value
            }
            if let value = statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber {
                written += value.uint64Value
            }
            devices += 1
        }

        guard devices > 0 else { return nil }
        return DiskCounters(bytesRead: read, bytesWritten: written, deviceCount: devices)
    }

    /// Throughput between two counter readings.
    ///
    /// As with paging, a rate only ever comes from a delta over a measured
    /// interval, and a counter that goes backwards (device removed, counter
    /// reset) reports zero rather than an underflowed spike.
    public static func rates(
        from earlier: DiskCounters,
        to later: DiskCounters,
        seconds: Double
    ) -> DiskRates? {
        guard seconds > 0 else { return nil }

        // A different set of devices means these two readings are not two readings
        // of the same thing. Mount a drive between samples and the aggregate jumps
        // by that drive's entire lifetime byte count, which divided by one second
        // reads as hundreds of gigabytes per second — a fabricated measurement of
        // the most alarming kind (FR-002). Unmounting one loses a device's history
        // and looks like a counter reset.
        //
        // "No rate" is the honest answer across a topology change, and every
        // surface already renders nil as unavailable. One sample is lost; nothing
        // is invented. `deviceCount` was captured for exactly this and was never
        // consulted.
        guard later.deviceCount == earlier.deviceCount else { return nil }

        func rate(_ old: UInt64, _ new: UInt64) -> Double {
            guard new >= old else { return 0 }
            return Double(new - old) / seconds
        }

        return DiskRates(
            readBytesPerSecond: rate(earlier.bytesRead, later.bytesRead),
            writeBytesPerSecond: rate(earlier.bytesWritten, later.bytesWritten)
        )
    }

    /// The sentence that must accompany disk figures, since a user will reasonably
    /// expect to see which application is responsible (FR-009).
    public static let perApplicationUnavailable =
        "Disk activity is shown for the whole Mac. macOS does not report "
        + "per-application disk activity to App Store apps, so it cannot be broken "
        + "down by app."
}
