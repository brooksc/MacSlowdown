import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// Design 5c's "Something happened then" — a report filed against a stretch we
/// were not watching (TASK-120, FR-064, S-2).
///
/// **Why this is not just another report button.** Every other report the product
/// takes arrives alongside readings, and the readings are the better evidence. A
/// gap is the case where there are none and never will be: the coverage record's
/// whole job is to say "we can't answer for 1:40 to 2:25", and without this
/// gesture that honesty is a dead end. So the assertions below are mostly about
/// what the record must **not** claim — that it has evidence, that it was dated
/// from the filing, or that something we detected coincided with it.
@MainActor
@Suite("Reporting against a coverage gap")
struct GapReportTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 12)) ?? .now
    }

    /// Watched from midnight to 1:00, nothing until 3:00, then watched to noon.
    /// The same shape `OverviewTests.gapLeadsTheScreen` builds, so both are
    /// reasoning about one situation.
    private func logWithGap(start: Date) -> CoverageLog {
        var log = CoverageLog()
        log.observe(at: start, tolerance: .seconds(20), resumingAfter: .appNotRunning)
        log.observe(at: start.addingTimeInterval(3600), tolerance: .seconds(7200),
                    resumingAfter: .appNotRunning)
        log.observe(at: start.addingTimeInterval(3600 * 3), tolerance: .seconds(20),
                    resumingAfter: .appNotRunning)
        log.observe(at: noon, tolerance: .seconds(86_400), resumingAfter: .appNotRunning)
        return log
    }

    @Test("A gap is offered to report against; a fully watched window is not")
    func offeredOnlyWhenThereIsAGap() {
        let start = calendar.startOfDay(for: noon)

        let gap = OverviewPresentation.reportableGap(
            log: logWithGap(start: start), scale: .today, now: noon, calendar: calendar)
        #expect(gap != nil)

        // Watched throughout: the control must not be there. A report against a
        // stretch we did watch belongs to "It feels slow right now", which keeps
        // the readings.
        var solid = CoverageLog()
        solid.observe(at: start, tolerance: .seconds(20), resumingAfter: .appNotRunning)
        solid.observe(at: noon, tolerance: .seconds(86_400), resumingAfter: .appNotRunning)
        #expect(OverviewPresentation.reportableGap(
            log: solid, scale: .today, now: noon, calendar: calendar) == nil)
    }

    @Test("The button files against the same gap the sentence beneath the strip names")
    func buttonAndSentenceAgree() {
        let start = calendar.startOfDay(for: noon)
        let log = logWithGap(start: start)
        let gap = try! #require(OverviewPresentation.reportableGap(
            log: log, scale: .today, now: noon, calendar: calendar))
        let note = try! #require(OverviewPresentation.gapNote(
            log: log, scale: .today, now: noon, calendar: calendar))
        // FR-060 in miniature: two surfaces describing one gap must not pick it
        // independently.
        #expect(note.contains(OverviewPresentation.clockRange(gap, calendar: calendar)))
    }

    @Test("The report is dated from the middle of the gap, not from the filing")
    func datedFromTheGap() {
        let start = calendar.startOfDay(for: noon)
        let gap = try! #require(OverviewPresentation.reportableGap(
            log: logWithGap(start: start), scale: .today, now: noon, calendar: calendar))

        let secondsAgo = OverviewPresentation.secondsAgo(ofMiddleOf: gap, now: noon)
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: secondsAgo), reportedAt: noon)

        #expect(report.timing.isRetrospective)
        #expect(report.experiencedAt < report.reportedAt)
        // Inside the gap, and near its middle rather than either edge — the
        // evidence window is built around the moment, so aiming at an edge would
        // centre it half outside the stretch the user is pointing at.
        #expect(report.experiencedAt >= gap.from)
        #expect(report.experiencedAt <= gap.to)
        let middle = gap.from.addingTimeInterval(gap.duration.totalSeconds / 2)
        #expect(abs(report.experiencedAt.timeIntervalSince(middle)) < 1)
    }

    @Test("A gap report says it kept no readings, rather than showing nothing")
    func statesTheAbsenceOfReadings() {
        let start = calendar.startOfDay(for: noon)
        let gap = try! #require(OverviewPresentation.reportableGap(
            log: logWithGap(start: start), scale: .today, now: noon, calendar: calendar))
        let secondsAgo = OverviewPresentation.secondsAgo(ofMiddleOf: gap, now: noon)

        // Readings either side of the gap but none inside it — which is what a
        // gap is, and is why the coverage case must be `noSamplesInWindow` rather
        // than "no history".
        let outside = [
            sample(at: start.addingTimeInterval(600), cpu: 12),
            sample(at: noon.addingTimeInterval(-60), cpu: 9),
        ]
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: secondsAgo), reportedAt: noon,
            retainedSamples: outside)

        #expect(report.evidence.samples.isEmpty)
        #expect(!report.evidence.coverage.hasSamples)

        let kept = SlowdownReportPresentation.keptReadings(report)
        let outcome = SlowdownReportPresentation.gapReportOutcome(
            range: OverviewPresentation.clockRange(gap, calendar: calendar), kept: kept)
        // It says so in words, and it does not apologise or imply the report was
        // worth less for it.
        #expect(outcome.contains("It still counts"))
        #expect(!outcome.localizedCaseInsensitiveContains("unfortunately"))
        #expect(outcome.contains(OverviewPresentation.clockRange(gap, calendar: calendar)))
    }

    @Test("A gap report counts as a report without a detection, even with an incident open now")
    func countedAsUndetected() {
        let start = calendar.startOfDay(for: noon)
        let gap = try! #require(OverviewPresentation.reportableGap(
            log: logWithGap(start: start), scale: .today, now: noon, calendar: calendar))
        let secondsAgo = OverviewPresentation.secondsAgo(ofMiddleOf: gap, now: noon)

        // An incident open *right now*, hours after the gap, and its conditions
        // handed to `make` exactly as the store hands them over. Before the fix
        // that set was kept verbatim, so filing a gap report while any unrelated
        // incident happened to be open came back as a coincidence — inflating the
        // one figure FR-064 exists to produce.
        let openNow = incident(began: noon.addingTimeInterval(-300),
                               conditions: [.cpuSaturation])
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: secondsAgo), reportedAt: noon,
            incidents: [openNow],
            conditionsInForce: openNow.conditions)

        #expect(report.evidence.conditionsInForce.isEmpty)
        #expect(report.evidence.incidentID == nil)
        #expect(!report.coincidedWithDetection)
        let overlap = SlowdownDetectionOverlap(reports: [report])
        #expect(overlap.withoutDetection == 1)
        #expect(overlap.coincidingWithDetection == 0)
    }

    @Test("A report about now still keeps the conditions breaching now")
    func aReportAboutNowIsUnaffected() {
        // The narrowing above must not cost the common case its evidence.
        let openNow = incident(began: noon.addingTimeInterval(-300),
                               conditions: [.cpuSaturation])
        let report = SlowdownReport.make(
            timing: .now, reportedAt: noon,
            incidents: [openNow], conditionsInForce: openNow.conditions)

        #expect(report.evidence.conditionsInForce == [.cpuSaturation])
        #expect(report.coincidedWithDetection)
    }

    @Test("A retrospective report inside a real episode keeps that episode's conditions")
    func aRetrospectiveReportInsideAnEpisodeKeepsIts() {
        // The other side of the rule: narrowing is about *when*, not about
        // retrospective reports being worth less. An episode that genuinely
        // covers the reported moment is a coincidence and is recorded as one.
        let episode = incident(began: noon.addingTimeInterval(-3600), lasting: 1800,
                               conditions: [.memoryPressure], open: false)
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: 2700), reportedAt: noon,
            incidents: [episode], conditionsInForce: [.cpuSaturation])

        #expect(report.evidence.conditionsInForce == [.memoryPressure])
        #expect(report.coincidedWithDetection)
    }

    // MARK: - Fixtures

    private func incident(
        began: Date, lasting seconds: Double = 600,
        conditions: Set<IncidentCondition>, open: Bool = true
    ) -> Incident {
        Incident(
            id: UUID(), beganAt: began, triggeredAt: began,
            recoveryStartedAt: nil,
            closedAt: open ? nil : began.addingTimeInterval(seconds),
            conditions: conditions, severity: .moderate,
            peakCPUBusyFraction: 0.94, peakMemoryPressure: .normal)
    }

    private func sample(at date: Date, cpu: Double) -> HistorySample {
        HistorySample(
            timestamp: date, totalBusyPercentOfOneCore: cpu,
            attributedPercentOfOneCore: cpu, unattributedPercentOfOneCore: 0,
            topContributors: [])
    }
}
