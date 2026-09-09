import Foundation
import Testing

@testable import Metrics

// MARK: - Fixtures

private func contributor(_ name: String, cpu: Double = 40) -> IncidentContributor {
    IncidentContributor(
        applicationID: "/Applications/\(name).app", displayName: name,
        bundlePath: "/Applications/\(name).app", peakPercentOfOneCore: cpu)
}

private func attribution(_ contributors: [IncidentContributor]) -> AttributionSample {
    AttributionSample(
        applications: contributors,
        totalBusyPercentOfOneCore: 200, attributedPercentOfOneCore: 120,
        unattributedPercentOfOneCore: 80, logicalCoreCount: 8)
}

private func report(
    at date: Date,
    applications: [IncidentContributor]? = nil,
    conditions: Set<IncidentCondition> = []
) -> SlowdownReport {
    SlowdownReport.make(
        timing: .now, reportedAt: date,
        conditionsInForce: conditions,
        liveAttribution: applications.map(attribution))
}

private let calendar = Calendar(identifier: .gregorian)

private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(
        year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

// MARK: - Tests

@Suite("What a person's reports have in common (FR-064, design 5d)")
struct SlowdownReportPatternTests {
    /// One report has nothing to be compared against. Saying something anyway is
    /// how a comparison becomes a guess.
    @Test("A single report yields no pattern")
    func oneReportSaysNothing() {
        let only = report(at: date(day: 1, hour: 14), applications: [contributor("Xcode")])
        #expect(SlowdownReportPatterns.pattern(in: [only]) == nil)
        #expect(SlowdownReportPatterns.pattern(in: []) == nil)
    }

    @Test("An application recorded in every report is the pattern")
    func sharedApplication() {
        let reports = [
            report(at: date(day: 1, hour: 9),
                   applications: [contributor("Xcode", cpu: 310), contributor("Mail")]),
            report(at: date(day: 2, hour: 15),
                   applications: [contributor("Xcode", cpu: 190), contributor("Safari")]),
            report(at: date(day: 3, hour: 20),
                   applications: [contributor("Notes"), contributor("Xcode", cpu: 88)]),
        ]
        #expect(SlowdownReportPatterns.pattern(in: reports)
            == .sharedApplication(name: "Xcode", reports: 3))
    }

    /// "All three had Chrome running" must not mean "the two we had readings for
    /// did". A report with nothing recorded disqualifies the comparison.
    @Test("A report with no attribution disqualifies the shared-application claim")
    func missingAttributionDisqualifies() {
        let reports = [
            report(at: date(day: 1, hour: 9), applications: [contributor("Xcode")]),
            report(at: date(day: 2, hour: 15)),
        ]
        #expect(SlowdownReportPatterns.sharedApplication(in: reports) == nil)
    }

    @Test("No application common to all reports is no pattern")
    func noSharedApplication() {
        let reports = [
            report(at: date(day: 1, hour: 9), applications: [contributor("Xcode")]),
            report(at: date(day: 2, hour: 15), applications: [contributor("Safari")]),
        ]
        #expect(SlowdownReportPatterns.sharedApplication(in: reports) == nil)
    }

    @Test("Reports in the same part of the day, on different days, are a pattern")
    func sameTimeOfDay() {
        let reports = [
            report(at: date(day: 1, hour: 14, minute: 10), conditions: [.cpuSaturation]),
            report(at: date(day: 3, hour: 15, minute: 40), conditions: [.memoryPressure]),
        ]
        #expect(SlowdownReportPatterns.pattern(in: reports)
            == .sameTimeOfDay(earliestHour: 14, latestHour: 15, reports: 2, days: 2))
    }

    /// Otherwise the claim is an arithmetic restatement of "these were all this
    /// afternoon", which the user already knows.
    @Test("Reports on one day are not a time-of-day pattern")
    func oneDayIsNotATimeOfDayPattern() {
        let reports = [
            report(at: date(day: 1, hour: 14), conditions: [.cpuSaturation]),
            report(at: date(day: 1, hour: 15), conditions: [.cpuSaturation]),
        ]
        #expect(SlowdownReportPatterns.sameTimeOfDay(in: reports, calendar: calendar) == nil)
    }

    @Test("Hours further apart than the band are not a pattern")
    func widelySpacedHours() {
        let reports = [
            report(at: date(day: 1, hour: 9)),
            report(at: date(day: 2, hour: 18)),
        ]
        #expect(SlowdownReportPatterns.sameTimeOfDay(in: reports, calendar: calendar) == nil)
    }

    /// The case the instrument exists for: repeated slowdowns our detection was
    /// silent about.
    @Test("Reports that coincided with nothing are themselves the pattern")
    func noneCoincidedWithDetection() {
        let reports = [
            report(at: date(day: 1, hour: 9)),
            report(at: date(day: 4, hour: 18)),
            report(at: date(day: 6, hour: 11)),
        ]
        #expect(SlowdownReportPatterns.pattern(in: reports, calendar: calendar)
            == .noneCoincidedWithDetection(reports: 3))
    }

    @Test("One report coinciding with a condition withdraws that claim")
    func oneDetectionWithdrawsIt() {
        let reports = [
            report(at: date(day: 1, hour: 9)),
            report(at: date(day: 4, hour: 18), conditions: [.memoryPressure]),
        ]
        #expect(SlowdownReportPatterns.noneCoincidedWithDetection(in: reports) == nil)
        // And with nothing else to say, nothing is said.
        #expect(SlowdownReportPatterns.pattern(in: reports, calendar: calendar) == nil)
    }

    /// Specificity, not importance: an application the user can go and look at
    /// beats a time of day, which beats "we saw nothing either time".
    @Test("The most specific pattern is the one returned")
    func specificityOrder() {
        let reports = [
            report(at: date(day: 1, hour: 14), applications: [contributor("Xcode")]),
            report(at: date(day: 2, hour: 14), applications: [contributor("Xcode")]),
        ]
        #expect(SlowdownReportPatterns.pattern(in: reports, calendar: calendar)
            == .sharedApplication(name: "Xcode", reports: 2))
        // All three were true of that set.
        #expect(SlowdownReportPatterns.sameTimeOfDay(in: reports, calendar: calendar) != nil)
        #expect(SlowdownReportPatterns.noneCoincidedWithDetection(in: reports) != nil)
    }
}

