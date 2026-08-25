import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// A run of retained samples, `cadence` seconds apart, ending at `end`.
private func samples(
    count: Int, cadence: Double = 2, end: Date = Date(timeIntervalSince1970: 10_000),
    total: (Int) -> Double = { _ in 120 },
    unattributed: (Int) -> Double = { _ in 30 }
) -> [HistorySample] {
    (0..<count).map { index in
        let offset = Double(count - 1 - index) * cadence
        return HistorySample(
            timestamp: end.addingTimeInterval(-offset),
            totalBusyPercentOfOneCore: total(index),
            attributedPercentOfOneCore: total(index) - unattributed(index),
            unattributedPercentOfOneCore: unattributed(index),
            topContributors: [])
    }
}

private func points(_ values: [Double], cadence: Double = 2,
                    start: Date = Date(timeIntervalSince1970: 0)) -> [SparklinePoint] {
    values.enumerated().map {
        SparklinePoint(at: start.addingTimeInterval(Double($0.offset) * cadence),
                       value: $0.element)
    }
}

@Suite("A sparkline plots only what was retained")
struct SparklineSeriesTests {
    /// The whole point of TASK-66's accessor: the view draws the series FR-005
    /// keeps, so the popover and the incident report cannot disagree about the
    /// same minutes.
    @Test("The aggregate series is one point per retained sample, in order")
    func aggregateSeriesMirrorsHistory() {
        let history = samples(count: 6, total: { 100 + Double($0) * 10 })
        let series = SparklinePresentation.totalBusySeries(history)

        #expect(series.count == history.count)
        #expect(series.map(\.value) == [100, 110, 120, 130, 140, 150])
        #expect(series.map(\.at) == history.map(\.timestamp))
    }

    /// The "System processes" row's figure *is* `unattributedPercentOfOneCore`
    /// (see `InventoryRow`), and every retained sample carries it — so that one row
    /// has a series with the same coverage as the machine total.
    @Test("The unattributed series is the System processes row's own figure")
    func unattributedSeries() {
        let history = samples(count: 4, unattributed: { 20 + Double($0) })
        #expect(SparklinePresentation.unattributedSeries(history).map(\.value)
                == [20, 21, 22, 23])
    }

    /// Reversed on 2026-08-25 (TASK-95). `FamilyHistory` records each family's sum
    /// on every sampling pass, so a family's curve now has the same coverage as the
    /// machine total's. The limitation moved down a level rather than disappearing:
    /// a *process* still has no series, because history is keyed on the family.
    @Test("Per-family history is retained; per-process history is not")
    func perFamilyHistoryIsRetained() {
        #expect(SparklinePresentation.perFamilyHistoryIsRetained)
        #expect(SparklinePresentation.perProcessHistoryExplanation
            .contains("not for each of its processes"))
        // The reason must be about our records, never about the process.
        #expect(!SparklinePresentation.perProcessHistoryExplanation.contains("idle"))
    }

    /// Two samples is the number of samples we have, not a flat quarter-hour.
    @Test("An empty history yields an empty series, never a padded one")
    func emptyHistory() {
        #expect(SparklinePresentation.totalBusySeries([]).isEmpty)
        #expect(SparklinePresentation.unattributedSeries([]).isEmpty)
    }
}

