import Foundation
import Metrics

/// The incident we cannot attribute (design 1h, FR-013, FR-038, FR-055).
///
/// This is the hard case and the common one: CLAUDE.md records that roughly 40
/// percentage points of busy CPU cannot be attributed to any process a Mac App
/// Store build is permitted to measure. The failure mode this file exists to
/// prevent is a contributor list that quietly stops short of the total, leaving a
/// user to conclude either that their apps were responsible or that we cannot
/// count.
///
/// Three rules run through everything below.
///
/// 1. **The remainder is a measurement, not a gap.** `unattributed = total −
///    attributed`, both sides measured, so the remainder is arithmetic on two
///    readings rather than an estimate or a rounding error. It is presented as the
///    largest slice when it is the largest slice.
/// 2. **Names and times are available for the processes we cannot measure.**
///    `sysctl KERN_PROC_ALL` returns command, uid, parent and start time for every
///    process. Only CPU and memory are denied. So "what was running" is a measured
///    fact even where "how much did it use" has no answer at all.
/// 3. **Timing is not attribution.** A process that started before the load rose
///    and ran through it is a candidate and nothing more. Every suggestion this
///    file produces carries that sentence with it, inseparably.

// MARK: - Where the CPU went

/// The split of busy CPU, guaranteed to account for all of it (FR-055).
struct CPUSplit: Equatable {
    /// Whether the slices came from one coherent reading or from separate maxima.
    ///
    /// This distinction decides what may be drawn as a share of the whole.
    /// `IncidentAttribution` deliberately keeps two different aggregations: the
    /// three totals come from the single busiest sample and therefore sum, while
    /// each application's figure is its own maximum across the incident. Stacking
    /// maxima inside a total from one instant would produce a chart whose parts
    /// can exceed its whole, so in that case the applications are listed beside
    /// the split rather than inside it.
    enum Coherence: Equatable {
        /// One sampling interval: every figure describes the same moment.
        case singleInterval
        /// Per-application maxima across the incident, alongside totals from the
        /// busiest sample.
        case peaksAcrossIncident

        var note: String {
            switch self {
            case .singleInterval:
                "All figures come from the same sampling interval, so they add up."
            case .peaksAcrossIncident:
                "The two shares below come from the busiest sampling interval and add "
                + "up to all the busy CPU in it. Each application underneath is its own "
                + "highest reading during the incident, so those figures are separate "
                + "maxima and are not parts of one total."
            }
        }
    }

