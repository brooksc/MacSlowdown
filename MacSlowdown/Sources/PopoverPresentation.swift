import AppKit
import Foundation
import Metrics

/// Pure presentation for the menu bar popover (design 1a).
///
/// Separated from the view for the same reason `Presentation` is separated from
/// the store: the popover's copy is a requirement, not decoration (FR-013,
/// FR-038), and the cases that matter — nothing measured yet, a volume that did
/// not report, a family we can only partly account for — are unreachable from a
/// test while they live inside a `body`.
///
/// Nothing here samples, and nothing here invents a figure. Every value either
/// comes from a measurement passed in or is marked unavailable.
enum PopoverPresentation {

    // MARK: - Verdict

    /// The plain-language headline. A sentence, not a severity word: the popover
    /// exists to answer "is my Mac all right?", and "Normal" answers a different
    /// question.
    struct Verdict: Equatable {
        let headline: String
        let symbolName: String
    }

    static func verdict(severity: Severity, incidentOpen: Bool) -> Verdict {
        // A live incident has its own headline — `incidentHeadline`, which states
        // the condition and how long it has held. This fallback exists so the
        // healthy copy can never sit over an open incident even if a caller
        // reaches for `verdict` during one.
        // Measurements, not verdicts about the user's experience (FR-063). See
        // the longer note at `NowPresentation.verdict` for why "Your Mac is
        // heavily loaded" is a claim we are not entitled to make from a CPU
        // reading: the same reading is produced by a build somebody started
        // deliberately, and we cannot tell the two apart.
        if incidentOpen {
            return Verdict(
                headline: "A sustained condition is being recorded",
                symbolName: "exclamationmark.triangle.fill")
        }
        switch severity {
        case .normal:
            return Verdict(
                headline: "No sustained condition right now",
                symbolName: "checkmark.circle.fill")
        case .elevated:
            return Verdict(
                headline: "CPU has been high for the last half-minute",
                symbolName: "gauge.with.dots.needle.67percent")
        case .severe:
            return Verdict(
                headline: "CPU has been near capacity for the last half-minute",
                symbolName: "gauge.with.dots.needle.100percent")
        }
    }

    // MARK: - Proof that monitoring is running

    /// "No slowdowns in the last 24 hours. Watching since 8:02 AM."
    ///
    /// The second half is load-bearing. "No slowdowns" on its own is equally
    /// consistent with the app having silently stopped measuring, so the line has
    /// to state the window it is speaking about.
    ///
    /// The window is the observed one, never a claimed one: we only assert "the
    /// last 24 hours" once we have actually been watching that long. Before then
    /// the sentence names the start instead, because incidents are held in memory
    /// for this session only and a 24-hour claim would be unsupported (FR-038).
    /// - Parameter incidentDates: when each known incident began. **Dates rather
    ///   than a count**, so the window this sentence names and the window it counts
    ///   are decided in one place. They used to be decided in two: the caller passed
    ///   `recentIncidents.count`, which is everything inside the user's retention
    ///   setting — up to 90 days — and this function rendered it as "since 9:14 AM,
    ///   when monitoring started". Both windows were wrong, on the popover's
    ///   load-bearing line. It became wrong when TASK-72 made history persist across
    ///   restarts (FR-002).
    static func monitoringLine(
        isRunning: Bool,
        watchingSince: Date?,
        now: Date,
        incidentDates: [Date],
        timeText: (Date) -> String = Self.shortTime
    ) -> String {
        guard isRunning else {
            return "Monitoring is not running, so nothing is being observed."
        }
        guard let watchingSince else {
            // We know we are running but not since when, so there is no window to
            // count against. Say only what is known.
            return "Monitoring is running."
        }
        let elapsed = now.timeIntervalSince(watchingSince)
        if elapsed >= 24 * 60 * 60 {
            let cutoff = now.addingTimeInterval(-24 * 60 * 60)
            let count = incidentPhrase(incidentDates.count { $0 >= cutoff })
            return "\(count) in the last 24 hours. Watching since \(timeText(watchingSince))."
        }
        let count = incidentPhrase(incidentDates.count { $0 >= watchingSince })
        return "\(count) since \(timeText(watchingSince)), when monitoring started."
    }

