import Foundation
import Testing

@testable import Metrics

// MARK: - Fixtures

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SlowdownReportStoreTests-\(UUID().uuidString)",
                                isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func history(endingAt end: Date, count: Int) -> [HistorySample] {
    (0..<count).map { step in
        HistorySample(
            timestamp: end.addingTimeInterval(-Double(count - 1 - step)),
            totalBusyPercentOfOneCore: 137.5 + Double(step),
            attributedPercentOfOneCore: 90.25,
            unattributedPercentOfOneCore: 47.25,
            topContributors: [
                ContributorSummary(pid: 501, startTime: 12_345_678, command: "kernel_task",
                                   percentOfOneCore: 90.25, residentBytes: 987_654)
            ])
    }
}

/// A report with real evidence behind it, so a round trip has something to preserve.
private func report(daysAgo: Double, now: Date,
                    conditionsInForce: Set<IncidentCondition> = [],
                    incidents: [Incident] = []) -> SlowdownReport {
    let at = now.addingTimeInterval(-daysAgo * 86_400)
    return SlowdownReport.make(
        timing: .now, reportedAt: at,
        retainedSamples: history(endingAt: at, count: 30),
        incidents: incidents,
        conditionsInForce: conditionsInForce,
        liveAttribution: AttributionSample(
            applications: [
                IncidentContributor(applicationID: "/Applications/Safari.app",
                                    displayName: "Safari",
                                    bundleID: "com.apple.Safari",
                                    bundlePath: "/Applications/Safari.app",
                                    peakPercentOfOneCore: 212.5,
                                    hasUncertainMembers: true)
            ],
            totalBusyPercentOfOneCore: 400.5,
            attributedPercentOfOneCore: 300.25,
            unattributedPercentOfOneCore: 100.25,
            logicalCoreCount: 8))
}

private let thirtyDays = PrivacySettings(retention: .thirtyDays)

// MARK: - The file

@Suite("Reports are stored in a versioned file")
struct SlowdownReportStorageTests {
    @Test("A written file carries a schema version, the retention and the bound")
    func fileCarriesItsSchema() throws {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let store = SlowdownReportStore(url: url, limit: 25)
        let now = Date()
        store.record(report(daysAgo: 1, now: now), settings: thirtyDays, now: now)

        let data = try Data(contentsOf: url)
        let decoded = try SlowdownReportStore.decoder
            .decode(StoredSlowdownReports.self, from: data)
        #expect(decoded.schemaVersion == StoredSlowdownReports.currentSchemaVersion)
        #expect(decoded.retentionDays == 30)
        #expect(decoded.limit == 25)
        #expect(decoded.reports.count == 1)
    }

    /// The round trip goes through a real file and a second store, because an
    /// encoder that agrees with itself is not evidence that a report survives a
    /// restart.
    @Test("A report survives a restart exactly, dates included")
    func roundTripThroughAFile() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let original = report(daysAgo: 0.5, now: now)
        SlowdownReportStore(url: url).record(original, settings: thirtyDays, now: now)

        let reopened = SlowdownReportStore(url: url)
        let restored = reopened.load(settings: thirtyDays, now: now)