    struct Slice: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case unattributed
            case application
            /// Measured processes below the retained contributor limit.
            case otherMeasured
        }

        let name: String
        let percentOfOneCore: Double
        let kind: Kind
        let evidence: Evidence

        var id: String { "\(kind.rawValue)-\(name)" }
    }

    /// Largest first, and always summing to `totalPercentOfOneCore`.
    let slices: [Slice]
    let totalPercentOfOneCore: Double
    let logicalCoreCount: Int
    let coherence: Coherence
    /// Per-application maxima, shown separately when they cannot be stacked.
    let applicationPeaks: [IncidentContributor]

    static let unattributedName = "Unattributed system activity"

    /// Share of all busy CPU, 0...1.
    func share(of slice: Slice) -> Double {
        guard totalPercentOfOneCore > 0 else { return 0 }
        return min(1, max(0, slice.percentOfOneCore / totalPercentOfOneCore))
    }

    var unattributedSlice: Slice? { slices.first { $0.kind == .unattributed } }

    var unattributedShare: Double {
        unattributedSlice.map(share(of:)) ?? 0
    }

    /// The property the whole section exists to hold: the parts account for the
    /// whole. Checked in tests rather than asserted in prose.
    var accountsForTotal: Bool {
        abs(slices.reduce(0) { $0 + $1.percentOfOneCore } - totalPercentOfOneCore) < 0.5
    }

    /// Builds from a coherent single-interval reading — an open incident's live
    /// attribution, where the contributors and the totals describe one moment.
    static func build(from attribution: CPUAttribution, limit: Int = 4) -> CPUSplit {
        let named = attribution.contributors.prefix(limit)
        var slices: [Slice] = [
            Slice(name: unattributedName,
                  percentOfOneCore: attribution.unattributedPercentOfOneCore,
                  kind: .unattributed, evidence: .calculated)
        ]
        slices += named.map {
            Slice(name: $0.label, percentOfOneCore: $0.percentOfOneCore,
                  kind: .application, evidence: .measured)
        }
        let namedSum = named.reduce(0) { $0 + $1.percentOfOneCore }
        let remainder = attribution.attributedPercentOfOneCore - namedSum
        if remainder > 0.5 {
            slices.append(Slice(name: "Everything else we could measure",
                                percentOfOneCore: remainder,
                                kind: .otherMeasured, evidence: .measured))
        }
        return CPUSplit(
            slices: slices.sorted { $0.percentOfOneCore > $1.percentOfOneCore },
            totalPercentOfOneCore: attribution.totalBusyPercentOfOneCore,
            logicalCoreCount: attribution.logicalCoreCount,
            coherence: .singleInterval,
            applicationPeaks: [])
    }

    /// Builds from what was recorded with the incident.
    ///
    /// Only the two shares are stacked, because only they came from one interval.
    /// The applications ride alongside as their own maxima — see `Coherence`.
    static func build(from recorded: IncidentAttribution) -> CPUSplit {
        let slices: [Slice] = [
            Slice(name: unattributedName,
                  percentOfOneCore: recorded.unattributedPercentOfOneCoreAtPeak,
                  kind: .unattributed, evidence: .calculated),
            Slice(name: "Everything we could measure",
                  percentOfOneCore: recorded.attributedPercentOfOneCoreAtPeak,
                  kind: .otherMeasured, evidence: .measured),
        ]
        return CPUSplit(
            slices: slices.sorted { $0.percentOfOneCore > $1.percentOfOneCore },
            totalPercentOfOneCore: recorded.peakTotalBusyPercentOfOneCore,
            logicalCoreCount: recorded.logicalCoreCount,
            coherence: .peaksAcrossIncident,
            applicationPeaks: recorded.applications)
    }
}

// MARK: - What was running

/// One system process, evidenced by name and timing and by nothing else.
struct SystemProcessWitness: Identifiable, Equatable {
    let command: String
    /// What the process is for, where the descriptor table knows. Nil is a real
    /// answer: most of the table has no published role and inventing one would be
    /// the fabricated claim FR-002 forbids.
    let role: String?
    /// Measured, from `kinfo_proc.p_starttime`. Nil when we never saw it running.
    let startedAt: Date?
    /// When we first *noticed* it gone. Bounded by the sampling interval, never
    /// the exact moment of exit — see `SystemProcessRoster.timingPrecisionNote`.
    let exitNoticedAt: Date?
    /// Present in the process table when the roster was taken.
    let isRunningNow: Bool
    /// Its start time precedes the window, so it was running when the window began.
    let coveredWindowStart: Bool

    var id: String { command }

    /// The name to lead with: the role where we have one, the command otherwise.
    var displayName: String { role ?? command }

    /// Whether we are claiming this process was absent rather than present.
    var isAbsent: Bool { !isRunningNow && startedAt == nil && exitNoticedAt == nil }