@Suite("Too few points is a sentence, not a flat line")
struct SparklineReadinessTests {
    @Test("Below the minimum, the answer is words that say we have not watched long enough")
    func tooFew() {
        guard case .tooFew(let sentence) = SparklinePresentation.readiness(points([80, 90]))
        else { return #expect(Bool(false), "two readings should not be drawable") }

        #expect(sentence.contains("2 readings"))
        #expect(sentence.contains("at least \(SparklinePresentation.minimumPoints)"))
        // The failure mode this exists to prevent: a flat line reading as calm.
        #expect(sentence.contains("how long we have been watching"))
        #expect(!sentence.lowercased().contains("nothing happened"))
    }

    @Test("One reading is singular, and still not a trend")
    func singleReading() {
        guard case .tooFew(let sentence) = SparklinePresentation.readiness(points([80]))
        else { return #expect(Bool(false), "one reading should not be drawable") }
        #expect(sentence.contains("1 reading retained"))
    }

    @Test("No readings at all is still stated, never drawn")
    func noReadings() {
        #expect(SparklinePresentation.readiness([]) != .ready)
    }

    @Test("At the minimum it becomes drawable")
    func atMinimum() {
        let just = points(Array(repeating: 50, count: SparklinePresentation.minimumPoints))
        #expect(SparklinePresentation.readiness(just) == .ready)
    }
}

@Suite("The caption states the span we actually have")
struct SparklineSpanTests {
    /// Never pad the window. Four minutes of samples labelled "last 15 min" would
    /// make the missing eleven read as measured calm.
    @Test("A short span says so, and names the window it falls short of")
    func shortSpanIsDeclared() {
        // 90 samples at 2 s = 178 s ≈ 3 min, against a 15 min window.
        let caption = SparklinePresentation.spanCaption(
            points(Array(repeating: 100, count: 90)), window: .seconds(15 * 60))

        #expect(caption.contains("3 min"))
        #expect(caption.contains("all we have retained"))
        #expect(caption.contains("15 min window"))
    }

    @Test("A full window is stated plainly")
    func fullSpan() {
        let full = points(Array(repeating: 100, count: 451))  // 900 s at 2 s
        #expect(SparklinePresentation.spanCaption(full, window: .seconds(15 * 60))
                == "Last 15 min")
    }

    @Test("Under a minute is counted in seconds rather than rounded away")
    func secondsSpan() {
        let caption = SparklinePresentation.spanCaption(
            points(Array(repeating: 100, count: 21)), window: .seconds(15 * 60))
        #expect(caption.contains("40 s"))
    }

    @Test("The span is measured between the first and last reading, not assumed")
    func spanIsMeasured() {
        #expect(SparklinePresentation.span(points([1, 2, 3, 4], cadence: 5)).totalSeconds == 15)
        #expect(SparklinePresentation.span(points([1])).totalSeconds == 0)
        #expect(SparklinePresentation.span([]).totalSeconds == 0)
    }
}

@Suite("Gaps are broken, never bridged")
struct SparklineGapTests {
    /// A straight line across minutes nobody observed is an invented measurement.
    @Test("A hole in the record splits the series into separate runs")
    func gapSplitsRuns() {
        let start = Date(timeIntervalSince1970: 0)
        let before = points([100, 110, 120], start: start)
        let after = points([90, 95], start: start.addingTimeInterval(600))
        let runs = SparklinePresentation.runs(
            before + after, gapThreshold: SparklinePresentation.gapThreshold(cadence: .seconds(2)))

        #expect(runs.count == 2)
        #expect(runs[0].map(\.value) == [100, 110, 120])
        #expect(runs[1].map(\.value) == [90, 95])
    }

    /// A sampling loop on a busy machine runs late; breaking the stroke for ordinary
    /// jitter would invent gaps as readily as bridging them invents readings.
    @Test("Ordinary lateness is not a gap")
    func jitterIsNotAGap() {
        let start = Date(timeIntervalSince1970: 0)
        let series = [
            SparklinePoint(at: start, value: 100),
            SparklinePoint(at: start.addingTimeInterval(2), value: 110),
            SparklinePoint(at: start.addingTimeInterval(7), value: 120),
        ]
        let runs = SparklinePresentation.runs(
            series, gapThreshold: SparklinePresentation.gapThreshold(cadence: .seconds(2)))
        #expect(runs.count == 1)
    }

    @Test("The threshold has a floor, so a fast investigation cadence is not absurdly tight")
    func thresholdFloor() {
        #expect(SparklinePresentation.gapThreshold(cadence: .seconds(1)).totalSeconds == 8)
        #expect(SparklinePresentation.gapThreshold(cadence: .seconds(5)).totalSeconds == 20)
    }

    @Test("An empty series has no runs")
    func emptyRuns() {
        #expect(SparklinePresentation.runs([], gapThreshold: .seconds(8)).isEmpty)
    }
}

@Suite("The incident mark comes from the incident")
struct SparklineMarkerTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test("A start inside the retained span lands where it happened")
    func markerInsideSpan() {
        let series = points(Array(repeating: 100, count: 11))  // 0…20 s
        let fraction = SparklinePresentation.markerFraction(
            for: start.addingTimeInterval(5), in: series)
        #expect(fraction == 0.25)
    }

