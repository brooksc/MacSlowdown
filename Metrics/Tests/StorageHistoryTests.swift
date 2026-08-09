import Foundation
import Testing

@testable import Metrics

private func volume(
    id: String = "/", total: UInt64 = 1_000_000_000_000, available: UInt64,
    purgeable: UInt64? = nil
) -> VolumeCapacity {
    VolumeCapacity(url: URL(fileURLWithPath: id), name: "Test",
                   isStartupVolume: id == "/", isRemovable: false, isNetwork: false,
                   totalBytes: total, availableBytes: available,
                   purgeableEstimateBytes: purgeable)
}

private let terabyte: UInt64 = 1_000_000_000_000
private let gigabyte = 1_000_000_000.0

/// Hourly readings over `days` ending at `end`, shaped by `availableGB(hoursAgo)`.
/// Hourly rather than at the real quarter-hour cadence so the arrays stay small;
/// nothing in the analysis depends on the cadence.
private func hourly(
    days: Double, endingAt end: Date, total: UInt64 = terabyte,
    availableGB: (Double) -> Double
) -> [StorageReading] {
    let hours = Int(days * 24)
    return (0...hours).map { step in
        let hoursAgo = Double(hours - step)
        return StorageReading(
            volumeID: "/", timestamp: end.addingTimeInterval(-hoursAgo * 3600),
            availableBytes: UInt64(availableGB(hoursAgo) * gigabyte), totalBytes: total)
    }
}

/// A straight line from `from` GB at `overDays` ago to `to` GB now.
private func slope(from: Double, to: Double, overDays: Double, endingAt end: Date)
    -> [StorageReading] {
    hourly(days: overDays, endingAt: end) { hoursAgo in
        let progress = 1 - (hoursAgo / (overDays * 24))
        return from + (to - from) * progress
    }
}

@Suite("Storage history")
struct StorageHistoryTests {
    @Test("Readings closer together than the minimum interval are not retained")
    func coalescesToMinimumInterval() {
        let history = StorageHistory(minimumInterval: .seconds(900))
        let start = Date()
        let snapshot = StorageSnapshot(volumes: [volume(available: 100_000_000_000)],
                                       unreadable: [])

        #expect(history.record(snapshot, at: start).count == 1)
        #expect(history.record(snapshot, at: start.addingTimeInterval(60)).isEmpty)
        #expect(history.record(snapshot, at: start.addingTimeInterval(901)).count == 1)
        #expect(history.readings(forVolume: "/").count == 2)
    }

    @Test("Readings older than the retention window are dropped")
    func prunesPastRetention() {
        let history = StorageHistory(retention: .seconds(86400), minimumInterval: .seconds(1))
        let now = Date()
        let snapshot = StorageSnapshot(volumes: [volume(available: 100_000_000_000)],
                                       unreadable: [])

        history.record(snapshot, at: now.addingTimeInterval(-90000))
        history.record(snapshot, at: now)
        #expect(history.readings(forVolume: "/").count == 1)
    }

    /// The covered span is what was recorded, never the retention window. A screen
    /// that said "last 14 days" over four hours of readings would be claiming
    /// history it does not have (FR-002).
    @Test("Covered duration reports the span actually recorded")
    func coveredDurationIsMeasured() {
        let history = StorageHistory(minimumInterval: .seconds(1))
        let now = Date()
        let snapshot = StorageSnapshot(volumes: [volume(available: 100_000_000_000)],
                                       unreadable: [])
        history.record(snapshot, at: now.addingTimeInterval(-7200))
        history.record(snapshot, at: now)

        #expect(abs(history.coveredDuration(forVolume: "/").totalSeconds - 7200) < 1)
        #expect(history.coveredDuration(forVolume: "/nowhere").totalSeconds == 0)
    }

    @Test("A persisted series survives a restart")
    func persistsAcrossRestarts() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "storage-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let now = Date()
        let first = StorageHistory(minimumInterval: .seconds(1), fileURL: url)
        first.record(StorageSnapshot(volumes: [volume(available: 100_000_000_000)],
                                     unreadable: []), at: now)