    static func incidentPhrase(_ count: Int) -> String {
        switch count {
        case ..<1: "No slowdowns"
        case 1: "1 slowdown"
        default: "\(count) slowdowns"
        }
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// When monitoring began.
    ///
    /// Taken from the process launch date because `AppDelegate` starts the sampler
    /// in `applicationDidFinishLaunching`, so the two are the same instant to
    /// within the launch itself. It is a measured value rather than an assumed one.
    /// A `monitoringStartedAt` on the store would be more direct; see the task
    /// notes for TASK-65.1.
    static var launchedAt: Date? { NSRunningApplication.current.launchDate }

    // MARK: - Headline figures

    /// One cell of the four-up strip.
    ///
    /// `isAvailable == false` means the measurement could not be taken. It is
    /// rendered as such and never as a zero, because "0 B/s" says the disk was
    /// idle and that is a different claim (FR-002).
    struct MetricTile: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
        let isAvailable: Bool
        /// Longer form, used for the accessibility label and the tooltip.
        let detail: String
        /// Fill for a capacity bar, as a fraction used. Nil where a bar would be
        /// meaningless.
        let barFraction: Double?
    }

    static func tiles(
        attribution: CPUAttribution?,
        memoryPressure: MemoryPressureLevel,
        diskRates: DiskRates?,
        storage: VolumeCapacity?
    ) -> [MetricTile] {
        [
            cpuTile(attribution),
            memoryTile(memoryPressure),
            diskTile(diskRates),
            storageTile(storage),
        ]
    }

    private static func cpuTile(_ attribution: CPUAttribution?) -> MetricTile {
        guard let attribution else {
            return MetricTile(
                id: "cpu", label: "CPU", value: "—", isAvailable: false,
                detail: "Taking the first reading. A rate needs two samples.",
                barFraction: nil)
        }
        let percent = attribution.totalBusyPercentOfOneCore
        return MetricTile(
            id: "cpu", label: "CPU",
            value: CPUPresentation.percentOfOneCore(percent),
            isAvailable: true,
            detail: "\(CPUPresentation.percentOfOneCore(percent)) of one core, "
                + CPUPresentation.machineRelative(percent),
            barFraction: nil)
    }

    private static func memoryTile(_ level: MemoryPressureLevel) -> MetricTile {
        // The word, not a percentage: memory pressure is not percent of RAM used,
        // and showing a number here would invite exactly that reading (FR-007).
        MetricTile(
            id: "memory", label: "Memory pressure", value: level.label,
            isAvailable: true, detail: level.explanation, barFraction: nil)
    }

    private static func diskTile(_ rates: DiskRates?) -> MetricTile {
        guard let rates else {
            return MetricTile(
                id: "disk", label: "Disk", value: "Unavailable", isAvailable: false,
                detail: "No block storage driver reported byte counters.",
                barFraction: nil)
        }
        let total = rates.readBytesPerSecond + rates.writeBytesPerSecond
        return MetricTile(
            id: "disk", label: "Disk",
            value: "\(bytes(total))/s", isAvailable: true,
            // Read and write are kept in the detail rather than lost in the sum,
            // and per-application disk stays absent because it is blocked (FR-009).
            detail: "Whole machine: \(Presentation.diskThroughput(rates)). "
                + "Disk activity cannot be measured per application.",
            barFraction: nil)
    }

    private static func storageTile(_ volume: VolumeCapacity?) -> MetricTile {
        guard let volume else {
            return MetricTile(
                id: "storage", label: "Storage free", value: "Unavailable",
                isAvailable: false,
                detail: "The startup volume did not report its capacity.",
                barFraction: nil)
        }
        let used = 1 - volume.availableFraction
        return MetricTile(
            id: "storage", label: "Storage free",
            value: bytes(Double(volume.availableBytes)), isAvailable: true,
            // Purgeable space is deliberately not added in: it is an estimate of
            // what macOS thinks it could reclaim, not space you have (FR-041).
            detail: "\(bytes(Double(volume.availableBytes))) available of "
                + "\(bytes(Double(volume.totalBytes))) on \(volume.name).",
            barFraction: used)
    }

    private static func bytes(_ value: Double) -> String {
        ByteCountFormatStyle().format(Int64(max(0, value)))
    }

    // MARK: - Contributors

