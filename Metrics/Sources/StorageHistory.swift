import Foundation
import Synchronization

/// One measured reading of a volume's capacity at a point in time.
///
/// Every field is a measurement. Nothing here is interpolated: a gap in the series
/// is a period when the app was not running, and it stays a gap rather than being
/// filled in (FR-002).
public struct StorageReading: Sendable, Codable, Equatable {
    /// The volume's mount path, which is how `VolumeCapacity.id` identifies it.
    public let volumeID: String
    public let timestamp: Date
    public let availableBytes: UInt64
    public let totalBytes: UInt64

    public init(volumeID: String, timestamp: Date, availableBytes: UInt64, totalBytes: UInt64) {
        self.volumeID = volumeID
        self.timestamp = timestamp
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }

    public init(_ volume: VolumeCapacity, at timestamp: Date) {
        self.init(volumeID: volume.id, timestamp: timestamp,
                  availableBytes: volume.availableBytes, totalBytes: volume.totalBytes)
    }
}

/// A bounded, persisted series of capacity readings per volume.
///
/// Separate from `MetricsHistory` because the two have nothing in common but the
/// word history: CPU history is a 15-minute ring at a 2-second cadence held for
/// incident evidence, while a capacity slide is only visible over days. Storage is
/// therefore recorded at a quarter-hour cadence and retained for two weeks.
///
/// **Disk cost against FR-030.** One reading encodes to roughly 130 bytes, so a
/// full two weeks for one volume is about 175 KB. The file is rewritten whenever a
/// reading is appended — four times an hour — which is under 1 MB/hour against the
/// 10 MB/hour budget, and only that high on the first pass; a young history is a
/// fraction of the size.
public final class StorageHistory: Sendable {
    public static let defaultRetention: Duration = .seconds(14 * 24 * 3600)
    /// The shortest gap between two retained readings for the same volume.
    ///
    /// Capacity moves slowly. Sampling it at the metrics cadence would retain
    /// 600,000 readings a fortnight to show the same curve.
    public static let defaultMinimumInterval: Duration = .seconds(15 * 60)

    public let retention: Duration
    public let minimumInterval: Duration
    /// Where the series is persisted, or nil for a memory-only history.
    public let fileURL: URL?

    private let readingsByVolume = Mutex<[String: [StorageReading]]>([:])

    public init(
        retention: Duration = StorageHistory.defaultRetention,
        minimumInterval: Duration = StorageHistory.defaultMinimumInterval,
        fileURL: URL? = nil
    ) {
        self.retention = retention
        self.minimumInterval = minimumInterval
        self.fileURL = fileURL
    }

    /// The app's own history file, inside its container.
    public static let defaultFileURL: URL? = {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appending(path: "MacSlowdown/storage-history.json")
    }()

    /// The process-wide history, so the series does not restart when a view does.
    public static let shared = StorageHistory(fileURL: StorageHistory.defaultFileURL)

    // MARK: - Recording

    /// Records the readable volumes of a snapshot, honouring the minimum interval.
    ///
    /// Returns the readings actually appended, which is empty when it is simply
    /// too soon since the last one.
    @discardableResult
    public func record(_ snapshot: StorageSnapshot, at now: Date = Date()) -> [StorageReading] {
        let appended = readingsByVolume.withLock { store -> [StorageReading] in
            var appended: [StorageReading] = []
            for volume in snapshot.volumes {
                var series = store[volume.id] ?? []
                if let last = series.last,
                   now.timeIntervalSince(last.timestamp) < minimumInterval.totalSeconds {
                    continue
                }
                let reading = StorageReading(volume, at: now)
                series.append(reading)
                store[volume.id] = Self.pruned(series, retention: retention, now: now)
                appended.append(reading)
            }
            return appended
        }
        if !appended.isEmpty { persist() }
        return appended
    }

