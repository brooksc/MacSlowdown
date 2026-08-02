import Darwin
import Foundation

/// An observable change in the process table (FR-045).
///
/// Deliberately limited to what we can actually see. A process that freezes
/// without exiting produces no event here, and TASK-27 established there is no
/// public signal for one — so nothing in this file may ever imply a hang.
public enum LifecycleEvent: Sendable, Equatable {
    case launched(identity: ProcessIdentity, command: String, at: Date)
    case exited(identity: ProcessIdentity, command: String, at: Date)

    public var identity: ProcessIdentity {
        switch self {
        case .launched(let identity, _, _), .exited(let identity, _, _): identity
        }
    }

    public var command: String {
        switch self {
        case .launched(_, let command, _), .exited(_, let command, _): command
        }
    }

    public var at: Date {
        switch self {
        case .launched(_, _, let at), .exited(_, _, let at): at
        }
    }

    public var description: String {
        switch self {
        case .launched(let identity, let command, _):
            "\(command) started as PID \(identity.pid)"
        case .exited(let identity, let command, _):
            "\(command) exited — PID \(identity.pid) disappeared"
        }
    }
}

/// A process that exited and came back repeatedly (FR-046, as narrowed in v1.2).
public struct RelaunchPattern: Sendable, Equatable, Identifiable {
    /// Grouping key: the command name, since a relaunched process has a new PID
    /// and therefore a new identity by construction.
    public let command: String
    public let exits: Int
    public let firstAt: Date
    public let lastAt: Date
    /// How confident we are that these are the same application relaunching
    /// rather than unrelated processes sharing a truncated name.
    public let confidence: Confidence

    public var id: String { command }
    public var window: Duration { .seconds(lastAt.timeIntervalSince(firstAt)) }

    /// Describes what was observed, never why. We can see that a process exited
    /// and returned; we cannot see whether it crashed, was killed, or quit
    /// cleanly, and we cannot see a hang at all.
    public var summary: String {
        let minutes = max(1, Int((window.totalSeconds / 60).rounded()))
        return "\(command) exited and restarted \(exits) times in \(minutes) "
            + "minute\(minutes == 1 ? "" : "s")"
    }

    /// The caveat that must accompany any relaunch finding.
    public static let limitation =
        "We can see that a process exited and started again, because process "
        + "lifecycle is visible to us. We cannot see why it exited, and we cannot "
        + "tell whether an app has stopped responding — macOS reports a stalled app "
        + "exactly as it reports a healthy one."
}

/// Derives lifecycle events by comparing consecutive snapshots.
public struct LifecycleTracker: Sendable {
    /// A relaunch needs at least this many exits inside the window to count as a
    /// pattern rather than an ordinary restart.
    public var minimumExits: Int
    public var window: Duration

    public init(minimumExits: Int = 3, window: Duration = .seconds(900)) {
        self.minimumExits = minimumExits
        self.window = window
    }

    /// Events between two snapshots.
    ///
    /// Identity is `(pid, start time)`, so a PID reused by a different process
    /// correctly reads as one exit and one launch rather than as continuity.
    public func events(
        from earlier: ProcessSnapshot,
        to later: ProcessSnapshot,
        at date: Date = Date()
    ) -> [LifecycleEvent] {
        // Enumeration failure means we know nothing about what changed. Emitting
        // "everything exited" would be catastrophic nonsense (FR-002).
        guard !earlier.enumeration.didFail, !later.enumeration.didFail else { return [] }

        var events: [LifecycleEvent] = []
        for (identity, record) in later.records where earlier.records[identity] == nil {
            events.append(.launched(identity: identity, command: record.command, at: date))
        }
        for (identity, record) in earlier.records where later.records[identity] == nil {
            events.append(.exited(identity: identity, command: record.command, at: date))
        }
        return events.sorted { $0.at < $1.at || ($0.at == $1.at && $0.command < $1.command) }
    }

    /// Groups repeated exits of the same command into patterns.
    ///
    /// FR-046 acceptance criterion: a relaunch loop appears as related events
    /// rather than as unrelated incidents.
    public func relaunchPatterns(in events: [LifecycleEvent], now: Date = Date()) -> [RelaunchPattern] {
        let cutoff = now.addingTimeInterval(-window.totalSeconds)
        let exits = events.filter {
            if case .exited = $0 { return $0.at >= cutoff }
            return false
        }

        return Dictionary(grouping: exits, by: \.command)
            .compactMap { command, group -> RelaunchPattern? in
                guard group.count >= minimumExits else { return nil }
                let times = group.map(\.at).sorted()
                guard let first = times.first, let last = times.last else { return nil }

                // p_comm is truncated to 16 bytes, so distinct executables can
                // share a name. A name at the truncation limit could be several
                // different processes, which is an uncertain association (FR-045).
                let confidence: Confidence = command.count >= 15 ? .low : .moderate

                return RelaunchPattern(
                    command: command, exits: group.count,
                    firstAt: first, lastAt: last, confidence: confidence)
            }
            .sorted { $0.exits > $1.exits }
    }
}
