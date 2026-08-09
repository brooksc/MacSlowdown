import Foundation
import Synchronization

/// The on-disk form of incident history (TASK-72, FR-005, FR-012, FR-029).
///
/// Versioned deliberately. The export document already carries a schema version and
/// this follows it: a later change to what an incident records can then migrate the
/// stored form rather than fail to decode it and silently discard the user's
/// history — which is the failure mode a bare `[Incident]` on disk would have.
///
/// `retention` and `limit` are written alongside the incidents so a file can be read
/// and understood without the settings that produced it, and so a support report can
/// state what was in force when the file was written rather than what is in force
/// now.
public struct StoredIncidentHistory: Sendable, Codable, Equatable {
    /// Step this whenever the meaning of an existing field changes. Adding a field
    /// with a default does not require a step — `Incident`'s decoder tolerates a
    /// missing field wherever the property has a default.
    ///
    /// **2 (TASK-71).** `Incident.lifecycleFindings` on its own would not have
    /// needed a step; it is additive and defaults to empty, so a version-1 file
    /// still decodes and is still read here. What forced the step is
    /// `IncidentCondition.repeatedApplicationQuits`: the *meaning* of the existing
    /// `conditions` field changed, because it can now hold a value an earlier build
    /// cannot decode. Without the step, an earlier build reading a newer file would
    /// fail on the enum, call the whole file `.malformed`, and discard the user's
    /// entire history. With it, that build sees `.futureSchema`, refuses, and
    /// leaves the file intact for the build that can read it.
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let writtenAt: Date
    /// The retention period in force when this was written.
    public let retentionDays: Int
    /// The count bound in force when this was written.
    public let limit: Int
    /// Most recent first, matching the order the app holds them in.
    public let incidents: [Incident]

    public init(schemaVersion: Int = StoredIncidentHistory.currentSchemaVersion,
                writtenAt: Date = Date(), retentionDays: Int, limit: Int,
                incidents: [Incident]) {
        self.schemaVersion = schemaVersion
        self.writtenAt = writtenAt
        self.retentionDays = retentionDays
        self.limit = limit
        self.incidents = incidents
    }
}

/// Why a stored history could not be read.
///
/// Named cases rather than a bare nil so the difference between "there is nothing
/// yet" and "there is something and we could not understand it" survives to the
/// caller. Losing history must never block startup, but it must also never be
/// silent (FR-002).
public enum IncidentHistoryLoadFailure: Sendable, Equatable {
    /// No file. A first run, or history the user deleted.
    case nothingStored
    case unreadable(String)
    case malformed(String)
    /// Written by a later version of the app than this one.
    case futureSchema(version: Int)
}

/// Incident history that survives a restart, with retention enforced on every write
/// (TASK-72).
///
/// **Retention is applied here, not by a caller that remembers to ask.** Every path
/// that changes the stored set runs it through `RetentionPolicy` and the count bound
/// before anything is written, so an incident past its retention period cannot be on
/// disk after the next write — regardless of which screen, if any, the user has
/// open. `RetentionPolicy.expired` existed and nothing called it; this is the caller.
///
/// Two bounds, both real and both stated in the interface:
///   - **age**, from the user's retention setting (FR-029), and
///   - **count**, `limit`, because FR-005 requires retained evidence to be bounded
///     and a period alone bounds nothing on a machine that is in trouble all day.
///
/// Whichever bites first is what is kept, which is what the footer says.
public final class IncidentHistoryStore: Sendable {
    /// The count bound. 200 incidents of recorded attribution encode to a few
    /// hundred kilobytes, which is inside the FR-030 disk figure with room to spare,
    /// and is far more than the 30-day view can usefully draw.
    public static let defaultLimit = 200

    /// `nil` keeps history in memory only, which is what every test that is not
    /// about persistence wants.
    public let url: URL?
    public let limit: Int

    private struct State {
        var incidents: [Incident] = []
        var lastLoadFailure: IncidentHistoryLoadFailure?
    }

    private let state = Mutex(State())

    public init(url: URL?, limit: Int = IncidentHistoryStore.defaultLimit) {
        self.url = url
        self.limit = max(1, limit)
    }

    /// Most recent first.
    public var incidents: [Incident] { state.withLock { $0.incidents } }

    /// Why the last `load()` produced nothing, or nil if it produced something.
    public var lastLoadFailure: IncidentHistoryLoadFailure? {
        state.withLock { $0.lastLoadFailure }
    }

    // MARK: - Reading

