import Foundation

/// Where a volume lives, for the label beside its name.
public enum VolumeKind: String, Sendable, Equatable {
    case startup, internalDisk, external, removable, network

    public var label: String {
        switch self {
        case .startup: "Startup volume"
        case .internalDisk: "Internal"
        case .external: "External"
        case .removable: "Removable"
        case .network: "Network"
        }
    }
}

/// What we know about a mounted volume.
///
/// Three cases, and every mounted volume is in exactly one of them. There is no
/// fourth case for "left out": a volume we cannot read and a volume we chose not
/// to watch both appear, because a storage picture that silently drops rows is
/// wrong rather than incomplete (FR-002, FR-010, FR-041).
public enum VolumeState: Sendable, Equatable {
    case measured(VolumeCapacity)
    /// Mounted, but it did not report capacity we could use.
    case unreadable(reason: String)
    /// Deliberately not watched, with the reason and the fact it can be included.
    case excluded(reason: String)
}

public struct MountedVolume: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: String
    public let kind: VolumeKind
    /// The filesystem as macOS describes it — "APFS", "SMB" — or nil when the
    /// volume did not report one. Never guessed from the path.
    public let formatDescription: String?
    public let state: VolumeState

    public var id: String { url.path }
    public var isStartupVolume: Bool { kind == .startup }

    public var capacity: VolumeCapacity? {
        if case .measured(let capacity) = state { return capacity }
        return nil
    }

    /// "Startup volume · APFS · internal", omitting whatever was not reported.
    public func subtitle(isInternal: Bool?) -> String {
        var parts = [kind.label]
        if let formatDescription { parts.append(formatDescription) }
        if let isInternal, kind == .startup { parts.append(isInternal ? "internal" : "external") }
        return parts.joined(separator: " · ")
    }
}

/// Every mounted volume, in one list (FR-041).
///
/// `StorageSignals.snapshot` answers "what can we measure", and drops removable
/// volumes that monitoring excludes. This answers the different question the
/// storage screen asks — "what is mounted, and what do we know about each" — so
/// excluded and unreadable volumes carry their reason instead of vanishing.
public enum VolumeInventory {
    static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey,
        .volumeLocalizedFormatDescriptionKey,
    ]

    /// Removable volumes are not watched by default: a disk that is plugged in
    /// for ten minutes has no useful capacity history, and watching one the user
    /// did not ask about is surprising. They are listed as excluded, with a way in.
    public static let removableExclusionReason = "Excluded from monitoring"

    public static func mounted(
        includedRemovableVolumeIDs: Set<String> = [],
        fileManager: FileManager = .default
    ) -> [MountedVolume] {
        let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]) ?? []

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let name = values?.volumeName ?? url.lastPathComponent
            let isStartup = url.path == "/"
            let isNetwork = !(values?.volumeIsLocal ?? true)
            let isRemovable = (values?.volumeIsRemovable ?? false)
                || (values?.volumeIsEjectable ?? false)
            let isInternal = values?.volumeIsInternal

            let kind: VolumeKind =
                if isStartup { .startup }
                else if isNetwork { .network }
                else if isRemovable { .removable }
                else if isInternal == false { .external }
                else { .internalDisk }

            let state = self.state(
                url: url, name: name, values: values, kind: kind,
                isStartup: isStartup, isNetwork: isNetwork, isRemovable: isRemovable,
                included: includedRemovableVolumeIDs.contains(url.path))

            return MountedVolume(
                url: url, name: name, kind: kind,
                formatDescription: values?.volumeLocalizedFormatDescription,
                state: state)
        }
    }

    private static func state(
        url: URL, name: String, values: URLResourceValues?, kind: VolumeKind,
        isStartup: Bool, isNetwork: Bool, isRemovable: Bool, included: Bool
    ) -> VolumeState {
        if isRemovable, !isStartup, !included {
            return .excluded(reason: removableExclusionReason)
        }
        guard let total = values?.volumeTotalCapacity, total > 0,
              let available = values?.volumeAvailableCapacity
        else {
            // The network wording is specific because the cause is specific, and
            // a user who sees "did not report its capacity" for a file server
            // would reasonably think the app is broken.
            return .unreadable(
                reason: UnreadableVolume(url: url, name: name, isNetwork: isNetwork).explanation)
        }

        var purgeable: UInt64?
        if let important = values?.volumeAvailableCapacityForImportantUsage,
           important > Int64(available) {
            purgeable = UInt64(important) - UInt64(available)
        }

        return .measured(VolumeCapacity(
            url: url, name: name, isStartupVolume: isStartup,
            isRemovable: isRemovable, isNetwork: isNetwork,
            totalBytes: UInt64(total), availableBytes: UInt64(available),
            purgeableEstimateBytes: purgeable))
    }

    /// The measurable volumes, as a snapshot the history and detector consume.
    public static func snapshot(_ volumes: [MountedVolume]) -> StorageSnapshot {
        StorageSnapshot(
            volumes: volumes.compactMap(\.capacity),
            unreadable: volumes.compactMap { volume in
                guard case .unreadable = volume.state else { return nil }
                return UnreadableVolume(
                    url: volume.url, name: volume.name, isNetwork: volume.kind == .network)
            })
    }
}