    /// Timing in words, and only timing.
    ///
    /// Every branch restates observed times. None of them says what the process
    /// was doing, because for these processes we have no measurement of that at
    /// all.
    func timing(window: DateInterval) -> String {
        let started = startedAt.map(IncidentVerdict.time)
        switch (startedAt, exitNoticedAt, isRunningNow) {
        case (let start?, let exit?, _):
            let lead = window.start.timeIntervalSince(start)
            let prefix = lead > 0
                ? "started \(Self.approximate(lead)) before the window, at \(started ?? "")"
                : "started \(started ?? "") during the window"
            return "\(prefix); last seen running at \(IncidentVerdict.time(exit))"
        case (let start?, nil, true) where coveredWindowStart:
            let lead = window.start.timeIntervalSince(start)
            return lead > 0
                ? "started \(Self.approximate(lead)) before the window, at \(started ?? ""), "
                    + "and was still running when we looked"
                : "started \(started ?? ""), and was still running when we looked"
        case (let start?, nil, true):
            _ = start
            return "started \(started ?? "") during the window, and was still running "
                + "when we looked"
        case (let start?, nil, false):
            _ = start
            return "started \(started ?? ""); we did not see it again"
        default:
            return "not running when we looked, and we saw it neither start nor stop "
                + "during the window"
        }
    }

    /// A rounded interval, because the sampling cadence does not justify seconds —
    /// and because "1500 minutes before the window" is a number, not information.
    static func approximate(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "less than a minute" }
        if minutes < 90 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 36 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        let days = Int((seconds / 86_400).rounded())
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}

enum SystemProcessRoster {
    /// The section's whole claim, stated at its head so it cannot be read off.
    static let heading = "What was running"
    static let evidenceNote = "Measured — names and timing only, never their CPU."
    static let cpuLimitation =
        "macOS does not report per-process CPU or memory for any of these, so nothing "
        + "below says how busy any of them was. We can see that they ran, and when."
    static let timingPrecisionNote =
        "Start times come from the kernel and are exact. An exit is recorded when we "
        + "first noticed the process gone, so it is accurate to one sampling interval, "
        + "not to the second."

    /// System processes whose presence — or absence — is worth stating.
    ///
    /// Scheduled or periodic work only. A process is on this list because a user
    /// can check on it somewhere else, which is what makes both answers useful:
    /// "Time Machine was running" and "Software Update was not" are each evidence.
    /// The list is short on purpose; a roster of 229 protected processes is not a
    /// finding, it is a directory.
    static let watchlist: [String] = [
        "backupd", "mds_stores", "mds", "mdworker_shared", "softwareupdated",
        "suhelperd", "installd", "photoanalysisd", "photolibraryd", "cloudd",
        "nsurlsessiond", "XProtectService", "spindump", "corespotlightd",
    ]

    /// Everything the section shows, including what it may not claim.
    struct Roster: Equatable {
        let running: [SystemProcessWitness]
        /// Watchlist processes we can state were not running. Empty is not the same
        /// as "everything was running" — see `absenceClaimable`.
        let absent: [SystemProcessWitness]
        /// Whether absence is claimable at all. It is not, unless our lifecycle
        /// observation covers the whole window: a process that started and stopped
        /// between two sweeps leaves no trace, and before monitoring began we saw
        /// nothing whatsoever.
        let absenceClaimable: Bool
        let absenceLimitation: String?
        /// How we know these processes were running *then*, given the roster of
        /// live processes is read *now*.
        let provenanceNote: String

        var isEmpty: Bool { running.isEmpty && absent.isEmpty }
    }

    /// The reasoning that lets a roster read now describe a window that has closed.
    ///
    /// It is a deduction from two measurements, not an assumption: a start time
    /// earlier than the window plus a process still present means it existed
    /// throughout. Where the start time falls inside the window, that is what is
    /// said instead. Nothing here claims what any of them was doing.
    static let closedIncidentProvenance =
        "This roster was read from the process table just now. A process whose start "
        + "time precedes the window and which is still running was necessarily running "
        + "during it — that is a deduction from two measured times, not an assumption. "
        + "A system process that ran only during the window and has since stopped "
        + "appears here only if we saw it go."

    static let openIncidentProvenance =
        "Read from the process table just now, while this incident is still open."