        #expect(restored == [original])
        #expect(reopened.lastLoadFailure == nil)
        // Spelled out rather than left to Equatable, because it is the property
        // TASK-72 lost to ISO-8601 truncation and the one a coincidence with an
        // incident is decided on.
        #expect(restored.first?.reportedAt == original.reportedAt)
        #expect(restored.first?.experiencedAt == original.experiencedAt)
        #expect(restored.first?.evidence.window == original.evidence.window)
        #expect(restored.first?.evidence.samples.first?.timestamp
            == original.evidence.samples.first?.timestamp)
        #expect(restored.first?.evidence.attribution == original.evidence.attribution)
        #expect(restored.first?.evidence.attributionOrigin == .sampledAtReport)
    }

    /// The most informative record in the store is the one that matched nothing, so
    /// it is the one that must survive a restart intact.
    @Test("A report matching no detected condition round-trips as itself")
    func unmatchedReportRoundTrips() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let unmatched = SlowdownReport.make(
            timing: .recently(secondsAgo: 240), reportedAt: now,
            retainedSamples: history(endingAt: now, count: 600))
        #expect(!unmatched.coincidedWithDetection)

        SlowdownReportStore(url: url).record(unmatched, settings: thirtyDays, now: now)
        let restored = SlowdownReportStore(url: url).load(settings: thirtyDays, now: now)

        #expect(restored == [unmatched])
        #expect(restored.first?.coincidedWithDetection == false)
        #expect(restored.first?.timing == .recently(secondsAgo: 240))
        #expect(restored.first?.evidence.coverage.hasSamples == true)
    }

    @Test("A file from a newer build is refused and left in place")
    func futureSchemaIsRefused() throws {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let future = StoredSlowdownReports(
            schemaVersion: StoredSlowdownReports.currentSchemaVersion + 1,
            retentionDays: 30, limit: 100, reports: [report(daysAgo: 0, now: now)])
        try SlowdownReportStore.encoder.encode(future).write(to: url)

        let store = SlowdownReportStore(url: url)
        #expect(store.load(settings: thirtyDays, now: now).isEmpty)
        #expect(store.lastLoadFailure
            == .futureSchema(version: StoredSlowdownReports.currentSchemaVersion + 1))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Nothing stored and something unreadable are different answers")
    func loadFailuresAreNamed() throws {
        let directory = temporaryDirectory()
        let missing = SlowdownReportStore(url: directory.appendingPathComponent("none.json"))
        #expect(missing.load(settings: thirtyDays).isEmpty)
        #expect(missing.lastLoadFailure == .nothingStored)

        let garbage = directory.appendingPathComponent("garbage.json")
        try Data("not json".utf8).write(to: garbage)
        let broken = SlowdownReportStore(url: garbage)
        #expect(broken.load(settings: thirtyDays).isEmpty)
        if case .malformed = broken.lastLoadFailure {} else {
            Issue.record("expected malformed, got \(String(describing: broken.lastLoadFailure))")
        }

        let memoryOnly = SlowdownReportStore(url: nil)
        #expect(memoryOnly.load(settings: thirtyDays).isEmpty)
        #expect(memoryOnly.lastLoadFailure == .nothingStored)
    }

    /// FR-029: with restart persistence off, nothing about a report reaches the disk
    /// at all — not a file with an empty array in it.
    @Test("Persistence off writes nothing, and the report is still held in memory")
    func persistenceOffWritesNothing() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let store = SlowdownReportStore(url: url)
        let settings = PrivacySettings(persistAcrossRestarts: false)
        store.record(report(daysAgo: 0, now: now), settings: settings, now: now)

        #expect(store.reports.count == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Deleting reports what went")
    func deleteAllReportsWhatWent() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let store = SlowdownReportStore(url: url)
        store.record(report(daysAgo: 0, now: now), settings: thirtyDays, now: now)
        store.record(report(daysAgo: 1, now: now), settings: thirtyDays, now: now)

        let removed = store.deleteAll()
        #expect(removed.reports == 2)
        #expect(removed.bytes > 0)
        #expect(store.reports.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: - Retention

@Suite("Reports are kept under the same rules as incidents")
struct SlowdownReportRetentionTests {
    @Test("A report past the retention period is not kept, on the way in or out")
    func ageBound() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let store = SlowdownReportStore(url: url)
        let recent = report(daysAgo: 2, now: now)
        store.record(recent, settings: thirtyDays, now: now)
        store.record(report(daysAgo: 40, now: now), settings: thirtyDays, now: now)