        let second = StorageHistory(minimumInterval: .seconds(1), fileURL: url)
        second.restore(now: now)
        #expect(second.readings(forVolume: "/").count == 1)
        #expect(second.readings(forVolume: "/").first?.availableBytes == 100_000_000_000)
    }

    @Test("A missing history file leaves the series empty rather than failing")
    func missingFileIsNotAnError() {
        let history = StorageHistory(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "absent-\(UUID().uuidString).json"))
        history.restore()
        #expect(history.readings(forVolume: "/").isEmpty)
    }

    @Test("Unreadable volumes contribute no readings")
    func unreadableVolumesAreNotRecorded() {
        let history = StorageHistory(minimumInterval: .seconds(1))
        let snapshot = StorageSnapshot(
            volumes: [],
            unreadable: [UnreadableVolume(url: URL(fileURLWithPath: "/Volumes/share"),
                                          name: "share", isNetwork: true)])
        #expect(history.record(snapshot).isEmpty)
        #expect(history.readings(forVolume: "/Volumes/share").isEmpty)
    }
}

@Suite("Storage trend")
struct StorageTrendTests {
    private let now = Date()

    /// FR-002: too little history is its own answer, not a flat line.
    @Test("No readings state that there is no history, not that nothing changed")
    func noHistoryIsStated() {
        let trend = StorageTrendAnalysis.trend(for: [], now: now)
        #expect(trend == .insufficientHistory(covered: .zero, readings: 0))
        #expect(trend.statement.lowercased().contains("no capacity history"))
        #expect(!trend.isCalculated)
    }

    @Test("A span shorter than the minimum states the period we have")
    func shortSpanIsStated() {
        let readings = slope(from: 100, to: 99.75, overDays: 0.25, endingAt: now)
        let trend = StorageTrendAnalysis.trend(for: readings, now: now)
        guard case .insufficientHistory(let covered, let count) = trend else {
            Issue.record("expected insufficient history, got \(trend)")
            return
        }
        #expect(covered.totalSeconds < StorageTrendAnalysis.minimumSpan.totalSeconds)
        #expect(count == readings.count)
        #expect(trend.statement.contains("Not enough history"))
    }

    /// The headline the screen exists to state, in words rather than as a curve.
    @Test("A sustained decline is stated in words, dated from its start")
    func declineIsStatedInWords() {
        let readings = slope(from: 158, to: 96, overDays: 6, endingAt: now)
        let trend = StorageTrendAnalysis.trend(for: readings, now: now)

        guard case .declining(let bytes, let over, let stillFalling) = trend else {
            Issue.record("expected a decline, got \(trend)")
            return
        }
        #expect(bytes > 60_000_000_000)
        #expect(bytes < 64_000_000_000)
        // Dated from the peak, which is where the slide began — not from the
        // edge of the retained window.
        #expect(abs(over.totalSeconds - 6 * 86400) < 3600)
        #expect(stillFalling)
        #expect(trend.statement.hasPrefix("Down "))
        #expect(trend.statement.contains("6 days"))
        #expect(trend.isCalculated)
    }

    @Test("A rise is stated as a rise")
    func riseIsStated() {
        let readings = slope(from: 40, to: 80, overDays: 4, endingAt: now)
        let trend = StorageTrendAnalysis.trend(for: readings, now: now)
        guard case .rising(let bytes, let over) = trend else {
            Issue.record("expected a rise, got \(trend)")
            return
        }
        #expect(bytes > 39_000_000_000)
        #expect(abs(over.totalSeconds - 4 * 86400) < 3600)
        #expect(trend.statement.hasPrefix("Up "))
    }

    /// A volume breathes by a gigabyte or two from caches alone. That is not a
    /// direction, and calling it one would be a fabricated finding.
    @Test("Movement below the material threshold is not called a direction")
    func noiseIsNotATrend() {
        // 200 MB of drift over two days, against a 5 GB material threshold.
        let readings = slope(from: 100, to: 99.8, overDays: 2, endingAt: now)
        let trend = StorageTrendAnalysis.trend(for: readings, now: now)
        guard case .steady = trend else {
            Issue.record("expected steady, got \(trend)")
            return
        }
        #expect(trend.statement.contains("Roughly unchanged"))
    }

