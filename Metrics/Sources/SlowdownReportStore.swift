import Foundation
import Synchronization

/// The on-disk form of user-reported slowdowns (FR-064, FR-029).
///
/// Versioned for the reason `StoredIncidentHistory` is: a later change to what a
/// report records must be able to migrate rather than fail to decode and silently
/// discard evidence the user gave us. That matters more here than for incidents —
/// an incident we lose can happen again and be detected again, while a report is a
/// thing a person did once, and losing it loses the only record of a slowdown we
/// never saw.
///
/// The retention and the count bound travel with the file so it can be read and
/// understood without the settings that produced it.
public struct StoredSlowdownReports: Sendable, Codable, Equatable {
    /// Step this whenever the meaning of an existing field changes. Adding a field
    /// with a default does not require a step.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let writtenAt: Date
    /// The retention period in force when this was written.
    public let retentionDays: Int
    /// The count bound in force when this was written.
    public let limit: Int
    /// Most recent first, matching the order the app holds them in.
    public let reports: [SlowdownReport]

    public init(schemaVersion: Int = StoredSlowdownReports.currentSchemaVersion,
                writtenAt: Date = Date(), retentionDays: Int, limit: Int,
                reports: [SlowdownReport]) {
        self.schemaVersion = schemaVersion
        self.writtenAt = writtenAt
        self.retentionDays = retentionDays
        self.limit = limit
        self.reports = reports
    }
}

/// User-reported slowdowns that survive a restart, with retention enforced on every
/// write (FR-064, FR-029).
///
/// Deliberately a second store beside `IncidentHistoryStore` rather than a field on
/// it. A report is not an incident and must never be able to become one: incidents
/// are things we detected, reports are things a person told us, and the entire value
/// of the instrument is that the two sets differ. Keeping them in one file would
/// also mean a schema step on either forced one on both.
///
/// What is shared is the *policy*: the same `PrivacySettings.retention`, the same
/// `persistAcrossRestarts` switch, the same "delete everything" path, and a count
/// bound alongside the age bound because a period alone bounds nothing on a machine
/// that is in trouble all day.
///
/// Nothing here is ever transmitted. The file is written in MacSlowdown's own
/// container, which no other app can read.
public final class SlowdownReportStore: Sendable {
    /// The count bound.
    ///
    /// Lower than the incident bound on purpose. A report is a deliberate human
    /// gesture, so hundreds of them is not a plausible month; and each one carries
    /// up to `SlowdownReportPolicy.maximumSamples` retained samples, which makes a
    /// report several times the size of an incident on disk. 100 keeps the file in
    /// the same order of magnitude as `incidents.json` while being far more than a
    /// 90-day view can usefully draw.
    public static let defaultLimit = 100

    /// `nil` keeps reports in memory only, which is what every test that is not
    /// about persistence wants.
    public let url: URL?
    public let limit: Int

    private struct State {
        var reports: [SlowdownReport] = []
        var lastLoadFailure: IncidentHistoryLoadFailure?
    }

    private let state = Mutex(State())

    public init(url: URL?, limit: Int = SlowdownReportStore.defaultLimit) {
        self.url = url
        self.limit = max(1, limit)
    }

    /// Most recent first.
    public var reports: [SlowdownReport] { state.withLock { $0.reports } }

    /// Why the last `load()` produced nothing, or nil if it produced something.
    ///
    /// The incident store's failure type is reused rather than duplicated: the four
    /// ways a stored file can fail us are the same four, and a second enum with the
    /// same cases would only invite the two to drift apart.
    public var lastLoadFailure: IncidentHistoryLoadFailure? {
        state.withLock { $0.lastLoadFailure }
    }

    // MARK: - Reading

    /// Reads what a previous run wrote, applying retention to what it finds.
    ///
    /// Retention is applied on the way **in** as well as out, so a machine that was
    /// off for two months does not show expired reports for the seconds before the
    /// next write prunes them.
    ///
    /// Nothing is recomputed. A report's evidence is what was recorded around the
    /// moment the user pointed at, and re-deciding any of it against the machine
    /// this file is decoded on would replace their afternoon with ours.
    @discardableResult
    public func load(settings: PrivacySettings, now: Date = Date()) -> [SlowdownReport] {
        guard let url else {
            state.withLock { $0.lastLoadFailure = .nothingStored }
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let failure: IncidentHistoryLoadFailure =
                FileManager.default.fileExists(atPath: url.path)
                    ? .unreadable(error.localizedDescription)
                    : .nothingStored
            state.withLock { $0.lastLoadFailure = failure }
            return []
        }

        let stored: StoredSlowdownReports
        do {
            stored = try Self.decoder.decode(StoredSlowdownReports.self, from: data)
        } catch {
            state.withLock { $0.lastLoadFailure = .malformed(error.localizedDescription) }
            return []
        }

        guard stored.schemaVersion <= StoredSlowdownReports.currentSchemaVersion else {
            // A file from a newer build. Refuse it and leave it in place, because
            // overwriting it would destroy reports the newer build can still read.
            state.withLock { $0.lastLoadFailure = .futureSchema(version: stored.schemaVersion) }
            return []
        }

        let kept = Self.bounded(stored.reports, settings: settings, limit: limit, now: now)
        state.withLock {
            $0.reports = kept
            $0.lastLoadFailure = nil
        }
        return kept
    }

    // MARK: - Writing

