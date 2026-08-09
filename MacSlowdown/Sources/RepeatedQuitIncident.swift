import Foundation
import Metrics

/// An application that quit and came back, several times (design 1o, FR-046).
///
/// This screen is the delivery of a capability we do **not** have. TASK-27
/// established that macOS reports a beachballing application exactly as it reports
/// a healthy one, so FR-046 survives only as repeated-relaunch detection — and the
/// design's answer is to say so to the user in as many words rather than leave the
/// absence to be inferred. That is why `hangLimitation` is a first-class part of
/// the report and not a caption.
///
/// The evidence here is a different kind from every other incident screen. There
/// are no curves: there are sessions, exits, and PID changes. A resource series
/// appears only in the negative, as the thing that lets a resource cause be ruled
/// out — and only when samples actually cover the window. Where they do not, the
/// verdict is that we did not observe a resource problem, which is a weaker and
/// truer statement than "there wasn't one".

// MARK: - Sessions

/// One run of an application, from launch to exit.
struct AppSession: Identifiable, Equatable {
    let pid: pid_t
    /// The kernel's start time for that PID. Measured exactly.
    ///
    /// Nil when the process was already running before we started watching: we
    /// know it ended, not when it began, and guessing would put a fabricated
    /// duration on screen.
    let startedAt: Date?
    /// When we first noticed the process gone. Bounded by the sampling interval —
    /// never the exact moment of exit.
    let endedAt: Date?

    var id: Int32 { pid }
    var isOpen: Bool { endedAt == nil }