    /// A row of "Using the most CPU now".
    ///
    /// Unattributed system activity is one of these rather than a footnote: it is
    /// routinely one of the largest entries, and demoting it would let the visible
    /// rows appear to account for the machine when they do not (FR-013, FR-038).
    struct ContributorRow: Identifiable, Equatable {
        enum Kind: Equatable {
            case application
            /// Processes owned by another uid, which we are not permitted to measure.
            case unattributed
            /// Measured, but not large enough to list individually.
            case other
        }

        let id: String
        let kind: Kind
        let name: String
        /// Processes in the family. 1 for a standalone process.
        let processCount: Int
        /// Some members of this family could not be measured, so its figure is a
        /// floor rather than a total.
        let isPartial: Bool
        let percentOfOneCore: Double
        let executablePath: String?
    }

    static func contributorRows(
        families: [MonitorStore.FamilyRow],
        attributedPercentOfOneCore: Double,
        unattributedPercentOfOneCore: Double,
        limit: Int = 3
    ) -> [ContributorRow] {
        // A family with no CPU has no place under "using the most CPU now", even
        // though it earns its row in the inventory on memory alone.
        let leading = families.filter { $0.percentOfOneCore > 0 }.prefix(limit)

        var rows = leading.map { row in
            ContributorRow(
                id: row.id,
                kind: .application,
                name: row.family.displayName,
                processCount: row.processCount,
                isPartial: row.family.notMeasurableCount > 0,
                percentOfOneCore: row.percentOfOneCore,
                executablePath: row.family.members.first?.resolved.executablePath)
        }

        rows.sort { $0.percentOfOneCore > $1.percentOfOneCore }

        // Pinned below the ranked applications rather than sorted among them
        // (TASK-93). It is an aggregate, not a contributor, and "Other
        // applications" below has always been pinned for exactly that reason — the
        // two aggregates now sit together at the foot of the list instead of one
        // wandering up and down the ranking as the machine breathes.
        //
        // FR-055 permits the position and forbids the demotion: this row keeps its
        // full value, its full-width bar and its explanation, and the list still
        // visibly sums. It is drawn at full weight rather than dimmed, which is the
        // half of the requirement a stable position makes it easy to forget.
        rows.append(ContributorRow(
            id: "unattributed", kind: .unattributed,
            name: "Unattributed system activity",
            processCount: 0, isPartial: false,
            percentOfOneCore: unattributedPercentOfOneCore,
            executablePath: nil))

        // Everything measured but not shown individually. Without it the visible
        // rows would not sum to the total — the same failure the unattributed row
        // prevents, arriving by truncation instead of by permissions.
        let remainder = attributedPercentOfOneCore
            - leading.reduce(0) { $0 + $1.percentOfOneCore }
        if remainder > 0.5 {
            rows.append(ContributorRow(
                id: "other", kind: .other, name: "Other applications",
                processCount: 0, isPartial: false,
                percentOfOneCore: remainder, executablePath: nil))
        }

        return rows
    }

    /// The spoken form of a contributor row, so VoiceOver hears the qualifiers
    /// that sighted users read as "· 9 processes" and "(partial)" (FR-034).
    static func accessibilityLabel(for row: ContributorRow) -> String {
        var parts = [row.name]
        if row.processCount > 1 { parts.append("\(row.processCount) processes") }
        if row.isPartial { parts.append("partly measured") }
        parts.append("\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core")
        return parts.joined(separator: ", ")
    }

    /// Why a family's figure is marked partial.
    static let partialExplanation =
        "Some processes in this application are owned by another user account, "
        + "which App Store apps are not permitted to measure. This figure is at "
        + "least this much, and may be more."

    // MARK: - Live incident (design 1b)
    //
    // The triage moment. Everything below is the same discipline as above, under
    // more pressure: the headline is a measured condition and a measured duration,
    // the one causal sentence is a `Conclusion` so it cannot be shown without its
    // evidence class and confidence (FR-013, FR-038), and the contributor list is
    // stated as a share that adds to 100% so a user can check the arithmetic.
    //
    // **The sparkline** is total CPU over the retained window with the incident
    // start marked, drawn from `MonitorStore.retainedSamples` — the same series
    // FR-005 keeps as evidence, never one accumulated in the view. Its rules live in
    // `SparklinePresentation`: no interpolation across a gap, no padding out to the
    // nominal window, and a sentence rather than a flat line when too little has
    // been retained to mean anything.

