import Darwin
import Foundation

/// An observable change in the process table (FR-045).
///
/// Deliberately limited to what we can actually see. A process that freezes
/// without exiting produces no event here, and TASK-27 established there is no
/// public signal for one — so nothing in this file may ever imply a hang.
public enum LifecycleEvent: Sendable, Equatable {
    case launched(identity: ProcessIdentity, command: String, isApplication: Bool, at: Date)
    case exited(identity: ProcessIdentity, command: String, isApplication: Bool, at: Date)

    public var identity: ProcessIdentity {
        switch self {
        case .launched(let identity, _, _, _), .exited(let identity, _, _, _): identity
        }
    }

    public var command: String {
        switch self {
        case .launched(_, let command, _, _), .exited(_, let command, _, _): command
        }
    }

    /// Whether this process ran from inside an application bundle, recorded **at the
    /// moment we saw the event** and never re-derived (TASK-84).
    ///
    /// It has to be captured here. Identity resolution reads `proc_pidpath`, and a
    /// process that has exited has no path to read; by the time a relaunch pattern
    /// is assembled — up to fifteen minutes later — the pid is gone and the
    /// resolver's `(pid, start time)` cache entry has been pruned. So the answer is
    /// taken while the process is still in a snapshot, from the cache the sweep's
    /// own grouping pass already warmed, and carried on the event.
    ///
    /// False is the safe direction and the deliberate default of an unknown: it
    /// means the event is recorded and shown, but cannot on its own open an
    /// incident.
    public var isApplication: Bool {
        switch self {
        case .launched(_, _, let isApplication, _), .exited(_, _, let isApplication, _):
            isApplication
        }
    }

    public var at: Date {
        switch self {
        case .launched(_, _, _, let at), .exited(_, _, _, let at): at
        }
    }

    public var description: String {
        switch self {
        case .launched(let identity, let command, _, _):
            "\(command) started as PID \(identity.pid)"
        case .exited(let identity, let command, _, _):
            "\(command) exited — PID \(identity.pid) disappeared"
        }
    }
}

/// The words for a repeated-quit episode, in one place (TASK-84).
///
/// **"Unexpected" is gone, and must not come back.** An exit is a process that was
/// in one snapshot and not in the next. There is no exit status, no signal, and no
/// readable crash report under the sandbox, so a clean quit and a crash are
/// *identical to us* — "quit unexpectedly" asserted a measurement we never took,
/// which FR-002 forbids as plainly as inventing a number would. What follows says
/// only what was observed: the process quit, and it quit more than once.
///
/// One type because the rename touched five surfaces at once — the condition label,
/// the incidents row, the report headline, the summariser's headline (built from the
/// condition label) and the menu bar's spoken word — and a second copy of any of
/// them is how two screens come to describe one incident differently. Every surface
/// composes from here; nothing writes the verb itself.
///
/// **This may change again.** A spike is open on whether `kqueue`/`EVFILT_PROC` with
/// `NOTE_EXITSTATUS` can distinguish a crash from a normal exit under the sandbox.
/// If it can, then "crashed" becomes sayable for the exits that were crashes, this
/// wording is revisited, and the threshold argument in `LifecycleTracker` reopens
/// too — a *crash* loop is a much stronger signal than an exit loop and would not
/// need the application restriction below to be safe. Nothing here assumes the
/// question is closed.
public enum RepeatedQuitWording {
    /// The verb, and the only place it is written. Past tense, intransitive: this
    /// is what the process did, not what happened to it.
    static let verb = "quit"

    /// `IncidentCondition.repeatedApplicationQuits.label`. Also the summariser's
    /// headline, which reads "\(conditionLabel) for 3 minutes, 15 seconds".
    public static let conditionLabel = "Repeated quits"

    /// The menu bar's one-word form, beside "CPU", "memory", "storage", "thermal".
    /// A verb where the others are nouns, because there is no resource here to
    /// name and naming one would imply a shortage this condition exists to say we
    /// did not measure.
    public static let menuBarWord = "quits"

    /// An incidents row: "Final Cut Pro quit repeatedly".
    ///
    /// No count, because the row already carries the pattern's own summary
    /// underneath it and repeating the figure in two registers invites them to
    /// disagree.
    public static func repeatedly(subject: String) -> String {
        "\(subject) \(verb) repeatedly"
    }