    var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    var durationText: String? {
        guard let duration else { return nil }
        let minutes = Int((duration / 60).rounded())
        return minutes < 1
            ? "under a minute"
            : "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

/// One exit, evidenced by the PID that went and the PID that replaced it.
///
/// The PID pair is the whole evidence. It is what distinguishes "the app is still
/// running and something is wrong with it" — which we cannot see — from "this
/// process ended and a different one took its place", which we can see exactly.
struct ExitEvidence: Identifiable, Equatable {
    let noticedAt: Date
    let pid: pid_t
    let relaunchedAsPID: pid_t?
    /// From the exit we noticed to the kernel's start time for the replacement.
    let interval: TimeInterval?

    var id: Int32 { pid }

    var text: String {
        var text = "Exited · PID \(pid) disappeared"
        if let relaunchedAsPID {
            let gap = interval.map { " \(Self.seconds($0)) later" } ?? ""
            text += " · relaunched\(gap) as PID \(relaunchedAsPID)"
        } else {
            text += " · we did not see it start again"
        }
        return text
    }

    static func seconds(_ interval: TimeInterval) -> String {
        let value = max(0, Int(interval.rounded()))
        return value < 90 ? "\(value) s" : "\(Int((interval / 60).rounded())) min"
    }
}

// MARK: - Ruling a resource cause in or out

/// Whether the machine was short of anything while this was happening.
///
/// Three cases, and `.notObserved` is the one that matters. "We saw no resource
/// problem" and "there was no resource problem" are different claims, and only the
/// first is supportable when nothing was retained across the window.
enum ResourceVerdict: Equatable {
    /// Samples cover the window and show nothing near a threshold.
    case normal(peakBusyShareOfMachine: Double, peakPressure: MemoryPressureLevel?)
    /// Samples cover the window and something was under strain.
    case strained(peakBusyShareOfMachine: Double, peakPressure: MemoryPressureLevel?)
    /// Not enough retained evidence to say either way.
    case notObserved(reason: String)

    /// Above this share of the machine, CPU is not "normal" for these purposes.
    /// Deliberately below the incident threshold: ruling a cause out asks for more
    /// headroom than opening an incident asks for.
    static let busyCeiling = 0.7

    var conclusion: Conclusion {
        switch self {
        case .normal(let busy, let pressure):
            var text = "Not a resource problem. Total CPU stayed under "
            text += "\(Int((busy * 100).rounded()))% of this Mac across the window"
            if let pressure {
                text += ", and memory pressure never went past \(pressure.label.lowercased())"
            }
            text += ". Whatever ended the application, the machine was not short of "
            text += "anything we measure."
            return Conclusion(text, evidence: .calculated)

        case .strained(let busy, let pressure):
            var text = "A resource cause is not ruled out. Total CPU reached "
            text += "\(Int((busy * 100).rounded()))% of this Mac"
            if let pressure, pressure > .normal {
                text += " and memory pressure reached \(pressure.label.lowercased())"
            }
            text += " during the window. That does not make it the reason the "
            text += "application exited — we cannot see the reason at all."
            return Conclusion(text, evidence: .calculated)

        case .notObserved(let reason):
            return Conclusion(
                "We cannot rule a resource cause in or out. \(reason)", evidence: .measured)
        }
    }

    var rulesOutResources: Bool { if case .normal = self { true } else { false } }

    static func build(
        samples: [HistorySample],
        window: DateInterval,
        logicalCoreCount: Int?,
        peakPressure: MemoryPressureLevel?
    ) -> ResourceVerdict {
        let inside = samples.filter { window.contains($0.timestamp) }
        guard let cores = logicalCoreCount, cores > 0 else {
            return .notObserved(reason:
                "The number of logical cores was not recorded with this window, and a "
                + "percentage of one core means nothing without it.")
        }
        guard inside.count >= 3, let peak = inside.map(\.totalBusyPercentOfOneCore).max() else {
            return .notObserved(reason:
                "No retained samples cover this window, so we can say only that we did "
                + "not observe a resource problem — not that there was none.")
        }
        let share = peak / (Double(cores) * 100)
        let pressureFine = (peakPressure ?? .normal) <= .normal
        return share < busyCeiling && pressureFine
            ? .normal(peakBusyShareOfMachine: share, peakPressure: peakPressure)
            : .strained(peakBusyShareOfMachine: share, peakPressure: peakPressure)
    }
}

// MARK: - Memory before each exit

/// The application's resident memory just before each exit.
///
/// This exists to *refute* a hypothesis rather than to support one. "It was
/// growing until it ran out" is the first thing anyone assumes about an app that
/// quits repeatedly, and the retained contributor summaries can settle it: if the
/// third exit came at a third of the memory the first did, growth towards a limit
/// is not the story.
struct MemoryBeforeExit: Identifiable, Equatable {
    let exitNoticedAt: Date
    let residentBytes: UInt64

    var id: Double { exitNoticedAt.timeIntervalSince1970 }

    var text: String {
        ByteCountFormatStyle().format(Int64(residentBytes))
    }
}

enum MemoryTrendBeforeExits {
    /// Readings needed before a trend is a trend rather than two numbers.
    static let minimumReadings = 2

    static func readings(
        command: String, exits: [ExitEvidence], samples: [HistorySample]
    ) -> [MemoryBeforeExit] {
        exits.compactMap { exit in
            let candidate = samples
                .filter { $0.timestamp <= exit.noticedAt }
                .sorted { $0.timestamp < $1.timestamp }
                .last { sample in sample.topContributors.contains { $0.command == command } }
            guard let sample = candidate,
                  let contributor = sample.topContributors.first(where: { $0.command == command })
            else { return nil }
            return MemoryBeforeExit(
                exitNoticedAt: exit.noticedAt, residentBytes: contributor.residentBytes)
        }
    }

    /// What the readings say, as arithmetic and nothing more.
    ///
    /// Note the units: resident size, not footprint, because `proc_pid_rusage` is
    /// denied. Activity Monitor shows footprint, so these figures legitimately
    /// differ from it and the sentence says so.
    static func conclusion(_ readings: [MemoryBeforeExit]) -> Conclusion? {
        guard readings.count >= minimumReadings,
              let first = readings.first, let last = readings.last else { return nil }
        let list = readings.map(\.text).joined(separator: ", then ")
        var text = "Resident memory before each exit was \(list). "
        text += last.residentBytes <= first.residentBytes
            ? "It was lower before the last exit than before the first, so this was not "
                + "an application growing towards a limit."
            : "It was higher before the last exit than before the first. That is growth, "
                + "not a limit being hit — nothing here shows a ceiling being reached."
        text += " Resident size, not the footprint figure Activity Monitor shows."
        return Conclusion(text, evidence: .calculated)
    }
}

// MARK: - The report

struct RepeatedQuitReport {
    let command: String
    let displayName: String
    let pattern: RelaunchPattern
    /// Oldest first.
    let sessions: [AppSession]
    let exits: [ExitEvidence]
    let window: DateInterval
    let resources: ResourceVerdict
    let memoryBeforeExits: [MemoryBeforeExit]
    /// When the last relaunch happened, and whether it is still up.
    let stillRunningSince: Date?

    // MARK: Copy that must not drift

    /// FR-046's non-negotiable sentence, verbatim from the framework so the app
    /// and the framework cannot come to say different things about it.
    static let hangLimitation = RelaunchPattern.limitation

    /// What we can and can't say, as the design frames it.
    static let capability =
        "We can see that an application quit and came back, because process lifecycle is "
        + "visible to us: a PID disappears and a different one takes its place. We cannot "
        + "tell you an application froze or beachballed — macOS reports a stalled "
        + "application exactly as it reports a healthy one — so we say nothing rather "
        + "than guess."

    /// The correction to the obvious reading of "it quit on its own".
    ///
    /// The design's copy says none of the exits followed a quit request "from you
    /// or from us". Half of that is provable and half is not. MacSlowdown has no
    /// process control at all, so "not from us" is true by construction. Whether
    /// *the user* quit it is not visible to us, and claiming it would be exactly
    /// the unlabelled causal claim FR-013 forbids.
    static let quitRequestNote =
        "MacSlowdown never quits an application — it has no way to — so none of these "
        + "followed a request from us. Whether you quit it yourself is not something we "
        + "can see."

    static let timingPrecisionNote =
        "Start times come from the kernel and are exact. An exit is recorded when we "
        + "first noticed the process gone, so each one is accurate to one sampling "
        + "interval rather than to the second."

    static let sessionLegend: [(label: String, meaning: String)] = [
        ("Session that ended", "a run that finished while we were watching"),
        ("Session still open", "the run that was still going when we last looked"),
        ("Exit", "the moment we first saw the process gone"),
    ]

    // MARK: Narrative

    var headline: String {
        let minutes = max(1, Int((window.duration / 60).rounded()))
        return "\(displayName) quit unexpectedly \(Self.count(pattern.exits)) times in "
            + "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    var opening: String {
        var text = ""
        let intervals = exits.compactMap(\.interval)
        if !intervals.isEmpty {
            let average = intervals.reduce(0, +) / Double(intervals.count)
            text += "Each time it reopened by itself within about "
            text += "\(ExitEvidence.seconds(average)). "
        }
        switch resources {
        case .normal:
            text += "Nothing was wrong with CPU or memory while this happened, so on the "
            text += "evidence we have this is the application ending, not your Mac running "
            text += "short of anything."
        case .strained:
            text += "The machine was also under load during this window, so we cannot "
            text += "separate the two."
        case .notObserved:
            text += "We hold no measurements across this window, so we cannot say whether "
            text += "the machine was short of anything at the time."
        }
        return text
    }

    /// Measured, then calculated, then the single low-confidence hypothesis.
    var conclusions: [Conclusion] {
        var conclusions: [Conclusion] = []

        var measured = "\(Self.count(pattern.exits).capitalized) exits in "
        measured += "\(max(1, Int((window.duration / 60).rounded()))) minutes, "
        measured += exits.allSatisfy { $0.relaunchedAsPID != nil }
            ? "each followed by a relaunch under a new PID. "
            : "not all of which we saw relaunch. "
        measured += Self.quitRequestNote
        conclusions.append(Conclusion(measured, evidence: .measured))

        let lengths = sessions.compactMap(\.durationText)
        if !lengths.isEmpty {
            conclusions.append(Conclusion(
                "Sessions we saw from start to finish lasted \(Self.list(lengths)).",
                evidence: .calculated))
        }
        if let memory = MemoryTrendBeforeExits.conclusion(memoryBeforeExits) {
            conclusions.append(memory)
        }

        // The hypothesis. Low, always: the thing we would need to raise it — the
        // reason the process ended — is not observable at all, so no amount of
        // further evidence of the same kind could make it stronger.
        var likely = "Repeated exits in a short window usually mean the application met "
        likely += "the same problem each time — a particular file, a plug-in, an export. "
        likely += "We have no way to see why it exited, only that it did, so this cannot "
        likely += "be narrowed further from here."
        conclusions.append(Conclusion(
            likely, evidence: .heuristic,
            confidence: min(.low, pattern.confidence)))

        return conclusions
    }

    var ruledOut: [Conclusion] { [resources.conclusion] }

    /// Tools that can see what we cannot. Nothing here claims we read a report.
    var tools: [SystemTool] { [.console, .appUpdates] }

    static func count(_ value: Int) -> String {
        switch value {
        case 2: "two"
        case 3: "three"
        case 4: "four"
        case 5: "five"
        default: "\(value)"
        }
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }

    // MARK: Building

    /// Assembles the report from observed lifecycle events.
    ///
    /// Sessions are built by walking launches and exits for one command in time
    /// order. A launch's time comes from the kernel's start time for that PID, not
    /// from the sweep that noticed it, so session lengths are as exact as their
    /// endpoints allow — which is exact at the start and one interval wide at the
    /// end.
    static func build(
        pattern: RelaunchPattern,
        displayName: String? = nil,
        lifecycle: [LifecycleEvent],
        samples: [HistorySample] = [],
        logicalCoreCount: Int? = nil,
        peakPressure: MemoryPressureLevel? = nil,
        now: Date = Date()
    ) -> RepeatedQuitReport {
        let events = lifecycle
            .filter { $0.command == pattern.command }
            .sorted { $0.at < $1.at }

        var sessions: [AppSession] = []
        var exits: [ExitEvidence] = []
        var openByPID: [pid_t: Date] = [:]

        for event in events {
            switch event {
            case .launched(let identity, _, _):
                openByPID[identity.pid] = Date(
                    timeIntervalSince1970: Double(identity.startTime) / 1_000_000)
            case .exited(let identity, _, let at):
                let started = openByPID.removeValue(forKey: identity.pid)
                sessions.append(AppSession(
                    pid: identity.pid, startedAt: started, endedAt: at))
                exits.append(ExitEvidence(
                    noticedAt: at, pid: identity.pid, relaunchedAsPID: nil, interval: nil))
            }
        }
        for (pid, started) in openByPID {
            sessions.append(AppSession(pid: pid, startedAt: started, endedAt: nil))
        }
        sessions.sort {
            ($0.startedAt ?? $0.endedAt ?? .distantPast)
                < ($1.startedAt ?? $1.endedAt ?? .distantPast)
        }

        // Pair each exit with the next session to start, which is the replacement
        // it is evidence of.
        exits = exits.map { exit in
            guard let replacement = sessions.first(where: {
                ($0.startedAt ?? .distantPast) >= exit.noticedAt
            }), let started = replacement.startedAt else { return exit }
            return ExitEvidence(
                noticedAt: exit.noticedAt, pid: exit.pid,
                relaunchedAsPID: replacement.pid,
                interval: started.timeIntervalSince(exit.noticedAt))
        }
        exits.sort { $0.noticedAt < $1.noticedAt }

        let start = sessions.first?.startedAt ?? pattern.firstAt
        let end = max(exits.last?.noticedAt ?? pattern.lastAt, start)
        let window = DateInterval(start: start, end: end)

        let open = sessions.last { $0.isOpen }
        return RepeatedQuitReport(
            command: pattern.command,
            displayName: displayName ?? pattern.command,
            pattern: pattern,
            sessions: sessions,
            exits: exits,
            window: window,
            resources: .build(
                samples: samples, window: window,
                logicalCoreCount: logicalCoreCount, peakPressure: peakPressure),
            memoryBeforeExits: MemoryTrendBeforeExits.readings(
                command: pattern.command, exits: exits, samples: samples),
            stillRunningSince: open?.startedAt ?? (open != nil ? now : nil))
    }
}