    /// How far before the window a start time still counts as temporally relevant.
    ///
    /// A process that has been up for eleven days was not "running during the
    /// window" in any sense that helps; it is simply always there. One that started
    /// four minutes before the load rose is the kind of coincidence worth showing.
    static let relevantLead: TimeInterval = 15 * 60
    static let maximumRunning = 12

    /// Builds the roster.
    ///
    /// - Parameters:
    ///   - window: the incident window.
    ///   - protected: processes we can name but not measure, as observed.
    ///   - lifecycle: launches and exits we saw, bounded by the tracker's window.
    ///   - lifecycleObservedFrom: the earliest moment our lifecycle record covers.
    ///     Absence is only claimable for a window inside it.
    ///   - enumerationSucceeded: a failed enumeration knows nothing about absence.
    static func build(
        window: DateInterval,
        protected: [ProtectedProcess],
        lifecycle: [LifecycleEvent],
        lifecycleObservedFrom: Date?,
        enumerationSucceeded: Bool,
        incidentIsOpen: Bool,
        watchlist: [String] = watchlist
    ) -> Roster {
        // One entry per command. p_comm is 16 bytes, so several processes can
        // share a name; the earliest start is kept, because that is the one whose
        // timing could precede the load.
        var earliestStart: [String: Date] = [:]
        for process in protected {
            let started = process.startedAt
            if let existing = earliestStart[process.command], existing <= started { continue }
            earliestStart[process.command] = started
        }

        var exits: [String: Date] = [:]
        var launches: [String: Date] = [:]
        for event in lifecycle {
            switch event {
            case .exited(_, let command, _, let at):
                exits[command] = max(exits[command] ?? at, at)
            case .launched(let identity, let command, _, _):
                // The launch time we want is the kernel's, not the sweep's.
                let started = Date(timeIntervalSince1970: Double(identity.startTime) / 1_000_000)
                launches[command] = min(launches[command] ?? started, started)
            }
        }

        let relevantFrom = window.start.addingTimeInterval(-relevantLead)
        var commands = Set(watchlist)
        for (command, started) in earliestStart where started >= relevantFrom && started <= window.end {
            commands.insert(command)
        }
        for command in exits.keys where earliestStart[command] != nil || launches[command] != nil {
            commands.insert(command)
        }

        var running: [SystemProcessWitness] = []
        var absent: [SystemProcessWitness] = []

        for command in commands.sorted() {
            let started = earliestStart[command] ?? launches[command]
            let exit = exits[command]
            let isRunning = earliestStart[command] != nil
            let witness = SystemProcessWitness(
                command: command,
                role: SystemProcessDescriptors.meaning(forCommand: command),
                startedAt: started,
                // An exit only belongs on a witness that is not running now: a
                // command that exited and came back is running, and reporting the
                // old exit beside the new start would read as a contradiction.
                exitNoticedAt: isRunning ? nil : exit,
                isRunningNow: isRunning,
                coveredWindowStart: (started.map { $0 <= window.start }) ?? false)

            if witness.isAbsent {
                absent.append(witness)
            } else if started.map({ $0 <= window.end }) ?? false {
                // Started after the window ended: it was not there, so it is not
                // evidence about the window.
                running.append(witness)
            }
        }

        // Closest to the window's start first: the coincidence a reader is looking
        // for is a process that appeared just before the load did.
        running.sort {
            let left = $0.startedAt.map { abs($0.timeIntervalSince(window.start)) } ?? .infinity
            let right = $1.startedAt.map { abs($0.timeIntervalSince(window.start)) } ?? .infinity
            return left == right ? $0.command < $1.command : left < right
        }

        let covers = (lifecycleObservedFrom.map { $0 <= window.start } ?? false)
            && enumerationSucceeded
        return Roster(
            running: Array(running.prefix(maximumRunning)),
            absent: covers ? absent : [],
            absenceClaimable: covers,
            absenceLimitation: covers ? nil : absenceLimitation(
                enumerationSucceeded: enumerationSucceeded,
                observedFrom: lifecycleObservedFrom, window: window),
            provenanceNote: incidentIsOpen
                ? openIncidentProvenance
                : closedIncidentProvenance)
    }

