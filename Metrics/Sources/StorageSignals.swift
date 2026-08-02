import Foundation

/// Capacity for one mounted volume (FR-041).
public struct VolumeCapacity: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: String
    public let isStartupVolume: Bool
    public let isRemovable: Bool
    public let isNetwork: Bool

    public let totalBytes: UInt64
    /// Space available right now, without macOS purging anything.
    public let availableBytes: UInt64
    /// Space macOS believes it could make available by purging caches and other
    /// reclaimable content.
    ///
    /// **An estimate, not space you have.** macOS may not release it, and treating
    /// it as free is the specific error FR-041 calls out.
    public let purgeableEstimateBytes: UInt64?

    public var id: String { url.path }
    public var usedBytes: UInt64 { totalBytes >= availableBytes ? totalBytes - availableBytes : 0 }
    public var availableFraction: Double {
        totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0
    }
}

/// A volume we could see but not measure. Listed rather than hidden, so the user
/// knows the picture is incomplete (FR-041, FR-002).
public struct UnreadableVolume: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: String
    public let isNetwork: Bool
    public var id: String { url.path }

    public var explanation: String {
        isNetwork
            ? "Network volumes are not reported to App Store apps."
            : "This volume did not report its capacity."
    }
}

public struct StorageSnapshot: Sendable {
    public let volumes: [VolumeCapacity]
    public let unreadable: [UnreadableVolume]
    public var startupVolume: VolumeCapacity? { volumes.first { $0.isStartupVolume } }
}

public enum StorageSignals {
    /// The purgeable estimate must never be presented as available space.
    public static let purgeableCaveat =
        "Purgeable space is an estimate of what macOS thinks it could reclaim. "
        + "It is not space you have, and macOS may not release it."

    public static func snapshot(
        includeRemovable: Bool = false,
        fileManager: FileManager = .default
    ) -> StorageSnapshot {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey,
        ]
        let mounted = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]) ?? []

        var volumes: [VolumeCapacity] = []
        var unreadable: [UnreadableVolume] = []

        for url in mounted {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.volumeName ?? url.lastPathComponent
            let isNetwork = !(values?.volumeIsLocal ?? true)
            let isRemovable = values?.volumeIsRemovable ?? false
            let isStartup = url.path == "/"

            if !includeRemovable, isRemovable, !isStartup { continue }

            guard let total = values?.volumeTotalCapacity, total > 0,
                  let available = values?.volumeAvailableCapacity
            else {
                unreadable.append(UnreadableVolume(url: url, name: name, isNetwork: isNetwork))
                continue
            }

            // availableCapacityForImportantUsage includes what macOS would purge,
            // so the difference is the purgeable estimate.
            var purgeable: UInt64?
            if let important = values?.volumeAvailableCapacityForImportantUsage,
               important > Int64(available) {
                purgeable = UInt64(important) - UInt64(available)
            }

            volumes.append(VolumeCapacity(
                url: url,
                name: name,
                isStartupVolume: isStartup,
                isRemovable: isRemovable,
                isNetwork: isNetwork,
                totalBytes: UInt64(total),
                availableBytes: UInt64(available),
                purgeableEstimateBytes: purgeable
            ))
        }

        return StorageSnapshot(volumes: volumes, unreadable: unreadable)
    }
}

/// Sustained low-storage detection (FR-042).
///
/// Requires the condition to persist, so a transient measurement anomaly does not
/// raise an incident — the same duration discipline FR-006 applies to CPU.
public struct LowStorageDetector: Sendable {
    public let fractionThreshold: Double
    public let absoluteThresholdBytes: UInt64
    public let requiredDuration: Duration

    public init(
        fractionThreshold: Double = 0.10,
        absoluteThresholdBytes: UInt64 = 5 * 1_073_741_824,
        requiredDuration: Duration = .seconds(60)
    ) {
        self.fractionThreshold = fractionThreshold
        self.absoluteThresholdBytes = absoluteThresholdBytes
        self.requiredDuration = requiredDuration
    }

    /// Both a proportional and an absolute safeguard, as FR-042 requires: 10% of a
    /// 4 TB disk is 400 GB and not a problem, while 10% of a 128 GB disk is.
    public func isBelowThreshold(_ volume: VolumeCapacity) -> Bool {
        volume.availableFraction < fractionThreshold
            && volume.availableBytes < absoluteThresholdBytes
    }

    /// Whether a run of readings sustains the condition for long enough to count.
    public func isSustained(
        readings: [(volume: VolumeCapacity, at: Date)]
    ) -> Bool {
        guard let first = readings.first, let last = readings.last else { return false }
        guard readings.allSatisfy({ isBelowThreshold($0.volume) }) else { return false }
        return last.at.timeIntervalSince(first.at) >= requiredDuration.totalSeconds
    }
}