    private static func pruned(
        _ series: [StorageReading], retention: Duration, now: Date
    ) -> [StorageReading] {
        let cutoff = now.addingTimeInterval(-retention.totalSeconds)
        return series.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Reading

    public func readings(forVolume id: String) -> [StorageReading] {
        readingsByVolume.withLock { $0[id] ?? [] }.sorted { $0.timestamp < $1.timestamp }
    }

    /// The wall-clock span actually recorded for a volume — the honest answer to
    /// "how far back does this chart go", which is never assumed to be the
    /// retention window.
    public func coveredDuration(forVolume id: String) -> Duration {
        let series = readings(forVolume: id)
        guard let first = series.first, let last = series.last else { return .zero }
        return .seconds(last.timestamp.timeIntervalSince(first.timestamp))
    }

    public func removeAll() {
        readingsByVolume.withLock { $0.removeAll() }
        persist()
    }

    // MARK: - Persistence

    /// Best-effort: a capacity series is evidence, not configuration, and a write
    /// failure must never interrupt anything.
    public func persist() {
        guard let fileURL else { return }
        let snapshot = readingsByVolume.withLock { $0 }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Restores a series written by a previous run. Missing or unreadable state
    /// leaves the history empty, which the UI reports as "no history yet" rather
    /// than as a flat line.
    public func restore(now: Date = Date()) {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let restored = try? JSONDecoder().decode([String: [StorageReading]].self, from: data)
        else { return }
        readingsByVolume.withLock { store in
            store = restored.mapValues {
                Self.pruned($0.sorted { $0.timestamp < $1.timestamp },
                            retention: retention, now: now)
            }
        }
    }
}

/// What a series of capacity readings shows, stated so it can be put into words.
///
/// A direction is only ever claimed from readings that exist. Too little history
/// is its own case rather than a flat line or an extrapolation (FR-002, FR-038).
public enum StorageTrend: Sendable, Equatable {
    /// Not enough measured history to state a direction, with what there is.
    case insufficientHistory(covered: Duration, readings: Int)
    /// Measured across the window, with no material movement either way.
    case steady(over: Duration)
    /// Available space fell by `bytes` over `over`, measured from its highest
    /// point in the retained window. `stillFalling` is true only when the most
    /// recent readings continue downward — it is never inferred from the overall
    /// direction.
    case declining(bytes: UInt64, over: Duration, stillFalling: Bool)
    case rising(bytes: UInt64, over: Duration)

    /// The finding in words, which is the primary way this is conveyed. The curve
    /// reinforces it; it never has to carry it alone (FR-034).
    public var statement: String {
        switch self {
        case .insufficientHistory(let covered, let readings):
            if readings == 0 {
                return "No capacity history yet. A trend needs readings over at least "
                    + StorageTrendAnalysis.describe(StorageTrendAnalysis.minimumSpan) + "."
            }
            // Agreed in number. On a freshly launched app this is the very first
            // sentence the Storage screen shows, and it read "1 readings over 1
            // minute" (TASK-119) — conspicuous next to copy that is otherwise
            // careful. `describe(_:)` already agrees its own nouns.
            let counted = readings == 1 ? "1 reading" : "\(readings) readings"
            return "Not enough history for a trend — \(counted) over "
                + StorageTrendAnalysis.describe(covered) + "."
        case .steady(let over):
            return "Roughly unchanged over the last " + StorageTrendAnalysis.describe(over) + "."
        case .declining(let bytes, let over, _):
            return "Down \(StorageTrendAnalysis.describe(bytes: bytes)) in the last "
                + StorageTrendAnalysis.describe(over) + "."
        case .rising(let bytes, let over):
            return "Up \(StorageTrendAnalysis.describe(bytes: bytes)) in the last "
                + StorageTrendAnalysis.describe(over) + "."
        }
    }

    /// Whether the figures in `statement` are a calculation over measurements
    /// rather than a measurement, for the provenance label (FR-038).
    public var isCalculated: Bool {
        if case .insufficientHistory = self { return false }
        return true
    }

    public var declineSpan: Duration? {
        if case .declining(_, let over, _) = self { return over }
        return nil
    }

    public var isStillFalling: Bool {
        if case .declining(_, _, let stillFalling) = self { return stillFalling }
        return false
    }
}

/// Turns capacity readings into a stated finding (FR-041).
public enum StorageTrendAnalysis {
    /// The least history that supports any claim about direction. Below this the
    /// answer is "we do not know yet", not a smaller number.
    public static let minimumSpan: Duration = .seconds(12 * 3600)

    /// Movement smaller than this share of capacity is not called a direction.
    /// Volumes breathe by a gigabyte or two from caches alone.
    public static let materialFractionOfCapacity = 0.005
    public static let materialFloorBytes: UInt64 = 512 * 1_048_576

    /// The tail examined to decide whether a decline is still going, as a share of
    /// the decline's own span. Bounded below so a short decline is not judged on
    /// two adjacent readings.
    static let tailFractionOfDecline = 0.25
    static let minimumTail: Duration = .seconds(3600)

    public static func trend(for readings: [StorageReading], now: Date = Date()) -> StorageTrend {
        let series = readings.sorted { $0.timestamp < $1.timestamp }
        guard let first = series.first, let last = series.last, series.count >= 2 else {
            // One reading covers no span at all, so there is nothing to overstate.
            return .insufficientHistory(covered: .zero, readings: series.count)
        }
        let covered = Duration.seconds(last.timestamp.timeIntervalSince(first.timestamp))
        guard covered.totalSeconds >= minimumSpan.totalSeconds else {
            return .insufficientHistory(covered: covered, readings: series.count)
        }

        let material = max(
            UInt64(Double(last.totalBytes) * materialFractionOfCapacity), materialFloorBytes)

        // Measured from the extreme, not from the window's edge: a slide that
        // began four days into a fortnight is a four-day slide, and dating it
        // from day zero would understate the rate.
        let peak = series.max { $0.availableBytes < $1.availableBytes } ?? last
        let trough = series.min { $0.availableBytes < $1.availableBytes } ?? last

        let fell = peak.timestamp < last.timestamp && peak.availableBytes > last.availableBytes
            ? peak.availableBytes - last.availableBytes : 0
        let rose = trough.timestamp < last.timestamp && last.availableBytes > trough.availableBytes
            ? last.availableBytes - trough.availableBytes : 0

        if fell >= material, fell >= rose {
            let over = Duration.seconds(last.timestamp.timeIntervalSince(peak.timestamp))
            return .declining(
                bytes: fell, over: over,
                stillFalling: isStillFalling(series, declineSpan: over, material: material))
        }
        if rose >= material {
            return .rising(
                bytes: rose,
                over: .seconds(last.timestamp.timeIntervalSince(trough.timestamp)))
        }
        return .steady(over: covered)
    }

    /// Whether the most recent stretch of readings is still going down.
    ///
    /// This is the distinction the screen exists for: a volume can be back above
    /// the warning line while the slide that took it there continues. Deliberately
    /// conservative — with no reading old enough to compare against, the answer is
    /// no, because "we cannot tell" must never be presented as "yes".
    static func isStillFalling(
        _ series: [StorageReading], declineSpan: Duration, material: UInt64
    ) -> Bool {
        guard let last = series.last else { return false }
        let tail = max(declineSpan.totalSeconds * tailFractionOfDecline, minimumTail.totalSeconds)
        let cutoff = last.timestamp.addingTimeInterval(-tail)
        guard let referenceIndex = series.lastIndex(where: { $0.timestamp <= cutoff })
        else { return false }
        // The tail must have readings of its own. Two readings a week apart show a
        // decline; they say nothing about whether it is still going.
        guard series.count - referenceIndex - 1 >= 2 else { return false }
        // A tenth of the material threshold: within the tail we are looking for
        // continued movement, not another whole slide.
        return series[referenceIndex].availableBytes > last.availableBytes + material / 10
    }

    /// How a volume stands against the low-storage warning line, in words.
    ///
    /// Recovered is not the same as fine: when a volume is back above the line but
    /// the decline has not stopped, that is what it says.
    public static func standingStatement(
        trend: StorageTrend,
        isBelowThreshold: Bool,
        hadLowStorageIncident: Bool
    ) -> String? {
        if isBelowThreshold {
            return "Below the low-storage warning line now."
        }
        guard case .declining(_, let over, let stillFalling) = trend else {
            return hadLowStorageIncident ? "Back above the low-storage warning line." : nil
        }
        let span = describe(over)
        if stillFalling {
            return hadLowStorageIncident
                ? "It is back above the line now, but the \(span) slide has not stopped."
                : "Above the line, but the \(span) slide has not stopped."
        }
        return hadLowStorageIncident
            ? "Back above the line, and the \(span) decline has not continued in the most recent readings."
            : nil
    }

    // MARK: - Wording

    public static func describe(_ duration: Duration) -> String {
        let seconds = duration.totalSeconds
        if seconds >= 2 * 86400 { return "\(Int((seconds / 86400).rounded())) days" }
        if seconds >= 86400 { return "1 day" }
        if seconds >= 7200 { return "\(Int((seconds / 3600).rounded())) hours" }
        if seconds >= 3600 { return "1 hour" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    static func describe(bytes: UInt64) -> String {
        ByteCountFormatStyle().format(Int64(bytes))
    }
}

extension LowStorageDetector {
    /// The available-space figure at which this volume would begin to breach —
    /// the line the trend chart draws.
    ///
    /// Both safeguards apply at once, so the effective line is the lower of them.
    /// Drawing the proportional line alone would show a 1 TB disk crossing at
    /// 100 GB when no incident would open until 5 GB, and a chart that disagrees
    /// with detection is worse than no chart.
    public func thresholdBytes(for volume: VolumeCapacity) -> UInt64 {
        min(UInt64(Double(volume.totalBytes) * fractionThreshold), absoluteThresholdBytes)
    }

    /// How the line is described, so its two-part definition is never hidden.
    public func thresholdExplanation(for volume: VolumeCapacity) -> String {
        let proportional = UInt64(Double(volume.totalBytes) * fractionThreshold)
        let percent = Int((fractionThreshold * 100).rounded())
        let line = ByteCountFormatStyle().format(Int64(thresholdBytes(for: volume)))
        return proportional <= absoluteThresholdBytes
            ? "Warning line \(line) — \(percent)% of capacity"
            : "Warning line \(line) — \(percent)% of capacity would be "
                + "\(ByteCountFormatStyle().format(Int64(proportional))), and the lower of the two applies"
    }
}