    private static func absenceLimitation(
        enumerationSucceeded: Bool, observedFrom: Date?, window: DateInterval
    ) -> String {
        if !enumerationSucceeded {
            return "The process table could not be read, so we cannot say which system "
                + "processes were absent."
        }
        guard let observedFrom else {
            return "We had not started watching launches and exits when this window began, "
                + "so we cannot say which system processes were absent during it."
        }
        _ = window
        return "Our record of launches and exits only reaches back to "
            + "\(IncidentVerdict.time(observedFrom)), which is after this window began. "
            + "A process could have run and stopped without us seeing it, so we are not "
            + "listing anything as absent."
    }
}

// MARK: - The shape of the load

/// What the retained CPU series looked like across the window.
///
/// A description, never an identification. A flat plateau is what constant
/// background work looks like — and also what a constant foreground workload looks
/// like. It narrows nothing on its own, which is why it is offered only as
/// supporting evidence beside a timing coincidence, and why its conclusion is
/// `.calculated` rather than `.heuristic`: it states arithmetic over samples and
/// draws no inference.
struct LoadShape: Equatable {
    /// Samples needed before the shape means anything.
    static let minimumSamples = 6

    let sampleCount: Int
    let meanPercentOfOneCore: Double
    let peakPercentOfOneCore: Double
    /// Peak minus trough across the window, as a share of the mean.
    let variation: Double
    let riseSeconds: TimeInterval?
    let fallSeconds: TimeInterval?

    /// A plateau: the load held within a fifth of its own average.
    var isSteady: Bool { variation <= 0.2 }

    static func build(samples: [HistorySample], window: DateInterval) -> LoadShape? {
        let inside = samples
            .filter { window.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
        guard inside.count >= minimumSamples else { return nil }

        let values = inside.map(\.totalBusyPercentOfOneCore)
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0, let peak = values.max(), let trough = values.min() else { return nil }

        // How long it took to reach four fifths of the peak, and how long after the
        // last such reading the window ended.
        let threshold = peak * 0.8
        let rise = inside.first { $0.totalBusyPercentOfOneCore >= threshold }
            .map { $0.timestamp.timeIntervalSince(window.start) }
        let fall = inside.last { $0.totalBusyPercentOfOneCore >= threshold }
            .map { window.end.timeIntervalSince($0.timestamp) }

        return LoadShape(
            sampleCount: inside.count,
            meanPercentOfOneCore: mean,
            peakPercentOfOneCore: peak,
            variation: (peak - trough) / mean,
            riseSeconds: rise,
            fallSeconds: fall)
    }

    var conclusion: Conclusion {
        var text = "Across \(sampleCount) retained samples, total CPU averaged "
        text += "\(Int(meanPercentOfOneCore.rounded()))% of one core and peaked at "
        text += "\(Int(peakPercentOfOneCore.rounded()))%"
        text += isSteady
            ? ", varying by less than a fifth of its own average — a steady plateau."
            : ", varying by \(Int((variation * 100).rounded()))% of its own average — "
                + "the load moved about rather than holding steady."
        text += " The shape of a load does not identify what produced it."
        return Conclusion(text, evidence: .calculated)
    }
}

// MARK: - Inference from timing

/// A candidate cause, offered as timing and labelled as timing.
struct TimingInference: Identifiable, Equatable {
    let command: String
    let displayName: String
    /// The measured and calculated facts underneath the suggestion.
    let supporting: [Conclusion]
    /// The suggestion itself. Always `.heuristic`, never above moderate.
    let conclusion: Conclusion

    var id: String { command }

    /// The sentence that keeps this honest, shown with the suggestion and never
    /// separable from it.
    static let disclaimer =
        "We can see that it was running; we cannot measure how much CPU it used, so "
        + "this is an inference from timing, not an attribution."

