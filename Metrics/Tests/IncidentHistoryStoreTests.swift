import Foundation
import Testing

@testable import Metrics

// MARK: - Fixtures

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("IncidentHistoryStoreTests-\(UUID().uuidString)",
                                isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func contributor(_ name: String, peak: Double) -> IncidentContributor {
    IncidentContributor(
        applicationID: "/Applications/\(name).app",
        displayName: name,
        bundleID: "com.example.\(name.lowercased())",
        bundlePath: "/Applications/\(name).app",
        peakPercentOfOneCore: peak,
        hasUncertainMembers: true)
}

/// An attribution sample whose confidence is genuinely derived, so a round trip has
/// something real to preserve rather than a default.
private func sample(leader: Double, total: Double, unattributed: Double) -> AttributionSample {
    AttributionSample(
        applications: [contributor("Chrome", peak: leader),
                       contributor("Xcode", peak: leader / 2)],
        totalBusyPercentOfOneCore: total,
        attributedPercentOfOneCore: total - unattributed,
        unattributedPercentOfOneCore: unattributed,
        logicalCoreCount: 10)
}

private func incident(
    closedDaysAgo: Double,
    now: Date,
    attribution: IncidentAttribution? = nil,
    id: UUID = UUID()
) -> Incident {
    let closed = now.addingTimeInterval(-closedDaysAgo * 86_400)
    var incident = Incident(
        id: id,
        beganAt: closed.addingTimeInterval(-600),
        triggeredAt: closed.addingTimeInterval(-420),
        recoveryStartedAt: closed.addingTimeInterval(-60),
        closedAt: closed,
        conditions: [.cpuSaturation, .memoryPressure],
        severity: .high,
        peakCPUBusyFraction: 0.93,
        peakMemoryPressure: .warning)
    incident.attribution = attribution
    return incident
}

private let thirtyDays = PrivacySettings(retention: .thirtyDays)

// MARK: - Schema

@Suite("The stored form is versioned")
struct IncidentHistorySchemaTests {
    /// FR-040's habit applied to our own storage: a format change must be able to
    /// migrate rather than silently discard what a user recorded.
    @Test("A written file carries a schema version, the retention and the bound")
    func fileCarriesItsSchema() throws {
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let store = IncidentHistoryStore(url: url, limit: 50)
        let now = Date()
        store.record(incident(closedDaysAgo: 1, now: now), settings: thirtyDays, now: now)

        let data = try Data(contentsOf: url)
        let decoded = try IncidentHistoryStore.decoder.decode(StoredIncidentHistory.self, from: data)
        #expect(decoded.schemaVersion == StoredIncidentHistory.currentSchemaVersion)
        #expect(decoded.retentionDays == 30)
        #expect(decoded.limit == 50)
        #expect(decoded.incidents.count == 1)
    }

    /// A file from a newer build is refused and **left alone**. Decoding half of it
    /// would show a user history we had partly invented; overwriting it would
    /// destroy history the newer build can still read.
    @Test("A file from a later schema is refused, reported, and not overwritten")
    func futureSchemaIsRefused() throws {
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let future = StoredIncidentHistory(
            schemaVersion: StoredIncidentHistory.currentSchemaVersion + 7,
            retentionDays: 30, limit: 20,
            incidents: [incident(closedDaysAgo: 1, now: Date())])
        try IncidentHistoryStore.encoder.encode(future).write(to: url)

        let store = IncidentHistoryStore(url: url)
        #expect(store.load(settings: thirtyDays).isEmpty)
        #expect(store.lastLoadFailure
            == .futureSchema(version: StoredIncidentHistory.currentSchemaVersion + 7))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// Nothing stored and something stored we cannot read are different facts, and
    /// a first run must not be reported as corruption.
    @Test("An absent file is nothing stored; a damaged one is malformed")
    func absentAndDamagedDiffer() throws {
        let directory = temporaryDirectory()
        let missing = IncidentHistoryStore(
            url: directory.appendingPathComponent("nothing.json"))
        #expect(missing.load(settings: thirtyDays).isEmpty)
        #expect(missing.lastLoadFailure == .nothingStored)

        let damaged = directory.appendingPathComponent("damaged.json")
        try Data("{not json".utf8).write(to: damaged)
        let store = IncidentHistoryStore(url: damaged)
        #expect(store.load(settings: thirtyDays).isEmpty)
        if case .malformed = store.lastLoadFailure {} else {
            Issue.record("expected malformed, got \(String(describing: store.lastLoadFailure))")
        }
    }
}

// MARK: - Attribution survives (FR-013, FR-038)

@Suite("Recorded attribution survives persistence unchanged")
struct IncidentAttributionPersistenceTests {
    /// Everything an incident concluded comes back byte-for-byte, including the
    /// confidence it carried. `Incident` is `Equatable`, so this compares the whole
    /// record rather than the fields the test happened to think of.
    @Test("An incident round-trips through a real file identically")
    func roundTripIsIdentical() throws {
        let now = Date()
        let recorded = IncidentAttribution(
            sample: sample(leader: 420, total: 900, unattributed: 380), at: now)
        let original = incident(closedDaysAgo: 2, now: now, attribution: recorded)

        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        IncidentHistoryStore(url: url).record(original, settings: thirtyDays, now: now)

        // A second store object, constructed fresh from the same URL, sharing no
        // memory with the first — the in-process equivalent of a relaunch.
        let reopened = IncidentHistoryStore(url: url)
        let restored = try #require(reopened.load(settings: thirtyDays, now: now).first)

        #expect(restored == original)
        #expect(restored.attribution?.confidence == recorded.confidence)
        #expect(restored.attribution?.applications == recorded.applications)
        #expect(restored.attribution?.logicalCoreCount == 10)
        #expect(restored.attribution?.evidence == .heuristic)
        #expect(restored.attribution?.conclusion?.confidence == recorded.confidence)
    }

    /// The load path must not re-derive confidence from the figures beside it.
    ///
    /// Proved by storing a confidence the figures would **not** produce: the sample
    /// below recomputes to `.low`, and the file says `.high`. If anything on the
    /// read path recalculated, this would come back `.low`.
    @Test("Confidence is read from the file, never recomputed from the figures")
    func confidenceIsNotRecomputed() throws {
        let now = Date()
        let unconfident = sample(leader: 10, total: 900, unattributed: 800)
        #expect(IncidentAttribution.confidence(for: unconfident) == .low)

        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let stored = IncidentAttribution(sample: unconfident, at: now)
        try IncidentHistoryStore.encoder
            .encode(StoredIncidentHistory(
                retentionDays: 30, limit: 20,
                incidents: [incident(closedDaysAgo: 1, now: now, attribution: stored)]))
            .write(to: url)

        // Rewrite just the confidence in the stored JSON, so the file disagrees with
        // what the figures would give.
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"confidence\":\"low\"",
                                         with: "\"confidence\":\"high\"")
        #expect(text.contains("\"confidence\":\"high\""))
        try Data(text.utf8).write(to: url)

        let restored = try #require(
            IncidentHistoryStore(url: url).load(settings: thirtyDays, now: now).first)
        #expect(restored.attribution?.confidence == .high)
    }

    /// An incident with nothing attributed comes back with nothing attributed. The
    /// gap is the record; filling it from live state is the failure FR-038 forbids.
    @Test("An unattributed incident does not acquire an attribution on load")
    func absentAttributionStaysAbsent() throws {
        let now = Date()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        IncidentHistoryStore(url: url).record(
            incident(closedDaysAgo: 1, now: now), settings: thirtyDays, now: now)

        let restored = try #require(
            IncidentHistoryStore(url: url).load(settings: thirtyDays, now: now).first)
        #expect(restored.attribution == nil)
    }

    /// Actions and suppressions are the evidence behind "recovered after you acted"
    /// and "not alerted because you marked this expected". They have to persist or
    /// those sentences quietly stop being sayable after a restart.
    @Test("Linked actions and suppressions survive the round trip")
    func linkedEvidenceSurvives() throws {
        let now = Date()
        var original = incident(closedDaysAgo: 1, now: now)
        let verification = ActionVerifier.verify(
            action: .activate, target: "Chrome", result: .succeeded,
            before: 0.9, after: 0.4, window: .seconds(60),
            requestedAt: original.beganAt.addingTimeInterval(30))
        let linkedAction = original.record(verification)
        #expect(linkedAction)
        let linkedSuppression = original.record(SuppressedDetection(
            application: "Chrome", classification: .expected,
            at: original.beganAt.addingTimeInterval(45), severity: .high))
        #expect(linkedSuppression)

        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        IncidentHistoryStore(url: url).record(original, settings: thirtyDays, now: now)
        let restored = try #require(
            IncidentHistoryStore(url: url).load(settings: thirtyDays, now: now).first)

        #expect(restored.actions == original.actions)
        #expect(restored.suppressions == original.suppressions)
        #expect(restored.outcome == original.outcome)
    }
}