    /// "CPU has been maxed for 6 min".
    ///
    /// Two measured facts and nothing else: which conditions the detector found
    /// breaching, and how long they have held. The duration runs from `beganAt` —
    /// when the condition first breached — not from `triggeredAt`, because a user
    /// asking "how long has this been going on" means the slowdown, not the moment
    /// our sustained-duration threshold elapsed.
    static func incidentHeadline(_ incident: Incident, now: Date) -> String {
        let subject = NowPresentation.leadingRelaunchPattern(incident)
            .map { ProcessNaming.labelled(command: $0.command) }
        let phrases = orderedConditions(incident.conditions)
            .map { conditionPhrase($0, subject: subject) }
        let joined: String
        switch phrases.count {
        case 0: joined = "A sustained condition has been recorded"
        case 1: joined = phrases[0]
        default:
            let rest = phrases.dropFirst().map(lowercasedFirst)
            joined = ([phrases[0]] + rest.dropLast()).joined(separator: ", ")
                + " and " + (rest.last ?? "")
        }
        return "\(joined) for \(elapsedPhrase(now.timeIntervalSince(incident.beganAt)))"
    }

    /// A stable, severity-led order so the headline does not reshuffle between
    /// samples as `Set` iteration order changes.
    static func orderedConditions(_ conditions: Set<IncidentCondition>) -> [IncidentCondition] {
        IncidentCondition.allCases.filter(conditions.contains)
    }

    /// - Parameter subject: the application a repeated-quit episode is about, when
    ///   the incident records one. Anonymity was never a deliberate choice here:
    ///   TASK-82 gave the Now banner a name and this map, which had no access to the
    ///   incident, kept saying "An application" beside it (TASK-87).
    static func conditionPhrase(_ condition: IncidentCondition, subject: String? = nil) -> String {
        switch condition {
        case .cpuSaturation: "CPU has been maxed"
        case .memoryPressure: "Memory has been under pressure"
        case .thermalPressure: "This Mac has been running hot"
        case .lowStorage: "Storage has been low"
        // What we saw, and only what we saw. Not "keeps crashing", not "keeps
        // freezing" — we observe a PID going and another taking its place, never
        // the reason (FR-046). Naming the application says which one that happened
        // to; it does not make the claim any stronger, which is why the confidence
        // label in `incidentHeadlineQualifier` travels with it.
        case .repeatedApplicationQuits:
            subject.map { "\($0) has been quitting and reopening" }
                ?? "An application has been quitting and reopening"
        }
    }

    /// The evidence class and confidence for a headline that names an application,
    /// and nil for one that states only what was measured.
    ///
    /// The same qualifier the Now banner shows, from the same rule, because TASK-82's
    /// finding was that two surfaces describing one incident must not disagree — and
    /// a name shown here without the label the banner carries would be the stronger
    /// claim of the two (FR-038).
    static func incidentHeadlineQualifier(_ incident: Incident) -> String? {
        NowPresentation.leadingRelaunchPattern(incident)
            .map { NowPresentation.heuristicQualifier($0.confidence) }
    }