    static let noneFound =
        "No system process started close enough to the rise for its timing to suggest "
        + "anything. We are not going to name one on the strength of it merely having "
        + "been running — most of these run all the time."
}

enum TimingInferenceBuilder {
    /// A start this long before the window still counts as "just before".
    static let maximumLead: TimeInterval = 5 * 60
    static let maximumCandidates = 3

    /// Candidates whose *timing* coincides with the window.
    ///
    /// The qualifying shape is narrow on purpose: started within five minutes
    /// before the window (or inside it), and still running at the end or seen to
    /// stop around it. Confidence never exceeds moderate, and falls to low the
    /// moment more than one process qualifies — when two coincidences fit equally
    /// well, the honest report is that we cannot choose between them.
    static func inferences(
        window: DateInterval,
        witnesses: [SystemProcessWitness],
        shape: LoadShape?
    ) -> [TimingInference] {
        let candidates = witnesses.filter { witness in
            guard let started = witness.startedAt else { return false }
            let lead = window.start.timeIntervalSince(started)
            guard lead <= maximumLead, started <= window.end else { return false }
            // Ran to the end of the window, or was last seen at or after it.
            if witness.isRunningNow { return true }
            guard let exit = witness.exitNoticedAt else { return false }
            return exit >= window.end.addingTimeInterval(-60)
        }
        guard !candidates.isEmpty else { return [] }

        let confidence: Confidence = candidates.count == 1 ? .moderate : .low
        return candidates.prefix(maximumCandidates).map { witness in
            var supporting: [Conclusion] = [
                Conclusion(
                    "\(witness.displayName) (\(witness.command)) "
                        + "\(witness.timing(window: window)).",
                    evidence: .measured)
            ]
            if let shape { supporting.append(shape.conclusion) }

            var text = "\(witness.displayName) is a candidate on timing alone. It "
            text += "\(witness.timing(window: window)), which brackets the period the load "
            text += "was raised."
            if candidates.count > 1 {
                text += " \(candidates.count) system processes fit that description equally "
                text += "well, so this does not single one out."
            }
            text += " \(TimingInference.disclaimer)"

            return TimingInference(
                command: witness.command,
                displayName: witness.displayName,
                supporting: supporting,
                conclusion: Conclusion(text, evidence: .heuristic, confidence: confidence))
        }
    }
}

// MARK: - Why we can't name it

enum UnattributedExplanation {
    static let heading = "Why we can't name it"

    /// The plain-language limit.
    ///
    /// Deliberately **not** the sandbox story. Our own measurements say the binding
    /// limit is uid: other-uid processes are denied identically whether or not we
    /// are sandboxed, and only a privileged process sees them. Blaming the sandbox
    /// would be a tidier sentence and a false one, and it would also imply that a
    /// non-App-Store build of this app could do better, which it could not.
    static let limit =
        "macOS reports per-process CPU only for processes you own. System work runs "
        + "under root or under service accounts — the window server, the Spotlight "
        + "indexer, Time Machine, audio and backup daemons — and macOS denies those "
        + "figures to any ordinary application, sandboxed or not. We measured this: "
        + "every process owned by another user is denied, and every process owned by "
        + "you is readable, with no exceptions either way."

    /// The sentence that stops the remainder being read as slack in our arithmetic.
    static func remainderIsMeasured(share: Double) -> String {
        "The \(Int((share * 100).rounded()))% above is the measured difference between "
        + "total CPU, which macOS does report, and the sum of every process we are "
        + "permitted to read. It is a real measurement of what is left over, not a "
        + "rounding error and not an estimate."
    }

    static let whatWeStillSee =
        "We can still see that those processes exist and when they start and stop, "
        + "which is where the timing above comes from."

