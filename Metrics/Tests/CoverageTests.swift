import Foundation
import Testing

@testable import Metrics

/// The coverage record (TASK-113).
///
/// The property under test throughout is that **a gap is never healed and never
/// implied away**. Every assertion here is a way of getting that wrong: extending
/// an interval across a hole, filling a window with watched time we do not have,
/// rounding a short gap out of the total, or letting a restart quietly claim the
/// stretch it was absent for.
@Suite("Coverage record")
struct CoverageTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test("A reading within tolerance extends the interval rather than opening one")
    func continuousObservationIsOneInterval() {
        var log = CoverageLog()
        for second in stride(from: 0.0, through: 60.0, by: 2.0) {
            log.observe(at: at(second), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        }
        #expect(log.intervals.count == 1)
        #expect(log.intervals[0].began == at(0))
        #expect(log.intervals[0].lastObserved == at(60))
        #expect(log.watched(from: at(0), to: at(60)).totalSeconds == 60)
    }

    @Test("A lapse longer than the tolerance opens a new interval and records the reason")
    func lapseOpensAGap() {
        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(10), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        let opened = log.observe(at: at(600), tolerance: .seconds(20),
                                 resumingAfter: .systemAsleep)
        log.observe(at: at(610), tolerance: .seconds(20), resumingAfter: .systemAsleep)
        #expect(opened)
        #expect(log.intervals.count == 2)
        #expect(log.intervals[1].precededBy == .systemAsleep)

        let spans = log.spans(from: at(0), to: at(610))
        #expect(spans.count == 3)
        #expect(spans[0].state == .watched)
        #expect(spans[1].state == .notWatched(.systemAsleep))
        #expect(spans[2].state == .watched)
    }

    /// The claim the whole screen rests on: watched time is what we observed, never
    /// the length of the window.
    @Test("Watched time excludes the gap")
    func watchedExcludesGap() {
        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(100), tolerance: .seconds(200), resumingAfter: .appNotRunning)
        log.observe(at: at(1000), tolerance: .seconds(20), resumingAfter: .noReadings)
        log.observe(at: at(1100), tolerance: .seconds(200), resumingAfter: .noReadings)
        #expect(log.watched(from: at(0), to: at(1100)).totalSeconds == 200)
    }

    /// Every moment is accounted for. A strip that only drew the gaps it could
    /// explain would be honest about those and silent about the rest.
    @Test("Spans tile the window exactly")
    func spansTileTheWindow() {
        var log = CoverageLog()
        log.observe(at: at(300), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(400), tolerance: .seconds(200), resumingAfter: .appNotRunning)

        let spans = log.spans(from: at(0), to: at(1000))
        #expect(spans.first?.from == at(0))
        #expect(spans.last?.to == at(1000))
        for (earlier, later) in zip(spans, spans.dropFirst()) {
            #expect(earlier.to == later.from)
        }
        let covered = spans.reduce(0.0) { $0 + $1.duration.totalSeconds }
        #expect(covered == 1000)
    }

    /// The reason recorded when we resumed is the only account we have of the
    /// stretch before the first interval, so it is the account the strip gives.
    @Test("A window reaching before the record claims no watching, and says why")
    func leadingWindowIsNotWatched() {
        var log = CoverageLog()
        log.observe(at: at(500), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(510), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        let spans = log.spans(from: at(0), to: at(510))
        #expect(spans[0].state == .notWatched(.appNotRunning))
        #expect(log.watched(from: at(0), to: at(500)).totalSeconds == 0)
    }

    /// One sample says we were alive at an instant, not that we covered a stretch.
    /// The record under-claims here on purpose — the alternative is painting a width
    /// for a duration nothing measured.
    @Test("A single reading claims no stretch of coverage")
    func singleReadingClaimsNoStretch() {
        var log = CoverageLog()
        log.observe(at: at(500), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        #expect(log.watched(from: at(0), to: at(1000)).totalSeconds == 0)
        #expect(log.spans(from: at(0), to: at(1000)).allSatisfy { !$0.state.isWatched })
    }

    @Test("An empty record claims nothing at all")
    func emptyRecordClaimsNothing() {
        let log = CoverageLog()
        let spans = log.spans(from: at(0), to: at(1000))
        #expect(spans.count == 1)
        #expect(spans[0].state == .notWatched(.beyondRecord))
        #expect(log.isComplete(from: at(0), to: at(1000)) == false)
    }

    /// The minimum governs what is *listed*, never what is counted — otherwise the
    /// listed gaps and the watched total would disagree in front of the user.
    @Test("A short lapse is below the listing threshold but still costs watched time")
    func shortGapIsCountedButNotListed() {
        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(5), resumingAfter: .appNotRunning)
        log.observe(at: at(30), tolerance: .seconds(5), resumingAfter: .noReadings)
        #expect(log.gaps(from: at(0), to: at(30), minimum: .seconds(60)).isEmpty)
        #expect(log.watched(from: at(0), to: at(30)).totalSeconds == 0)
    }

    @Test("Pruning truncates the straddling interval rather than dropping it")
    func pruningTruncates() {
        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(1000), tolerance: .seconds(2000), resumingAfter: .appNotRunning)
        let pruned = log.prune(before: at(500))
        #expect(pruned)
        #expect(log.intervals.count == 1)
        #expect(log.intervals[0].began == at(500))
        // Stamped so the leading gap on a long view reads as the limit of what we
        // keep, not as a stretch we failed to watch (design 5c).
        #expect(log.intervals[0].precededBy == .beyondRecord)
        #expect(log.watched(from: at(0), to: at(1000)).totalSeconds == 500)
    }

    @Test("A clock that goes backwards cannot shorten the record")
    func backwardsClockIsIgnored() {
        var log = CoverageLog()
        log.observe(at: at(100), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(110), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(50), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        #expect(log.intervals.count == 1)
        #expect(log.intervals[0].lastObserved == at(110))
    }

    @Test("Forgetting the record leaves only the fact that we are watching now")
    func forgettingRestartsTheRecord() {
        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(500), tolerance: .seconds(1000), resumingAfter: .appNotRunning)
        log.forgetting(at: at(500))
        #expect(log.intervals.count == 1)
        #expect(log.watched(from: at(0), to: at(500)).totalSeconds == 0)
        #expect(log.spans(from: at(0), to: at(500))[0].state == .notWatched(.beyondRecord))
    }

    @Test("The tolerance moves with the cadence rather than being a fixed number")
    func toleranceScalesWithCadence() {
        #expect(CoverageLog.tolerance(cadence: .seconds(1)).totalSeconds == 20)
        #expect(CoverageLog.tolerance(cadence: .seconds(10)).totalSeconds == 40)
    }

    @Test("The record round-trips through disk without moving")
    func roundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: at(37.5), tolerance: .seconds(100), resumingAfter: .appNotRunning)

        let store = CoverageStore(url: url, minimumWriteInterval: .seconds(0))
        #expect(store.flush(log, settings: .default, force: true) != nil)
        // Sub-second precision survives, for the reason recorded on
        // `IncidentHistoryStore`: an ISO-8601 stamp truncates and would report a
        // hairline gap at every restart.
        #expect(store.load() == log)
    }

    @Test("Writes are throttled, and a forced write is not")
    func writesAreThrottled() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        let store = CoverageStore(url: url, minimumWriteInterval: .seconds(60))
        #expect(store.flush(log, settings: .default, now: at(0)) != nil)
        #expect(store.flush(log, settings: .default, now: at(10)) == nil)
        #expect(store.flush(log, settings: .default, now: at(10), force: true) != nil)
        #expect(store.flush(log, settings: .default, now: at(90)) != nil)
    }

    @Test("Nothing is written when the user has asked us not to persist")
    func persistenceRespectsTheSetting() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var log = CoverageLog()
        log.observe(at: at(0), tolerance: .seconds(20), resumingAfter: .appNotRunning)
        let store = CoverageStore(url: url, minimumWriteInterval: .seconds(0))
        var settings = PrivacySettings.default
        settings.persistAcrossRestarts = false
        #expect(store.flush(log, settings: settings, force: true) == nil)
        #expect(store.load() == nil)
    }
}