    /// Clamping to the edge would claim the incident began exactly when our history
    /// happens to start — a coincidence, presented as a measurement.
    @Test("A start earlier than anything we retained is not clamped to the edge")
    func markerBeforeSpan() {
        let series = points(Array(repeating: 100, count: 11))
        #expect(SparklinePresentation.markerFraction(
            for: start.addingTimeInterval(-60), in: series) == nil)
    }

    @Test("An out-of-span start is explained in words instead")
    func markerCaptionOutsideSpan() {
        let series = points(Array(repeating: 100, count: 11))
        let caption = SparklinePresentation.markerCaption(
            beganAt: start.addingTimeInterval(-3600), points: series)
        #expect(caption.contains("before the history we still hold"))
    }

    @Test("An in-span start is captioned as started-then, now-here")
    func markerCaptionInsideSpan() {
        let series = points(Array(repeating: 100, count: 11))
        let caption = SparklinePresentation.markerCaption(
            beganAt: start.addingTimeInterval(10), points: series)
        #expect(caption.contains("started"))
        #expect(caption.hasSuffix("now"))
        #expect(!caption.contains("before the history"))
    }

    @Test("With no retained points there is nothing to mark")
    func markerWithoutPoints() {
        #expect(SparklinePresentation.markerFraction(for: start, in: []) == nil)
        #expect(SparklinePresentation.markerCaption(beganAt: start, points: []).isEmpty)
    }
}

@Suite("A chart VoiceOver cannot read is not accessible")
struct SparklineAccessibilityTests {
    /// FR-034. Every figure spoken has to be one that was plotted.
    @Test("The summary states the span, the range and the latest reading")
    func summary() {
        let series = points([50, 200, 90, 300, 120, 80])
        let text = SparklinePresentation.accessibilitySummary(
            title: "Total CPU", points: series, window: .seconds(15 * 60),
            gapThreshold: .seconds(8))

        #expect(text.contains("Total CPU"))
        #expect(text.contains("6 readings"))
        #expect(text.contains("lowest 50%"))
        #expect(text.contains("highest 300%"))
        #expect(text.contains("most recent 80%"))
        #expect(text.contains("all we have retained"))
    }

    @Test("A break in the record is spoken, not left to the picture")
    func summaryStatesGap() {
        let early = points(Array(repeating: 100.0, count: 5))
        let late = points(Array(repeating: 100.0, count: 5),
                          start: Date(timeIntervalSince1970: 600))
        let text = SparklinePresentation.accessibilitySummary(
            title: "Total CPU", points: early + late, window: .seconds(15 * 60),
            gapThreshold: .seconds(8))
        #expect(text.contains("break where no readings were taken"))
    }

    @Test("Too little history is spoken as too little history")
    func summaryWhenTooFew() {
        let text = SparklinePresentation.accessibilitySummary(
            title: "Total CPU", points: points([90, 95]), window: .seconds(15 * 60),
            gapThreshold: .seconds(8))
        #expect(text.contains("Total CPU"))
        #expect(text.contains("2 readings retained so far"))
    }
}

@Suite("Now states what it does not retain")
struct NowHistoryCopyTests {
    /// Design 1c charts disk throughput. `MetricsHistory` keeps CPU and nothing
    /// else, so the absence is stated rather than filled in from a series that
    /// would exist only while the screen was open.
    @Test("The disk card says there is no retained trend, and why")
    func diskNote() {
        #expect(NowPresentation.diskHistoryNote.contains("No history is retained"))
        #expect(NowPresentation.diskHistoryNote.contains("last interval"))
    }

    @Test("A footnote explains what the history column can and cannot cover")
    func historyFootnote() {
        let notes = NowPresentation.footnotes()
        #expect(notes.contains(NowPresentation.historyColumnNote))
        #expect(NowPresentation.historyColumnNote.contains("not retained"))
        #expect(NowPresentation.historyColumnNote.contains("machine total"))
    }
}
