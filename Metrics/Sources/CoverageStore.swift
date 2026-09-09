import Foundation
import Synchronization

/// The on-disk form of the coverage record (TASK-113).
///
/// Versioned for the same reason `StoredIncidentHistory` is: a later change to what
/// an interval records must be able to migrate the file rather than fail to decode
/// it and silently discard the record — and a *coverage* record that is silently
/// discarded is worse than most, because what it leaves behind is a screen claiming
/// we have no answer for a period we did in fact watch.
public struct StoredCoverage: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let writtenAt: Date
    /// The retention period in force when this was written, so the file can be read
    /// and understood without the settings that produced it.
    public let retentionDays: Int
    public let log: CoverageLog

    public init(schemaVersion: Int = StoredCoverage.currentSchemaVersion,
                writtenAt: Date = Date(), retentionDays: Int, log: CoverageLog) {
        self.schemaVersion = schemaVersion
        self.writtenAt = writtenAt
        self.retentionDays = retentionDays
        self.log = log
    }
}

/// Reads and writes the coverage record.
///
/// Deliberately thinner than `IncidentHistoryStore`: it holds no copy of the log.
/// The record is a single value with one writer — the sampling loop — and a second
/// authoritative copy inside a store is how two surfaces start disagreeing (FR-060).
///
/// **Writes are throttled, and the direction of the resulting error matters.** A
/// flush on every sample would put a file write on the measurement path at a 1 s
/// cadence for a record that changes by one timestamp. Instead the log is flushed
/// at most every `minimumWriteInterval`, which means a crash or a power cut loses
/// up to that much of the tail — and the lost tail reads back as a *gap*. We
/// under-claim coverage rather than over-claim it, which is the only tolerable way
/// for this particular record to be wrong.
public final class CoverageStore: Sendable {
    /// `nil` keeps the record in memory only, which is what every test that is not
    /// about persistence wants.
    public let url: URL?
    public let minimumWriteInterval: Duration

    private struct State {
        var lastWriteAt: Date?
    }

    private let state = Mutex(State())

    public init(url: URL?, minimumWriteInterval: Duration = .seconds(60)) {
        self.url = url
        self.minimumWriteInterval = minimumWriteInterval
    }

    /// What a previous run wrote, or nil if there is nothing readable.
    ///
    /// Nil is not an empty record: an empty `CoverageLog` claims a first run, and a
    /// file we could not decode claims nothing at all. The caller distinguishes them
    /// (FR-002).
    public func load() -> CoverageLog? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        guard let stored = try? Self.decoder.decode(StoredCoverage.self, from: data)
        else { return nil }
        // A file from a newer build: refuse it rather than decode half of it, and
        // leave it in place for the build that can read it.
        guard stored.schemaVersion <= StoredCoverage.currentSchemaVersion else { return nil }
        return stored.log
    }

    /// Writes if enough time has passed since the last write, or if `force`.
    ///
    /// Returns the bytes written, or nil when nothing was written — so a caller can
    /// tell "not due yet" from "written", rather than assuming the call did
    /// something because it returned (FR-050's rule, applied to our own disk).
    @discardableResult
    public func flush(_ log: CoverageLog, settings: PrivacySettings,
                      now: Date = Date(), force: Bool = false) -> Int? {
        guard let url, settings.persistAcrossRestarts else { return nil }
        let due = state.withLock { state -> Bool in
            if !force, let last = state.lastWriteAt,
               now.timeIntervalSince(last) < minimumWriteInterval.totalSeconds {
                return false
            }
            state.lastWriteAt = now
            return true
        }
        guard due else { return nil }

        let document = StoredCoverage(
            writtenAt: now, retentionDays: settings.retention.days, log: log)
        guard let data = try? Self.encoder.encode(document) else { return nil }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return data.count
    }

    /// Dates are encoded numerically for the reason recorded on
    /// `IncidentHistoryStore`: ISO-8601 truncates to whole seconds, and a coverage
    /// record that comes back a second short of what was written would report a
    /// hairline gap at every restart.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}