@Suite("Withdrawing a report (FR-064, design 5d)")
struct SlowdownReportDeletionTests {
    private let settings = PrivacySettings(retention: .thirtyDays)

    @Test("A deleted report is gone from memory and from the file")
    func deleteReachesTheFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlowdownReportDeletionTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reports.json")

        let store = SlowdownReportStore(url: url)
        let kept = report(at: Date().addingTimeInterval(-60))
        let withdrawn = report(at: Date())
        store.record(kept, settings: settings)
        store.record(withdrawn, settings: settings)

        let remaining = store.delete(id: withdrawn.id, settings: settings)
        #expect(remaining.map(\.id) == [kept.id])
        #expect(SlowdownReportStore(url: url).load(settings: settings).map(\.id) == [kept.id])
    }

    @Test("Deleting the last report leaves an empty file, not the old one")
    func deletingTheLastOneWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlowdownReportDeletionTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reports.json")

        let store = SlowdownReportStore(url: url)
        let only = report(at: Date())
        store.record(only, settings: settings)
        store.delete(id: only.id, settings: settings)

        #expect(SlowdownReportStore(url: url).load(settings: settings).isEmpty)
    }

    @Test("Deleting something that is not there changes nothing")
    func unknownIDIsANoOp() {
        let store = SlowdownReportStore(url: nil)
        let kept = report(at: Date())
        store.record(kept, settings: settings)
        #expect(store.delete(id: UUID(), settings: settings).map(\.id) == [kept.id])
    }
}