    static let handOff =
        "Activity Monitor is part of macOS and asks with more privilege than we have, "
        + "so it can show the per-process figures we cannot. If this is happening now, "
        + "open it and sort by CPU."
}

// MARK: - Has this happened before?

/// A time-of-day pattern across unattributed incidents (FR-013).
struct UnattributedRecurrence: Equatable {
    let incidentCount: Int
    let dayWindow: Int
    /// The hour range the incidents fall in, when they cluster.
    let earliestHour: Int?
    let latestHour: Int?
    let weekdaysOnly: Bool
    /// What the user themselves called the earlier ones (FR-039). `.userProvided`.
    let previousLabels: [String]

    var hasTimeOfDayPattern: Bool { earliestHour != nil }

    /// Counting retained records is a measurement.
    var count: Conclusion {
        Conclusion(
            "\(incidentCount) slowdowns in the last \(dayWindow) days were mostly "
                + "unattributed, this one included.",
            evidence: .measured)
    }

    /// The clustering is arithmetic over their timestamps.
    var clustering: Conclusion? {
        guard let earliest = earliestHour, let latest = latestHour else { return nil }
        let range = earliest == latest
            ? "in the \(Self.hour(earliest)) hour"
            : "between \(Self.hour(earliest)) and \(Self.hour(latest + 1))"
        let days = weekdaysOnly ? ", all on weekdays" : ""
        return Conclusion("They all began \(range)\(days).", evidence: .calculated)
    }

    /// The interpretation, and only this part is an interpretation.
    var hint: Conclusion? {
        guard hasTimeOfDayPattern else { return nil }
        return Conclusion(
            "A regular time of day points to scheduled work rather than to something "
                + "you did. It does not say which scheduled work.",
            evidence: .heuristic, confidence: .moderate)
    }

    var labelRecall: Conclusion? {
        guard !previousLabels.isEmpty else { return nil }
        let list = previousLabels.map { "\"\($0)\"" }.joined(separator: ", ")
        return Conclusion(
            "You labelled earlier slowdowns in this pattern \(list).",
            evidence: .userProvided)
    }

