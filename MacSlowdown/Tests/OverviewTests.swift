import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// The opening view's rules (TASK-113, designs 5a/5b/5c).
///
/// Most of these are assertions about what the screen may **not** say. The screen
/// is the product's standing claim about a period of time, and every way of
/// getting it wrong is a sentence that sounds reasonable: "everything is fine",
/// "no incidents", a headline dated from the start of a day we watched six minutes
/// of.
@MainActor
@Suite("Overview")
struct OverviewTests {
    /// A fixed calendar in GMT, so "midnight" is a value these assertions can
    /// compute rather than whatever the machine running them happens to think.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Noon on a real day in that calendar. Twelve hours after midnight, exactly,
    /// which is what makes the coverage arithmetic below checkable by hand.
    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 12)) ?? .now
    }

    /// A log that watched continuously from `from` until `to`.
    private func watching(from: Date, to: Date) -> CoverageLog {
        var log = CoverageLog()
        log.observe(at: from, tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: to, tolerance: .seconds(86_400 * 40), resumingAfter: .appNotRunning)
        return log
    }

    private func incident(
        began: Date, lasting seconds: Double, conditions: Set<IncidentCondition>,
        severity: IncidentSeverity = .moderate, open: Bool = true
    ) -> Incident {
        Incident(
            id: UUID(), beganAt: began, triggeredAt: began,
            recoveryStartedAt: nil,
            closedAt: open ? nil : began.addingTimeInterval(seconds),
            conditions: conditions, severity: severity,
            peakCPUBusyFraction: 0.94, peakMemoryPressure: .normal)
    }

    private func inputs(_ log: CoverageLog, now: Date) -> OverviewPresentation.Inputs {
        var inputs = OverviewPresentation.Inputs(log: log)
        inputs.now = now
        inputs.calendar = calendar
        return inputs
    }

    // MARK: - The three leads

    @Test("A complete window with nothing recorded leads with what was measured")
    func quietWindowLeadsQuietly() {
        let start = calendar.startOfDay(for: noon)
        let log = watching(from: start, to: noon)
        let headline = OverviewPresentation.headline(inputs(log, now: noon))

        #expect(OverviewPresentation.lead(inputs(log, now: noon)) == .nothingCrossed)
        #expect(headline.text.hasPrefix("Nothing has crossed a line since"))
        // FR-063: never a claim about the machine being fine, only about what we
        // measured and over what window.
        #expect(!headline.detail.localizedCaseInsensitiveContains("everything is fine"))
        #expect(headline.detail.contains("isn't a claim that the Mac was fine"))
    }

    @Test("A gap leads the screen, and refuses to answer for it")
    func gapLeadsTheScreen() {
        let start = calendar.startOfDay(for: noon)
        var log = CoverageLog()
        log.observe(at: start, tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: start.addingTimeInterval(3600), tolerance: .seconds(7200),
                    resumingAfter: .appNotRunning)
        // Two hours we were not running, then back to watching.
        log.observe(at: start.addingTimeInterval(3600 * 3), tolerance: .seconds(20),
                    resumingAfter: .appNotRunning)
        log.observe(at: noon, tolerance: .seconds(86_400), resumingAfter: .appNotRunning)

        let headline = OverviewPresentation.headline(inputs(log, now: noon))
        #expect(OverviewPresentation.lead(inputs(log, now: noon)) == .coverageGap)
        #expect(headline.text.hasPrefix("We can't answer for"))
        #expect(headline.detail.contains("MacSlowdown wasn't running"))
        #expect(headline.detail.contains("no record of it"))
    }

    @Test("An open condition leads, and hands the judgement back to the user")
    func openConditionLeads() {
        let start = calendar.startOfDay(for: noon)
        var inputs = inputs(watching(from: start, to: noon), now: noon)
        inputs.openIncident = incident(
            began: noon.addingTimeInterval(-540), lasting: 540, conditions: [.cpuSaturation])
        inputs.openHeadline = "CPU near capacity for 9 minutes"
        inputs.wasNotAnnounced = true

        let headline = OverviewPresentation.headline(inputs)
        #expect(OverviewPresentation.lead(inputs) == .conditionPresent)
        #expect(headline.text == "CPU near capacity for 9 minutes")
        // The sentence FR-063 exists for. A build and a slowdown are the same
        // measurement, and this screen says so rather than choosing for the reader.
        #expect(headline.detail.contains("depends on what you're doing"))
        #expect(headline.detail.contains("We didn't interrupt you for it"))
    }

    /// We may only claim not to have interrupted somebody when we did not.
    @Test("The no-interruption sentence is withheld when the condition announces")
    func announcedConditionDoesNotClaimSilence() {
        let start = calendar.startOfDay(for: noon)
        var inputs = inputs(watching(from: start, to: noon), now: noon)
        inputs.openIncident = incident(
            began: noon.addingTimeInterval(-300), lasting: 300,
            conditions: [.memoryPressure], severity: .high)
        inputs.openHeadline = "Memory pressure above warning for 5 minutes"
        inputs.wasNotAnnounced = false

        #expect(!OverviewPresentation.headline(inputs).detail.contains("didn't interrupt"))
    }

    // MARK: - Coverage in words

    @Test("The coverage line states both figures, never one")
    func coverageLineStatesBothFigures() {
        let start = calendar.startOfDay(for: noon)
        var log = CoverageLog()
        log.observe(at: start.addingTimeInterval(3600 * 6), tolerance: .seconds(20),
                    resumingAfter: .appNotRunning)
        log.observe(at: noon, tolerance: .seconds(86_400), resumingAfter: .appNotRunning)

        let line = OverviewPresentation.coverageSummary(
            log: log, scale: .today, now: noon, calendar: calendar)
        #expect(line.contains("6 hr"))
        #expect(line.contains("12 hr"))
        #expect(line.contains("since midnight"))
    }

    @Test("A fully covered window says so without arithmetic")
    func completeCoverageIsStatedPlainly() {
        let start = calendar.startOfDay(for: noon)
        let line = OverviewPresentation.coverageSummary(
            log: watching(from: start, to: noon), scale: .today, now: noon, calendar: calendar)
        #expect(line == "Watched all of it")
        #expect(OverviewPresentation.gapNote(
            log: watching(from: start, to: noon), scale: .today, now: noon,
            calendar: calendar) == nil)
    }

    /// A quiet headline may not be dated earlier than our record of the window.
    /// Dating it from midnight after six minutes of watching would be the exact
    /// claim S-6 says is worth nothing.
    @Test("The quiet headline is dated from the record, not from the window")
    func quietHeadlineIsDatedFromTheRecord() {
        let start = calendar.startOfDay(for: noon)
        var log = CoverageLog()
        let watchedFrom = noon.addingTimeInterval(-360)
        log.observe(at: watchedFrom, tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: noon, tolerance: .seconds(600), resumingAfter: .appNotRunning)

        // A gap of six hours leads instead, which is right — but the *quiet*
        // sentence, when it is reached, must still date itself from the record.
        var withoutGap = inputs(log, now: noon)
        withoutGap.scale = .today
        #expect(OverviewPresentation.lead(withoutGap) == .coverageGap)
        #expect(start < watchedFrom)

        let headline = OverviewPresentation.headline(
            inputs(watching(from: watchedFrom, to: noon), now: noon))
        #expect(headline.text.contains(OverviewPresentation.clock(watchedFrom)))
    }

    @Test("With no watched span at all, the headline says so rather than sounding quiet")
    func unwatchedWindowDoesNotSoundQuiet() {
        let headline = OverviewPresentation.headline(inputs(CoverageLog(), now: noon))
        #expect(headline.text == "We have nothing recorded for today"
                || headline.text.hasPrefix("We can't answer"))
        #expect(!headline.text.contains("Nothing has crossed a line"))
    }

    // MARK: - The long scale

    @Test("A day is watched throughout only when it has no gap in it")
    func dayCellsMarkPartialDays() {
        let today = calendar.startOfDay(for: noon)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var log = CoverageLog()
        // All of yesterday, then two hours missing this morning.
        log.observe(at: yesterday, tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: today, tolerance: .seconds(86_400 * 2), resumingAfter: .appNotRunning)
        log.observe(at: today.addingTimeInterval(3600 * 4), tolerance: .seconds(20),
                    resumingAfter: .systemAsleep)
        log.observe(at: noon, tolerance: .seconds(86_400), resumingAfter: .systemAsleep)

        let cells = OverviewPresentation.dayCells(
            log: log, incidents: [], now: noon, calendar: calendar, days: 3)
        #expect(cells.count == 3)
        #expect(cells[1].isWatchedThroughout)
        #expect(!cells[2].isWatchedThroughout)
        #expect(!cells[0].isWatchedThroughout)
        // A day is too coarse to be honest about the size of a gap, so the cell says
        // partial and the day view says exactly when.
        #expect(cells[2].spoken.contains("watched"))
    }

    @Test("The long-scale note counts complete days rather than implying coverage")
    func dayScaleNoteCountsCompleteDays() {
        let today = calendar.startOfDay(for: noon)
        let log = watching(from: calendar.date(byAdding: .day, value: -29, to: today) ?? today,
                           to: noon)
        let cells = OverviewPresentation.dayCells(
            log: log, incidents: [], now: noon, calendar: calendar)
        let note = OverviewPresentation.dayScaleNote(cells)
        #expect(note.contains("of \(cells.count) days"))
        #expect(note.contains("part of that day is missing"))
    }

    /// A strip full of hatching cannot say on its own whether we failed to watch
    /// that morning or whether that morning is simply outside what we keep.
    @Test("Where the record begins is stated when the window reaches past it")
    func recordBoundaryIsStated() {
        let start = calendar.startOfDay(for: noon)
        let began = start.addingTimeInterval(3600 * 8)
        let log = watching(from: began, to: noon)
        let note = OverviewPresentation.recordBeginsNote(
            log: log, scale: .today, now: noon, calendar: calendar)
        #expect(note?.contains("Our record begins") == true)
        #expect(note?.contains("outside the period we keep") == true)
        #expect(note?.contains(OverviewPresentation.clock(noon)) == true)

        // Nothing to say when the record covers the window.
        #expect(OverviewPresentation.recordBeginsNote(
            log: watching(from: start, to: noon), scale: .today, now: noon,
            calendar: calendar) == nil)
    }

    // MARK: - The trace

    /// The design draws a day-long CPU curve. We retain about fifteen minutes and do
    /// not persist it, so the screen states the limit rather than drawing a line it
    /// never measured (FR-002, FR-057).
    @Test("The trace states the span it covers, and says so when it has none")
    func traceScopeIsStated() {
        #expect(OverviewPresentation.traceScopeNote(retained: .zero)
            .contains("No metric series is retained yet"))
        let note = OverviewPresentation.traceScopeNote(retained: .seconds(900))
        #expect(note.contains("15 minutes"))
        #expect(note.contains("The strip above covers the whole window"))
    }

    // MARK: - Nothing recorded

    @Test("No conditions recorded is never phrased as a clean bill of health")
    func noConditionsIsNotACleanBillOfHealth() {
        let note = OverviewPresentation.noConditionsNote(watched: .seconds(3600 * 5))
        #expect(note.contains("5 hr"))
        #expect(note.contains("not the same as nothing having happened"))
        #expect(OverviewPresentation.noConditionsNote(watched: .seconds(5))
            .contains("statement about us rather than about the Mac"))
    }

    // MARK: - The store's record

    @Test("The store records coverage as samples arrive")
    func storeRecordsCoverage() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        try? await Task.sleep(for: .seconds(4))

        let log = store.coverage.log
        #expect(!log.intervals.isEmpty)
        guard let began = log.earliestRecord, let latest = log.latestObservation else {
            Issue.record("no coverage recorded after four seconds of sampling")
            return
        }
        #expect(latest > began)
        // Watching begins at the first *reading*, not when `start()` was called:
        // starting the loop is not evidence that it sampled.
        #expect(log.watched(from: began, to: latest).totalSeconds > 0)
    }
}