    /// A report headline: "Final Cut Pro quit three times in 12 minutes".
    ///
    /// - Parameter times: already spelled out by the caller where the design spells
    ///   it out; this type does not own number formatting.
    public static func counted(subject: String, times: String, minutes: Int) -> String {
        "\(subject) \(verb) \(times) times in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

/// A process that exited and came back repeatedly (FR-046, as narrowed in v1.2).
///
/// `Codable` because an incident opened for this records the pattern it was opened
/// on and that record is written to disk (TASK-71, TASK-72). Lifecycle events
/// themselves are bounded by the tracker's window and are not persisted, so without
/// this the evidence behind a stored repeated-quit incident would be gone by the
/// time anyone opened it.
public struct RelaunchPattern: Sendable, Equatable, Identifiable, Codable {
    /// Grouping key: the command name, since a relaunched process has a new PID
    /// and therefore a new identity by construction.
    public let command: String
    public let exits: Int
    public let firstAt: Date
    public let lastAt: Date
    /// How confident we are that these are the same application relaunching
    /// rather than unrelated processes sharing a truncated name.
    public let confidence: Confidence

    public init(
        command: String, exits: Int, firstAt: Date, lastAt: Date, confidence: Confidence
    ) {
        self.command = command
        self.exits = exits
        self.firstAt = firstAt
        self.lastAt = lastAt
        self.confidence = confidence
    }

    /// How confident we are about **why** the application exited: low, always, and
    /// it cannot rise (FR-013, FR-046).
    ///
    /// `confidence` above is about the *association* — whether these exits are the
    /// same application, which stronger evidence genuinely can improve. This is a
    /// different question with a permanent answer. The thing that would raise it is
    /// the reason a process ended, and no public API reports one to a sandboxed
    /// build, so no accumulation of exits makes the cause better known. Ten exits
    /// are more certainly a pattern and no more certainly explained than three.
    ///
    /// Capped rather than fixed, so a low-confidence association cannot come out
    /// looking better than the pattern it rests on.
    public var causeConfidence: Confidence { min(.low, confidence) }

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
    ///
    /// **Re-examined against FR-006 on 2026-08-09 and deliberately unchanged — the
    /// count is the wrong dial** (TASK-82 criterion #5, follow-up in TASK-84).
    ///
    /// Measured, not reasoned: one 901 s window on a developer Mac, sampled at 2 s,
    /// grouping disappearances by basename truncated to 16 bytes as `p_comm` is.
    /// **28 commands reached three exits** — `swift-frontend` 112, `swift-plugin-ser`
    /// 63, `mdworker_shared` 61, `yes` 60, `zsh` 42, `xcodebuild` 19, and 22 more.
    /// Raising the count cannot separate those from a real failure, because normal
    /// build churn reaches 112 and a user who relaunches a broken app gives up at
    /// three or four. Requiring a matched relaunch leaves 23 of the 28, because a
    /// build spawns the same compiler over and over.
    ///
    /// TASK-71 read `minimumExits` as FR-006's sustained-not-transient guard. FR-006
    /// forbids alerting on *one event too short to matter*; what this predicate
    /// admits is *many events that were each entirely normal*. Multiplicity is not
    /// duration.
    ///
    /// The filter that works is FR-046's own noun: **application** — see
    /// `relaunchPatterns`, which now applies it. Exactly one of the 28 lived in a
    /// `.app`, and it was MacSlowdown being rebuilt.
    public var minimumExits: Int
    public var window: Duration

    /// How long a process must have been running for its exit to count as an
    /// **application session** ending, rather than a task finishing.
    ///
    /// Added 2026-08-31 after the third hole in this predicate, found in the
    /// product owner's own recorded incidents: `XProtectRemediatorAdload`,
    /// `XProtectRemediatorBundlore` and their siblings live at
    /// `XProtect.app/Contents/MacOS/`, so they are genuinely the main executables
    /// of an application bundle and pass every path test we have. macOS runs about
    /// 34 of them, briefly, as a scheduled malware scan — and `p_comm`'s 16 bytes
    /// truncate every one to the same `XProtectRemediat` fragment, so they were
    /// counted as one thing quitting 34 times when they were 34 different programs
    /// each running once.
    ///
    /// No path rule can separate those from a real application, because on disk
    /// they *are* applications. What separates them is duration: FR-046 is about an
    /// application the user was working in going away and coming back, and a
    /// program that lived for four seconds was never a session. This is FR-006's
    /// sustained-not-transient rule applied to the right axis at last — the earlier
    /// attempts (TASK-71's exit count, TASK-84's bundle test, TASK-86's
    /// main-executable test) all measured multiplicity or provenance instead.
    ///
    /// Measured from `(pid, start time)`, which every event already carries, so
    /// this costs arithmetic and no new plumbing.
    public var minimumSessionLifetime: Duration

    public init(
        minimumExits: Int = 3,
        window: Duration = .seconds(900),
        minimumSessionLifetime: Duration = .seconds(60)
    ) {
        self.minimumExits = minimumExits
        self.window = window
        self.minimumSessionLifetime = minimumSessionLifetime
    }

    /// Events between two snapshots.
    ///
    /// Identity is `(pid, start time)`, so a PID reused by a different process
    /// correctly reads as one exit and one launch rather than as continuity.
    ///
    /// - Parameter isApplication: whether a process ran from inside a `.app`.
    ///   Deliberately a required parameter with no default. It is the predicate
    ///   TASK-84 turns on, and the failure it guards against is a caller that
    ///   silently does not supply it — the same shape of gap TASK-71 found, where
    ///   the framework could open an incident and the app never handed it the
    ///   evidence. **It must be answered from an already-warm cache**: identity
    ///   resolution costs ~760 ms per full sweep and may never run on the sampling
    ///   path, and a process that has just exited cannot be resolved at all.
    public func events(
        from earlier: ProcessSnapshot,
        to later: ProcessSnapshot,
        at date: Date = Date(),
        isApplication: (ProcessIdentity) -> Bool
    ) -> [LifecycleEvent] {
        // Enumeration failure means we know nothing about what changed. Emitting
        // "everything exited" would be catastrophic nonsense (FR-002).
        guard !earlier.enumeration.didFail, !later.enumeration.didFail else { return [] }

        var events: [LifecycleEvent] = []
        for (identity, record) in later.records where earlier.records[identity] == nil {
            events.append(.launched(
                identity: identity, command: record.command,
                isApplication: isApplication(identity), at: date))
        }
        for (identity, record) in earlier.records where later.records[identity] == nil {
            events.append(.exited(
                identity: identity, command: record.command,
                isApplication: isApplication(identity), at: date))
        }
        return events.sorted { $0.at < $1.at || ($0.at == $1.at && $0.command < $1.command) }
    }

    /// Groups repeated exits of the same command into patterns.
    ///
    /// FR-046 acceptance criterion: a relaunch loop appears as related events
    /// rather than as unrelated incidents.
    ///
    /// ## The subject must be an application (TASK-84, product owner 2026-08-09)
    ///
    /// Only exits of processes running from inside a `.app` are considered. FR-046
    /// asks about a failing **application** in its statement, its objective and its
    /// outcome; this predicate previously implemented "three processes sharing a
    /// 16-byte `p_comm` disappeared inside 15 minutes", which is a different thing
    /// and is what an ordinary Mac does all day. Measured over one 901 s window on
    /// a developer machine, 28 commands reached three exits and exactly one of them
    /// was in a `.app` — MacSlowdown itself, being rebuilt. With this filter the
    /// same window yields **zero** findings.
    ///
    /// **The recall cost, stated rather than hidden:** a daemon, launch agent, or
    /// command-line tool that really is failing over and over no longer opens an
    /// incident. `sshd`, a database server, a background sync helper — if one of
    /// those enters a crash loop, nothing here will alert. That is accepted because
    /// the alternative is a condition that breaches continuously on any machine
    /// that compiles, which alerts about everything and therefore about nothing.
    /// The evidence is not discarded: every exit is still recorded as a
    /// `LifecycleEvent`, still counted by the store's relaunch counters, and still
    /// shown per family in the process inspector — a user who suspects a daemon can
    /// still see its exits there. Only the *incident* is withheld.
    ///
    /// Multiplicity is not duration: FR-006 forbids alerting on one event too short
    /// to matter, and the old predicate alerted on many events that were each
    /// entirely normal. See `minimumExits` for why no value of the count fixes that.
    /// How long the exiting process had been running, or nil when the kernel gave
    /// us no start time.
    ///
    /// Nil excludes the exit rather than admitting it: an exit we cannot date is one
    /// we cannot call a session, and opening an incident on an unknown is the
    /// guess this predicate has already been wrong about three times.
    func sessionLifetime(of event: LifecycleEvent) -> Double? {
        let startTime = event.identity.startTime
        guard startTime > 0 else { return nil }
        // `kp_proc.p_starttime` is microseconds since the epoch.
        let started = Date(timeIntervalSince1970: Double(startTime) / 1_000_000)
        let lifetime = event.at.timeIntervalSince(started)
        return lifetime >= 0 ? lifetime : nil
    }

    public func relaunchPatterns(in events: [LifecycleEvent], now: Date = Date()) -> [RelaunchPattern] {
        let cutoff = now.addingTimeInterval(-window.totalSeconds)
        let exits = events.filter {
            guard case .exited = $0, $0.isApplication, $0.at >= cutoff else { return false }
            // A session, not a task. See `minimumSessionLifetime`.
            return sessionLifetime(of: $0).map {
                $0 >= minimumSessionLifetime.totalSeconds
            } ?? false
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