    /// The distinction the screen exists for. Recovered is not the same as fine.
    @Test("A decline that recovered but continues is still reported as falling")
    func recoveredButStillFalling() throws {
        // Falls from 158 to 96 over four days, is rescued to 130 over one day,
        // then slides again to 100. Above the line at the end, still going down.
        let readings = hourly(days: 8, endingAt: now) { hoursAgo in
            switch hoursAgo {
            case 96...: 158 - 62 * ((192 - hoursAgo) / 96)
            case 72..<96: 96 + 34 * ((96 - hoursAgo) / 24)
            default: 130 - 30 * ((72 - hoursAgo) / 72)
            }
        }

        let trend = StorageTrendAnalysis.trend(for: readings, now: now)
        #expect(trend.isStillFalling, "the most recent readings are still going down")

        let text = try #require(StorageTrendAnalysis.standingStatement(
            trend: trend, isBelowThreshold: false, hadLowStorageIncident: true))
        #expect(text.contains("back above the line"))
        #expect(text.contains("has not stopped"))
    }

    @Test("A decline that has genuinely stopped is not described as continuing")
    func recoveredAndStopped() throws {
        let readings = hourly(days: 8, endingAt: now) { hoursAgo in
            hoursAgo >= 48 ? 158 - 60 * ((192 - hoursAgo) / 144) : 98
        }

        let trend = StorageTrendAnalysis.trend(for: readings, now: now)
        #expect(!trend.isStillFalling)

        let text = try #require(StorageTrendAnalysis.standingStatement(
            trend: trend, isBelowThreshold: false, hadLowStorageIncident: true))
        #expect(!text.contains("has not stopped"))
        #expect(text.contains("not continued"))
    }

    /// "We cannot tell" must never be presented as "yes".
    @Test("Too little recent history never claims a decline is continuing")
    func cannotTellIsNotYes() {
        let readings = [
            StorageReading(volumeID: "/", timestamp: now.addingTimeInterval(-6 * 86400),
                           availableBytes: 158_000_000_000, totalBytes: 1_000_000_000_000),
            StorageReading(volumeID: "/", timestamp: now,
                           availableBytes: 96_000_000_000, totalBytes: 1_000_000_000_000),
        ]
        let trend = StorageTrendAnalysis.trend(for: readings, now: now)
        guard case .declining(_, _, let stillFalling) = trend else {
            Issue.record("expected a decline, got \(trend)")
            return
        }
        #expect(!stillFalling, "no readings inside the tail, so no claim about it")
    }

    @Test("Being below the line now is said plainly")
    func belowTheLineIsStated() throws {
        let text = try #require(StorageTrendAnalysis.standingStatement(
            trend: .steady(over: .seconds(86400)),
            isBelowThreshold: true, hadLowStorageIncident: false))
        #expect(text.contains("Below the low-storage warning line"))
    }
}

@Suite("Low-storage warning line")
struct LowStorageThresholdTests {
    /// FR-042 applies both safeguards at once, so the line the chart draws is the
    /// lower of them. Drawing the proportional line alone would show a 1 TB disk
    /// crossing at 100 GB when no incident opens until 5 GB.
    @Test("The drawn line is the lower of the proportional and absolute safeguards")
    func lineMatchesDetection() {
        let detector = LowStorageDetector()
        let big = volume(total: 1_000_000_000_000, available: 96_000_000_000)
        #expect(detector.thresholdBytes(for: big) == detector.absoluteThresholdBytes)

        let small = volume(total: 32_000_000_000, available: 4_000_000_000)
        #expect(detector.thresholdBytes(for: small) == 3_200_000_000)
    }

    @Test("A volume at the drawn line is exactly at the detection boundary")
    func lineAndDetectionAgree() {
        let detector = LowStorageDetector()
        for total in [UInt64(32_000_000_000), 128_000_000_000, 1_000_000_000_000] {
            let line = detector.thresholdBytes(for: volume(total: total, available: total))
            #expect(!detector.isBelowThreshold(volume(total: total, available: line)))
            #expect(detector.isBelowThreshold(volume(total: total, available: line - 1)))
        }
    }

    @Test("The line's two-part definition is never hidden")
    func explanationStatesBothSafeguards() {
        let detector = LowStorageDetector()
        let big = detector.thresholdExplanation(for: volume(total: 1_000_000_000_000,
                                                            available: 96_000_000_000))
        #expect(big.contains("10%"))
        #expect(big.contains("lower of the two"))

        let small = detector.thresholdExplanation(for: volume(total: 32_000_000_000,
                                                              available: 4_000_000_000))
        #expect(small.contains("10% of capacity"))
    }
}