// MARK: - Retention is enforced, not merely configured

@Suite("Retention is enforced on write")
struct IncidentRetentionEnforcementTests {
    /// The defect this task exists to close: `RetentionPolicy.expired` was defined
    /// and nothing called it.
    @Test("An incident past the retention period is not written")
    func expiredIncidentsAreNotStored() throws {
        let now = Date()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let store = IncidentHistoryStore(url: url)

        store.record(incident(closedDaysAgo: 40, now: now), settings: thirtyDays, now: now)
        let kept = store.record(incident(closedDaysAgo: 1, now: now),
                                settings: thirtyDays, now: now)

        #expect(kept.count == 1)
        let onDisk = try IncidentHistoryStore.decoder.decode(
            StoredIncidentHistory.self, from: Data(contentsOf: url))
        #expect(onDisk.incidents.count == 1)
    }

    /// Enforcement must not depend on an incident closing or a screen opening. This
    /// is the path the sampling loop calls every few seconds.
    @Test("Retention runs with nothing to store and no screen open")
    func enforcementRunsUnprompted() throws {
        let now = Date()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let store = IncidentHistoryStore(url: url)
        // Written when they were fresh: 89 days of retention holds both.
        let ninety = PrivacySettings(retention: .ninetyDays)
        store.record(incident(closedDaysAgo: 40, now: now), settings: ninety, now: now)
        store.record(incident(closedDaysAgo: 1, now: now), settings: ninety, now: now)
        #expect(store.incidents.count == 2)

        let removed = store.enforceRetention(settings: thirtyDays, now: now)
        #expect(removed.count == 1)
        #expect(store.incidents.count == 1)
        let onDisk = try IncidentHistoryStore.decoder.decode(
            StoredIncidentHistory.self, from: Data(contentsOf: url))
        #expect(onDisk.incidents.count == 1)
        #expect(onDisk.retentionDays == 30)
    }