    /// Coarse on purpose: the popover is read at a glance, and a second-resolution
    /// duration would imply a precision the sampling cadence does not have.
    static func elapsedPhrase(_ seconds: Double) -> String {
        DurationPhrase.phrase(seconds, .compact)
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    // MARK: The one causal sentence

    /// "Most of it is Xcode — 412% CPU, about 4.1 of 10 cores. While that
    /// continues, other apps are likely to feel slower."
    ///
    /// Returned as a `Conclusion`, not a `String`, so it is impossible to render
    /// without its evidence class and confidence: `Conclusion` forces a confidence
    /// onto anything marked `.heuristic`, and this is the only causal claim the
    /// popover makes (FR-013).
    ///
    /// The confidence is supplied by the caller rather than computed here, so it
    /// comes from `IncidentSummarizer` — the popover and the incident report must
    /// not be able to disagree about how sure we are.
    ///
    /// "Most of it" is claimed only when the leader really is most of it. Below
    /// half, the sentence says what is true instead: it is the largest contributor
    /// we can *measure*.
    static func cause(
        leaderName: String,
        leaderPercentOfOneCore: Double,
        totalBusyPercentOfOneCore: Double,
        unattributedShare: Double,
        confidence: Confidence,
        topology: CoreTopology = .current
    ) -> Conclusion {
        let share = totalBusyPercentOfOneCore > 0
            ? leaderPercentOfOneCore / totalBusyPercentOfOneCore
            : 0
        var text = share > 0.5
            ? "Most of it is \(leaderName)"
            : "The largest contributor we can measure is \(leaderName)"
        text += " — \(CPUPresentation.percentOfOneCore(leaderPercentOfOneCore)) CPU, "
        text += "\(CPUPresentation.machineRelative(leaderPercentOfOneCore, topology: topology)). "
        // The consequence in the user's terms. Deliberately not "until it
        // finishes": we cannot see whether the work is finite, and saying so would
        // be a prediction we have no measurement for.
        text += "While that continues, other apps are likely to feel slower."
        if unattributedShare > 0.3 {
            text += " Because a large share of activity is unattributable, it may not be "
            text += "the largest contributor overall — only the largest we can see."
        }
        return Conclusion(text, evidence: .heuristic, confidence: confidence)
    }

    // MARK: Share of the busy time

    /// One row of "Share of the busy time".
    ///
    /// `percentOfBusy` is a whole number, and the rows are guaranteed to sum to
    /// exactly 100. That is the point of the section: the design states "adds up to
    /// 100%" as a promise to the user, so the arithmetic has to survive rounding
    /// rather than nearly survive it.
    struct ShareRow: Identifiable, Equatable {
        let id: String
        let kind: ContributorRow.Kind
        let name: String
        let processCount: Int
        let isPartial: Bool
        let percentOfBusy: Int
        /// Share as a fraction, for the bar. Unrounded.
        let fractionOfBusy: Double
        let executablePath: String?
    }

    static let shareHeading = "Share of the busy time"
    static let shareHeadingQualifier = "adds up to 100%"

    static func shareRows(
        families: [MonitorStore.FamilyRow],
        attribution: CPUAttribution,
        limit: Int = 4
    ) -> [ShareRow] {
        let total = attribution.totalBusyPercentOfOneCore
        guard total > 0 else { return [] }

        let leading = Array(families.filter { $0.percentOfOneCore > 0 }.prefix(limit))

        // Everything measured but not listed individually. Unlike the healthy
        // screen's residual this has no threshold: a row omitted here would leave
        // the shares short of 100 and break the section's stated promise.
        let residual = max(0, attribution.attributedPercentOfOneCore
            - leading.reduce(0) { $0 + $1.percentOfOneCore })

        var weights = leading.map(\.percentOfOneCore)
        weights.append(attribution.unattributedPercentOfOneCore)
        weights.append(residual)

        let percents = wholePercents(weights, total: total)

        var rows = leading.enumerated().map { index, row in
            ShareRow(
                id: row.id, kind: .application, name: row.family.displayName,
                processCount: row.processCount,
                isPartial: row.family.notMeasurableCount > 0,
                percentOfBusy: percents[index],
                fractionOfBusy: row.percentOfOneCore / total,
                executablePath: row.family.members.first?.resolved.executablePath)
        }
        // A family that rounds to nothing is folded into the residual rather than
        // dropped, so the visible integers still add to 100.
        var otherPercent = percents[leading.count + 1]
        let (kept, vanished) = rows.stablePartition { $0.percentOfBusy > 0 }
        otherPercent += vanished.reduce(0) { $0 + $1.percentOfBusy }
        rows = kept.sorted { $0.percentOfBusy > $1.percentOfBusy }

        // Pinned below the ranked applications, not sorted among them (TASK-93).
        // It is an aggregate rather than a contributor, and "Other applications"
        // below has always been pinned for that reason; sorting one of the two by
        // value made it wander up and down the list as the machine breathed, which
        // is what the product owner saw.
        //
        // Always present, never a footnote. FR-055 permits the position and forbids
        // the demotion, so it keeps its full value, its full-width bar and its
        // explanation, and it is drawn at full weight rather than dimmed — the half
        // of the requirement that a stable position makes it easy to forget.
        rows.append(ShareRow(
            id: "unattributed", kind: .unattributed,
            name: "Unattributed system activity", processCount: 0, isPartial: false,
            percentOfBusy: percents[leading.count],
            fractionOfBusy: attribution.unattributedPercentOfOneCore / total,
            executablePath: nil))

        if otherPercent > 0 {
            rows.append(ShareRow(
                id: "other", kind: .other, name: "Other applications",
                processCount: 0, isPartial: false, percentOfBusy: otherPercent,
                fractionOfBusy: residual / total, executablePath: nil))
        }
        return rows
    }

    /// Rounds shares to whole numbers that sum to exactly 100 (largest remainder).
    ///
    /// Rounding each share independently is what makes contributor lists add to 99
    /// or 101, and this list is explicitly labelled as adding to 100.
    static func wholePercents(_ weights: [Double], total: Double) -> [Int] {
        guard total > 0, !weights.isEmpty else { return weights.map { _ in 0 } }
        let exact = weights.map { max(0, $0) / total * 100 }
        var whole = exact.map { Int($0.rounded(.down)) }
        let deficit = 100 - whole.reduce(0, +)

        if deficit > 0 {
            let byRemainder = exact.indices
                .sorted { (exact[$0] - Double(whole[$0])) > (exact[$1] - Double(whole[$1])) }
            for index in byRemainder.prefix(deficit) { whole[index] += 1 }
        } else if deficit < 0 {
            // The parts summed above the whole — only reachable from float noise,
            // since attributed + unattributed is total by construction.
            let byShare = whole.indices.sorted { whole[$0] > whole[$1] }
            var owed = -deficit
            for index in byShare where owed > 0 && whole[index] > 0 {
                whole[index] -= 1
                owed -= 1
            }
        }
        return whole
    }

    // MARK: The two conventions, reconciled

    /// The note the design refuses to leave out: the same application is "412%" in
    /// one place and "44%" in another, and both are correct.
    ///
    /// FR-004 requires one convention, stated wherever the numbers appear. The
    /// convention has not changed — percentages of CPU are still of one core. This
    /// section shows a *share of the incident's busy time*, which is a different
    /// quantity, and saying so is what stops it reading as a second convention.
    static func conventionReconciliation(
        leaderName: String,
        leaderPercentOfOneCore: Double,
        topology: CoreTopology = .current
    ) -> String {
        "\(leaderName) is at \(CPUPresentation.percentOfOneCore(leaderPercentOfOneCore)) CPU — "
        + "percentages there are of one core, and this Mac has \(topology.logical). "
        + "The shares above are of the busy CPU during this slowdown, which is why "
        + "they add up to 100%."
    }

    // MARK: Actions

    /// Stated on the incident screen because that is the moment a user fears the
    /// tool will act for them. Nothing in the app can quit or pause a process, and
    /// this says so where it matters (FR-037).
    static let controlAssurance =
        "MacSlowdown doesn't quit or pause apps for you — you stay in control of "
        + "anything with unsaved work."

    static func showActionTitle(for name: String) -> String { "Show \(name)" }

    /// How long a mute lasts, as the popover offers it. The full mute sheet is
    /// TASK-65.7; this is the minimum that makes the design's third action real.
    static let muteChoices: [Int] = [30, 60, 240]

    static func muteChoiceTitle(minutes: Int) -> String {
        minutes < 60 ? "For \(minutes) minutes" : "For \(minutes / 60) hour\(minutes == 60 ? "" : "s")"
    }

    /// FR-015: muting suppresses the interruption, never the monitoring. Said
    /// plainly, because a user who mutes and then finds no history would be right
    /// to feel misled.
    /// Delegated to `MuteAlerts` so the popover and the mute sheet cannot describe
    /// the same mute differently.
    ///
    /// This used to format raw minutes, which read an indefinite mute — stored as a
    /// long finite duration, because `MonitorStore.mute(forMinutes:)` is the only
    /// vocabulary there is — as "muted for another 52,560,000 min". `MuteAlerts`
    /// recognises that case and says "until you turn them back on".
    static func muteStatus(_ mute: MuteState, now: Date) -> String? {
        MuteAlerts.status(for: mute, now: now)
    }
}

private extension Array {
    /// Splits without reordering the kept elements.
    func stablePartition(_ isKept: (Element) -> Bool) -> ([Element], [Element]) {
        var kept: [Element] = []
        var dropped: [Element] = []
        for element in self {
            if isKept(element) { kept.append(element) } else { dropped.append(element) }
        }
        return (kept, dropped)
    }
}