    /// Reads what a previous run wrote, applying retention to what it finds.
    ///
    /// Retention is applied on the way **in** as well as on the way out: a machine
    /// that was off for two months must not show a screenful of expired incidents
    /// for the few seconds before the next write prunes them.
    ///
    /// Nothing here recomputes an incident. Attribution, confidence, severity and
    /// peaks are whatever was written; the only judgement applied is whether the
    /// record is still within retention (FR-013, FR-038).
    @discardableResult
    public func load(settings: PrivacySettings, now: Date = Date()) -> [Incident] {
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

        let stored: StoredIncidentHistory
        do {
            stored = try Self.decoder.decode(StoredIncidentHistory.self, from: data)
        } catch {
            state.withLock { $0.lastLoadFailure = .malformed(error.localizedDescription) }
            return []
        }

        guard stored.schemaVersion <= StoredIncidentHistory.currentSchemaVersion else {
            // A file from a newer build. Refuse it rather than decode half of it —
            // and leave it in place, because overwriting it would destroy history
            // the newer build can still read.
            state.withLock { $0.lastLoadFailure = .futureSchema(version: stored.schemaVersion) }
            return []
        }

        let kept = Self.bounded(stored.incidents, settings: settings, limit: limit, now: now)
        state.withLock {
            $0.incidents = kept
            $0.lastLoadFailure = nil
        }
        return kept
    }

    // MARK: - Writing

    /// Records a closed incident and writes the pruned history.
    ///
    /// Returns the retained set, so a caller updates its own state from what was
    /// actually kept rather than from what it offered.
    @discardableResult
    public func record(_ incident: Incident, settings: PrivacySettings,
                       now: Date = Date()) -> [Incident] {
        let kept = state.withLock { state -> [Incident] in
            var all = state.incidents.filter { $0.id != incident.id }
            all.insert(incident, at: 0)
            state.incidents = Self.bounded(all, settings: settings, limit: limit, now: now)
            return state.incidents
        }
        write(kept, settings: settings, now: now)
        return kept
    }

    /// Replaces the whole set — for a caller that mutated an incident already stored
    /// (linking an action or a suppression to it, FR-050, FR-016).
    @discardableResult
    public func replace(_ incidents: [Incident], settings: PrivacySettings,
                        now: Date = Date()) -> [Incident] {
        let kept = state.withLock { state -> [Incident] in
            state.incidents = Self.bounded(incidents, settings: settings, limit: limit, now: now)
            return state.incidents
        }
        write(kept, settings: settings, now: now)
        return kept
    }

    /// Applies retention without being asked to store anything.
    ///
    /// This is what makes the period real on a machine that is simply left running:
    /// nothing closes, no screen is opened, and an incident still ages out. It writes
    /// only when something actually expired, so calling it every sample costs a date
    /// comparison per retained incident and no disk traffic.
    ///
    /// Returns the incidents removed, so a caller can tell "nothing expired" from
    /// "we did not look".
    @discardableResult
    public func enforceRetention(settings: PrivacySettings, now: Date = Date()) -> [Incident] {
        let (removed, kept) = state.withLock { state -> ([Incident], [Incident]) in
            let kept = Self.bounded(state.incidents, settings: settings, limit: limit, now: now)
            guard kept.count != state.incidents.count else { return ([], kept) }
            let keptIDs = Set(kept.map(\.id))
            let removed = state.incidents.filter { !keptIDs.contains($0.id) }
            state.incidents = kept
            return (removed, kept)
        }
        guard !removed.isEmpty else { return [] }
        write(kept, settings: settings, now: now)
        return removed
    }

    /// Deletes the stored history and forgets it in memory.
    ///
    /// Returns how many incidents and how many bytes went, because "delete
    /// everything" that reports nothing is indistinguishable from a no-op — the same
    /// rule FR-050 applies to actions taken on the user's behalf.
    @discardableResult
    public func deleteAll() -> (incidents: Int, bytes: UInt64) {
        let count = state.withLock { state -> Int in
            let count = state.incidents.count
            state.incidents = []
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

    // MARK: - Bounds

    /// Age first, then count. Most recent first on the way out.
    static func bounded(_ incidents: [Incident], settings: PrivacySettings,
                        limit: Int, now: Date) -> [Incident] {
        let withinRetention = RetentionPolicy.retained(incidents, settings: settings, now: now)
        return Array(
            withinRetention
                .sorted { ($0.closedAt ?? $0.beganAt) > ($1.closedAt ?? $1.beganAt) }
                .prefix(limit))
    }

    // MARK: - Disk

    /// Dates are encoded numerically, **not** as ISO-8601 strings.
    ///
    /// `.iso8601` truncates to whole seconds, so a restored incident's times would
    /// differ from the ones recorded by up to a second — enough for `covers()` to
    /// disagree about whether an action fell inside the incident, and enough that a
    /// round trip is no longer the identity. Readability of the file is worth less
    /// than a record that comes back as what was written.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// Best-effort, and deliberately so: history is evidence, not configuration, and
    /// a failed write must never interrupt monitoring. Returns bytes written, or nil
    /// if nothing was written.
    @discardableResult
    private func write(_ incidents: [Incident], settings: PrivacySettings, now: Date) -> Int? {
        guard let url, settings.persistAcrossRestarts else { return nil }
        let document = StoredIncidentHistory(
            writtenAt: now,
            retentionDays: settings.retention.days,
            limit: limit,
            incidents: incidents)
        guard let data = try? Self.encoder.encode(document) else { return nil }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return data.count
    }
}

extension PrivacySettings.Retention {
    /// The period in whole days, for the stored form and for anything that has to
    /// state the period in words.
    public var days: Int {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        }
    }
}