    static func hour(_ hour: Int) -> String {
        let normalised = hour % 24
        var components = DateComponents()
        components.hour = normalised
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(normalised):00" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

enum UnattributedRecurrenceFinder {
    static let defaultDayWindow = 14
    /// Below this, a "pattern" is two coincidences.
    static let minimumOccurrences = 3
    /// Hours apart, at most, before the incidents stop being a time-of-day cluster.
    static let clusterSpanHours = 2

    static func pattern(
        in incidents: [Incident],
        including incident: Incident,
        labels: [UUID: String] = [:],
        threshold: Double = UnattributedIncidentReport.minimumUnattributedShare,
        dayWindow: Int = defaultDayWindow,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> UnattributedRecurrence? {
        let cutoff = now.addingTimeInterval(-Double(dayWindow) * 86_400)
        var matching = incidents.filter {
            $0.beganAt >= cutoff && ($0.attribution?.unattributedShare ?? 0) >= threshold
        }
        if !matching.contains(where: { $0.id == incident.id }),
           (incident.attribution?.unattributedShare ?? 0) >= threshold {
            matching.append(incident)
        }
        guard matching.count >= minimumOccurrences else { return nil }

        let hours = matching.map { calendar.component(.hour, from: $0.beganAt) }.sorted()
        let clusters = (hours.last ?? 0) - (hours.first ?? 0) <= clusterSpanHours
        let weekdays = matching.allSatisfy {
            let day = calendar.component(.weekday, from: $0.beganAt)
            return day != 1 && day != 7
        }

        let previous = matching
            .filter { $0.id != incident.id }
            .compactMap { labels[$0.id] }
            .reduce(into: [String]()) { result, label in
                if !result.contains(label) { result.append(label) }
            }

        return UnattributedRecurrence(
            incidentCount: matching.count,
            dayWindow: dayWindow,
            earliestHour: clusters ? hours.first : nil,
            latestHour: clusters ? hours.last : nil,
            weekdaysOnly: weekdays,
            previousLabels: previous)
    }
}

// MARK: - The report

/// Everything screen 1h shows, assembled from what we actually hold.
struct UnattributedIncidentReport {
    /// Above this share of busy CPU, the incident's story is the remainder rather
    /// than the contributor list, and this presentation replaces the ordinary one.
    static let minimumUnattributedShare = 0.5

    let split: CPUSplit
    let roster: SystemProcessRoster.Roster
    let shape: LoadShape?
    let inferences: [TimingInference]
    let recurrence: UnattributedRecurrence?
    let window: DateInterval
    let duration: String

    var unattributedShare: Double { split.unattributedShare }

    /// The headline the design asks for: what happened, not which metric moved.
    var headline: String {
        "Something outside your apps used the CPU for \(duration)"
    }

    /// The opening paragraph. Measured and calculated facts only; it names nothing.
    var opening: String {
        let share = Int((unattributedShare * 100).rounded())
        var text = "Total CPU was raised from \(IncidentVerdict.time(window.start)) to "
        text += "\(IncidentVerdict.time(window.end)). "
        text += "None of your open apps accounts for it — \(share)% of the load came from "
        text += "system processes whose per-process usage macOS does not report to us. "
        text += "We can tell you which system processes were running at the time, and when "
        text += "they started and stopped — but not how much CPU any of them used."
        return text
    }

    /// The tools worth offering, given what was actually running.
    var tools: [SystemTool] {
        var tools: [SystemTool] = [.activityMonitor]
        let commands = Set(roster.running.map(\.command) + roster.absent.map(\.command))
        for tool in SystemTool.byWatchedCommand where commands.contains(tool.key) {
            if !tools.contains(where: { $0.id == tool.value.id }) { tools.append(tool.value) }
        }
        return tools
    }

    /// Builds the report, or nil when this is not that kind of incident.
    ///
    /// Returning nil is the important half: an incident a user's own applications
    /// explain must not be dressed up in the language of a limit we did not hit.
    static func build(
        incident: Incident,
        liveAttribution: CPUAttribution?,
        protected: [ProtectedProcess],
        lifecycle: [LifecycleEvent],
        lifecycleObservedFrom: Date?,
        enumerationSucceeded: Bool,
        samples: [HistorySample],
        recentIncidents: [Incident],
        labels: [UUID: String] = [:],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> UnattributedIncidentReport? {
        // An incident's own recording wins over live state, exactly as the
        // measurements section does: live figures describe the machine now, and
        // for a closed incident that is a different machine.
        let split: CPUSplit
        if let recorded = incident.attribution {
            guard recorded.unattributedShare >= minimumUnattributedShare else { return nil }
            split = .build(from: recorded)
        } else if let live = liveAttribution, incident.isOpen {
            guard live.unattributedShare >= minimumUnattributedShare else { return nil }
            split = .build(from: live)
        } else {
            return nil
        }

        let window = DateInterval(
            start: incident.beganAt,
            end: max(incident.closedAt ?? now, incident.beganAt))

        let roster = SystemProcessRoster.build(
            window: window,
            protected: protected,
            lifecycle: lifecycle,
            lifecycleObservedFrom: lifecycleObservedFrom,
            enumerationSucceeded: enumerationSucceeded,
            incidentIsOpen: incident.isOpen)

        let shape = LoadShape.build(samples: samples, window: window)
        let inferences = TimingInferenceBuilder.inferences(
            window: window, witnesses: roster.running, shape: shape)

        let duration = DateComponentsFormatter.incidentDuration
            .string(from: window.duration) ?? "a period"

        return UnattributedIncidentReport(
            split: split,
            roster: roster,
            shape: shape,
            inferences: inferences,
            recurrence: UnattributedRecurrenceFinder.pattern(
                in: recentIncidents, including: incident, labels: labels,
                calendar: calendar, now: now),
            window: window,
            duration: duration)
    }
}