    /// Records a report and writes the pruned set.
    ///
    /// Returns what was retained, so a caller updates its own state from what was
    /// actually kept rather than from what it offered.
    @discardableResult
    public func record(_ report: SlowdownReport, settings: PrivacySettings,
                       now: Date = Date()) -> [SlowdownReport] {
        let kept = state.withLock { state -> [SlowdownReport] in
            var all = state.reports.filter { $0.id != report.id }
            all.insert(report, at: 0)
            state.reports = Self.bounded(all, settings: settings, limit: limit, now: now)
            return state.reports
        }
        write(kept, settings: settings, now: now)
        return kept
    }

    /// Applies retention without being asked to store anything.
    ///
    /// This is what makes the period real on a machine that is simply left running.
    /// It writes only when something actually expired, so calling it every sample
    /// costs one date comparison per retained report and no disk traffic.
    ///
    /// Returns the reports removed, so a caller can tell "nothing expired" from "we
    /// did not look".
    @discardableResult
    public func enforceRetention(settings: PrivacySettings,
                                 now: Date = Date()) -> [SlowdownReport] {
        let (removed, kept) = state.withLock { state -> ([SlowdownReport], [SlowdownReport]) in
            let kept = Self.bounded(state.reports, settings: settings, limit: limit, now: now)
            guard kept.count != state.reports.count else { return ([], kept) }
            let keptIDs = Set(kept.map(\.id))
            let removed = state.reports.filter { !keptIDs.contains($0.id) }
            state.reports = kept
            return (removed, kept)
        }
        guard !removed.isEmpty else { return [] }
        write(kept, settings: settings, now: now)
        return removed
    }

    /// Withdraws one report, in memory and on disk.
    ///
    /// A report is the one thing in this product that is the user's own statement
    /// rather than our measurement, so they get to take it back — and taking it
    /// back has to reach the file, not only the screen, or the next launch would
    /// show them a record they had deleted.
    ///
    /// Returns what remains, so a caller updates from what was actually kept.
    @discardableResult
    public func delete(id: UUID, settings: PrivacySettings,
                       now: Date = Date()) -> [SlowdownReport] {
        let (changed, kept) = state.withLock { state -> (Bool, [SlowdownReport]) in
            let remaining = state.reports.filter { $0.id != id }
            guard remaining.count != state.reports.count else { return (false, state.reports) }
            state.reports = remaining
            return (true, remaining)
        }
        guard changed else { return kept }
        // Written even when nothing remains: an empty document is what says the
        // reports were withdrawn, where leaving the old file would restore them.
        write(kept, settings: settings, now: now)
        return kept
    }

    /// Deletes the stored reports and forgets them in memory.
    ///
    /// Returns how many reports and how many bytes went, because a "delete
    /// everything" that reports nothing is indistinguishable from a no-op.
    @discardableResult
    public func deleteAll() -> (reports: Int, bytes: UInt64) {
        let count = state.withLock { state -> Int in
            let count = state.reports.count
            state.reports = []
            return count
        }
        var bytes: UInt64 = 0
        if let url {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if (try? FileManager.default.removeItem(at: url)) != nil {
                bytes = UInt64(size)
            }
        }
        return (count, bytes)
    }

    // MARK: - Querying

    /// Reports whose reported moment falls inside an interval, most recent first.
    ///
    /// Matched on `experiencedAt`, not on when the gesture was made: a retrospective
    /// report is about the earlier moment, and a query for "yesterday afternoon"
    /// that missed it because it was filed in the evening would be answering a
    /// question nobody asked.
    public func reports(in interval: DateInterval) -> [SlowdownReport] {
        state.withLock { $0.reports }.filter { interval.contains($0.experiencedAt) }
    }

    /// Reports made while nothing we watch had crossed a line.
    ///
    /// The set this feature exists to accumulate. Offered as a query rather than
    /// left to each caller to filter, so "a report that matched nothing" has one
    /// definition (FR-064).
    public func reportsWithoutDetection() -> [SlowdownReport] {
        state.withLock { $0.reports }.filter { !$0.coincidedWithDetection }
    }

    // MARK: - Bounds

    /// Age first, then count. Most recent first on the way out.
    static func bounded(_ reports: [SlowdownReport], settings: PrivacySettings,
                        limit: Int, now: Date) -> [SlowdownReport] {
        let withinRetention = RetentionPolicy.retained(reports, settings: settings, now: now)
        return Array(
            withinRetention
                .sorted { $0.reportedAt > $1.reportedAt }
                .prefix(limit))
    }

    // MARK: - Disk

    /// Dates are encoded numerically, **not** as ISO-8601 strings.
    ///
    /// The same rule TASK-72 established for incidents, and it bites harder here: a
    /// report's evidence window is compared against incident times and against
    /// sample timestamps, so a round trip that moved a date by up to a second would
    /// change which incident a report is said to coincide with — which is the one
    /// number this instrument exists to produce.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// Best-effort, and deliberately so: a failed write must never interrupt
    /// monitoring. Returns bytes written, or nil if nothing was written.
    @discardableResult
    private func write(_ reports: [SlowdownReport], settings: PrivacySettings,
                       now: Date) -> Int? {
        guard let url, settings.persistAcrossRestarts else { return nil }
        let document = StoredSlowdownReports(
            writtenAt: now,
            retentionDays: settings.retention.days,
            limit: limit,
            reports: reports)
        guard let data = try? Self.encoder.encode(document) else { return nil }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return data.count
    }
}
