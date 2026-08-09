import Foundation
import Metrics
import Observation

/// State for the storage screen (FR-041, FR-042). Design reference: 1l.
///
/// Shared rather than owned by the view, so navigating away and back does not
/// restart the capacity series or re-read it from disk. It is not part of
/// `MonitorStore` because capacity moves on a scale of days: sampling it on the
/// 2-second metrics loop would retain hundreds of thousands of readings a
/// fortnight to draw the same line.
@MainActor
@Observable
final class StorageScreenModel {
    static let shared = StorageScreenModel()

    /// Every mounted volume, measured or not.
    private(set) var volumes: [MountedVolume] = []
    /// When the volumes were last read. Nil until the first read completes —
    /// never a placeholder timestamp (FR-002).
    private(set) var lastChecked: Date?
    /// Re-read on a timer so "checked N ago" stays true without the view guessing.
    private(set) var now = Date()

    let history: StorageHistory
    let detector: LowStorageDetector

    /// How often the volume list is re-read while the screen is open. The history
    /// coalesces to its own quarter-hour interval, so this cadence costs a handful
    /// of resource-value reads and no extra disk writes.
    static let refreshInterval: Duration = .seconds(30)

    private static let includedRemovableDefaultsKey = "includedRemovableVolumes"

    /// Removable volumes the user asked us to watch (FR-041's route back in).
    private(set) var includedRemovableIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(includedRemovableIDs), forKey: Self.includedRemovableDefaultsKey)
        }
    }

    init(history: StorageHistory = .shared, detector: LowStorageDetector = LowStorageDetector()) {
        self.history = history
        self.detector = detector
        self.includedRemovableIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.includedRemovableDefaultsKey) ?? [])
        history.restore()
    }

    var startupVolume: MountedVolume? { volumes.first(where: \.isStartupVolume) }
    var otherVolumes: [MountedVolume] { volumes.filter { !$0.isStartupVolume } }

    func refresh(at date: Date = Date()) {
        volumes = VolumeInventory.mounted(includedRemovableVolumeIDs: includedRemovableIDs)
        history.record(VolumeInventory.snapshot(volumes), at: date)
        lastChecked = date
        now = date
    }

    /// Advances the clock the freshness line reads from, without re-reading.
    func tick(_ date: Date = Date()) { now = date }

    func include(_ volume: MountedVolume) {
        includedRemovableIDs.insert(volume.id)
        refresh()
    }

    func trend(for volume: MountedVolume) -> StorageTrend {
        StorageTrendAnalysis.trend(for: history.readings(forVolume: volume.id), now: now)
    }

    func readings(for volume: MountedVolume) -> [StorageReading] {
        history.readings(forVolume: volume.id)
    }

    func coveredDuration(for volume: MountedVolume) -> Duration {
        history.coveredDuration(forVolume: volume.id)
    }

    /// How this volume stands against the warning line, in words — including the
    /// case the screen exists for, where it is back above the line and still
    /// falling.
    func standing(for volume: MountedVolume, hadIncident: Bool) -> String? {
        guard let capacity = volume.capacity else { return nil }
        return StorageTrendAnalysis.standingStatement(
            trend: trend(for: volume),
            isBelowThreshold: detector.isBelowThreshold(capacity),
            hadLowStorageIncident: hadIncident)
    }
}

/// Formatting for the storage screen, kept out of the view so it can be tested
/// against the cases that matter rather than against whatever is mounted.
enum StoragePresentation {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatStyle().format(Int64(value))
    }

    /// "Checked 30 s ago". Nil before the first reading, because there is nothing
    /// truthful to say about the freshness of a value we do not have.
    static func freshness(lastChecked: Date?, now: Date) -> String? {
        guard let lastChecked else { return nil }
        let seconds = max(0, now.timeIntervalSince(lastChecked))
        if seconds < 60 { return "Checked \(Int(seconds)) s ago" }
        if seconds < 3600 { return "Checked \(Int(seconds / 60)) min ago" }
        return "Checked \(Int(seconds / 3600)) hr ago"
    }

    /// "96 GB available of 1 TB".
    static func headline(_ capacity: VolumeCapacity) -> String {
        "\(bytes(capacity.availableBytes)) available of \(bytes(capacity.totalBytes))"
    }

    /// The evidence class of a trend statement, in the same words the capacity
    /// legend uses (FR-038).
    ///
    /// A direction, a byte movement and a window are derived across many readings,
    /// so `.declining` / `.rising` / `.steady` are calculations. `.insufficientHistory`
    /// is not: it reports how many readings exist and how long they span, which is
    /// a count of measurements and nothing more. `StorageTrend.isCalculated` is the
    /// framework's own answer to that question and this must not second-guess it.
    static func trendProvenance(_ trend: StorageTrend) -> String {
        trend.isCalculated ? "Calculated" : "Measured"
    }

    /// The purgeable figure, always with the caveat attached to it rather than
    /// somewhere else on the screen (FR-041).
    static func purgeable(_ capacity: VolumeCapacity) -> String? {
        guard let purgeable = capacity.purgeableEstimateBytes else { return nil }
        return "Purgeable, roughly \(bytes(purgeable)) — an estimate, not space you have"
    }
}