        #expect(store.reports.map(\.id) == [recent.id])
        // And a file that somehow contains an expired report does not show one for
        // the seconds before the next write prunes it.
        #expect(SlowdownReportStore(url: url).load(settings: thirtyDays, now: now)
            .map(\.id) == [recent.id])
    }

    @Test("The retention setting is the one in force, not the one it was written under")
    func retentionSettingIsCurrent() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        SlowdownReportStore(url: url)
            .record(report(daysAgo: 10, now: now), settings: thirtyDays, now: now)

        let reopened = SlowdownReportStore(url: url)
        #expect(reopened.load(settings: PrivacySettings(retention: .sevenDays),
                              now: now).isEmpty)
    }

    /// A period alone bounds nothing on a machine somebody is having a bad week
    /// with, so there is a count bound too — and whichever bites first is what is
    /// kept.
    @Test("The count bound applies as well as the age bound")
    func countBound() {
        let now = Date()
        let store = SlowdownReportStore(url: nil, limit: 3)
        for day in 0..<10 {
            store.record(report(daysAgo: Double(day), now: now), settings: thirtyDays, now: now)
        }
        #expect(store.reports.count == 3)
        // Most recent first, and it is the recent ones that survive.
        let dates = store.reports.map(\.reportedAt)
        #expect(dates == dates.sorted(by: >))
        #expect(dates.first == now)
    }

    @Test("Retention is enforced without being asked to store anything")
    func enforceRetentionPrunesInPlace() {
        let url = temporaryDirectory().appendingPathComponent("slowdown-reports.json")
        let now = Date()
        let store = SlowdownReportStore(url: url)
        store.record(report(daysAgo: 29, now: now), settings: thirtyDays, now: now)

        // Nothing has expired yet: no work, and no disk traffic.
        #expect(store.enforceRetention(settings: thirtyDays, now: now).isEmpty)

        let later = now.addingTimeInterval(3 * 86_400)
        let removed = store.enforceRetention(settings: thirtyDays, now: later)
        #expect(removed.count == 1)
        #expect(store.reports.isEmpty)
        #expect(SlowdownReportStore(url: url).load(settings: thirtyDays, now: later).isEmpty)
    }

    @Test("Recording the same report twice does not duplicate it")
    func recordIsIdempotentOnID() {
        let now = Date()
        let store = SlowdownReportStore(url: nil)
        let one = report(daysAgo: 0, now: now)
        store.record(one, settings: thirtyDays, now: now)
        store.record(one, settings: thirtyDays, now: now)
        #expect(store.reports.count == 1)
    }
}

// MARK: - Querying

@Suite("Reports can be queried for a window")
struct SlowdownReportQueryTests {
    /// Matched on the moment the report is about. A retrospective report filed in
    /// the evening about the afternoon belongs to the afternoon.
    @Test("A query matches the reported moment, not the moment of the gesture")
    func queryMatchesExperiencedMoment() {
        let now = Date()
        let store = SlowdownReportStore(url: nil)
        let retrospective = SlowdownReport.make(
            timing: .recently(secondsAgo: 7200), reportedAt: now)
        store.record(retrospective, settings: thirtyDays, now: now)

        let afternoon = DateInterval(start: now.addingTimeInterval(-8000),
                                     end: now.addingTimeInterval(-6000))
        #expect(store.reports(in: afternoon).map(\.id) == [retrospective.id])
        #expect(store.reports(in: DateInterval(start: now.addingTimeInterval(-60),
                                               end: now)).isEmpty)
    }

    @Test("The reports that matched nothing can be asked for directly")
    func unmatchedReportsAreQueryable() {
        let now = Date()
        let store = SlowdownReportStore(url: nil)
        let matched = report(daysAgo: 0, now: now, conditionsInForce: [.cpuSaturation])
        let unmatched = report(daysAgo: 1, now: now)
        store.record(matched, settings: thirtyDays, now: now)
        store.record(unmatched, settings: thirtyDays, now: now)

        #expect(store.reportsWithoutDetection().map(\.id) == [unmatched.id])
        let overlap = SlowdownDetectionOverlap(reports: store.reports)
        #expect(overlap.reports == 2)
        #expect(overlap.coincidingWithDetection == 1)
        #expect(overlap.withoutDetection == 1)
    }
}