    /// Nothing expired must not mean a rewrite. At a 2-second cadence a write per
    /// sample would be the kind of disk traffic FR-030 exists to bound.
    @Test("Nothing expiring writes nothing")
    func noExpiryNoWrite() throws {
        let now = Date()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let store = IncidentHistoryStore(url: url)
        store.record(incident(closedDaysAgo: 1, now: now), settings: thirtyDays, now: now)
        let firstWrite = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)

        #expect(store.enforceRetention(settings: thirtyDays, now: now).isEmpty)
        let secondWrite = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        #expect(firstWrite == secondWrite)
    }

    /// Shortening the period in Settings is applied by the same enforcement path, so
    /// the interface's figure and the disk's contents cannot disagree (FR-029).
    @Test("Shortening the retention period removes what no longer fits")
    func shorteningRetentionPrunes() {
        let now = Date()
        let store = IncidentHistoryStore(url: nil)
        store.record(incident(closedDaysAgo: 20, now: now), settings: thirtyDays, now: now)
        #expect(store.incidents.count == 1)
        #expect(store.enforceRetention(
            settings: PrivacySettings(retention: .sevenDays), now: now).count == 1)
        #expect(store.incidents.isEmpty)
    }

    /// The second bound. A period alone bounds nothing on a machine that is in
    /// trouble all day, which is why the footer states both.
    @Test("The count bound applies within the retention period")
    func countBoundApplies() throws {
        let now = Date()
        let store = IncidentHistoryStore(url: nil, limit: 3)
        for day in 1...10 {
            store.record(incident(closedDaysAgo: Double(day), now: now),
                         settings: thirtyDays, now: now)
        }
        #expect(store.incidents.count == 3)
        // Most recent kept, oldest dropped.
        let newest = try #require(store.incidents.first?.closedAt)
        #expect(now.timeIntervalSince(newest) < 2 * 86_400)
    }

    /// Loading applies retention too. A Mac switched off for two months must not
    /// show a screenful of expired incidents for the seconds before the next write.
    @Test("Retention is applied on the way in as well as on the way out")
    func loadPrunes() throws {
        let now = Date()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        try IncidentHistoryStore.encoder
            .encode(StoredIncidentHistory(
                retentionDays: 90, limit: 20,
                incidents: [incident(closedDaysAgo: 40, now: now),
                            incident(closedDaysAgo: 2, now: now)]))
            .write(to: url)

        #expect(IncidentHistoryStore(url: url)
            .load(settings: thirtyDays, now: now).count == 1)
    }
}

// MARK: - Deletion

@Suite("Deleting incident history")
struct IncidentHistoryDeletionTests {
    @Test("Delete-all removes the file, forgets the incidents, and says how much went")
    func deleteReportsWhatWent() {
        let now = Date()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        let store = IncidentHistoryStore(url: url)
        store.record(incident(closedDaysAgo: 1, now: now), settings: thirtyDays, now: now)
        store.record(incident(closedDaysAgo: 2, now: now), settings: thirtyDays, now: now)

        let removed = store.deleteAll()
        #expect(removed.incidents == 2)
        #expect(removed.bytes > 0)
        #expect(store.incidents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(IncidentHistoryStore(url: url).load(settings: thirtyDays, now: now).isEmpty)
    }
}

// MARK: - Written where another process can read it

@Suite("History reaches the filesystem, not just another object")
struct IncidentHistoryOnDiskTests {
    /// The in-process round trip proves our decoder; this proves the bytes are
    /// genuinely on the filesystem and readable outside this address space.
    ///
    /// **It is not a restart test.** It says nothing about the app relaunching, the
    /// container path resolving under the sandbox, or `MonitorStore` reading the
    /// file at launch — only that a second, unrelated process sees what we wrote.
    @Test("A separate process can see the written record")
    func anotherProcessSeesTheFile() throws {
        let now = Date()
        let identifier = UUID()
        let url = temporaryDirectory().appendingPathComponent("incidents.json")
        IncidentHistoryStore(url: url).record(
            incident(closedDaysAgo: 1, now: now, id: identifier),
            settings: thirtyDays, now: now)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-c", identifier.uuidString, url.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(String(decoding: data, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines) == "1")
    }
}