/// FR-060, at the place it was actually broken this session.
///
/// The overview and the popover both offer the report gesture. They were built in
/// parallel and arrived with two labels for one action — the kind of drift this
/// requirement exists to stop, caught on the day rather than in six weeks.
@MainActor
@Suite("One gesture, one name")
struct ReportGestureNamingTests {
    /// Deliberately not a source-text scan. The first version of this test read
    /// `OverviewView.swift` from a relative path that does not resolve inside a
    /// test bundle, so it silently passed whatever the code said — a test that
    /// cannot fail is worse than no test, and it would have "guarded" this for
    /// months.
    ///
    /// What actually holds the property is the compiler: both surfaces reference
    /// `reportNowTitle`, so a second label cannot appear without someone deleting
    /// that reference. This pins the shared constant's identity and states where
    /// the real guarantee lives.
    @Test("One constant names the report gesture, and it says what it says")
    func oneName() {
        #expect(SlowdownReportPresentation.reportNowTitle == "It feels slow right now")
        #expect(SlowdownReportPresentation.reportEarlierTitle
            .hasPrefix("It was slow"))
        // The gesture asks for no classification: the labels are statements, not
        // questions, and neither invites the user to categorise anything (FR-064).
        for title in [SlowdownReportPresentation.reportNowTitle,
                      SlowdownReportPresentation.reportEarlierTitle] {
            #expect(!title.contains("?"), "the gesture must not ask a question")
        }
    }
}
