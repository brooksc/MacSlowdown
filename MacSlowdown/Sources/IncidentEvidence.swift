import Foundation
import Metrics

/// The presentation model behind the incident detail — "the evidence room"
/// (design 1e, FR-013, FR-038, FR-049, FR-050, FR-054).
///
/// Pure functions over their inputs, separated from the view for the same reason
/// `Presentation` is separated from `MonitorStore`: rules that live on a view are
/// unreachable from a test. Everything here is written so that a section with no
/// evidence behind it says so rather than being filled in.
///
/// The rule this file exists to enforce: **nothing is reconstructed.** Where the
/// design asks for something the app does not retain, the model reports the
/// absence as a named gap. A plausible-looking series drawn from values we never
/// recorded would be a fabricated measurement, which is the one thing the spec
/// never permits.

// MARK: - Provenance

/// When a displayed value was read, relative to the incident it describes.
///
/// This distinction is the whole difference between evidence and decoration. A
/// live power or thermal reading is a fact about *now*; presenting it under
/// "Conditions at the time" of an incident that closed an hour ago would assert
/// something we never measured.
enum EvidenceProvenance: Equatable {
    /// Captured while the incident was running, and stored with it.
    case recordedDuringIncident
    /// Read just now. Only defensible while the incident is still open.
    case observedNow
    /// Never captured, and not recoverable after the fact.
    case notRetained(reason: String)

    var isShowable: Bool {
        switch self {
        case .recordedDuringIncident, .observedNow: true
        case .notRetained: false
        }
    }

    var note: String {
        switch self {
        case .recordedDuringIncident:
            "Recorded while this incident was open."
        case .observedNow:
            "Read now, while this incident is still open."
        case .notRetained(let reason):
            reason
        }
    }
}

// MARK: - Confidence legend (FR-038 stated up front)

/// One line of the legend that opens the screen.
struct EvidenceLegendEntry: Identifiable, Equatable {
    let evidence: Evidence
    /// What, on this screen, is known that way.
    let subjects: String

    var id: String { evidence.rawValue }
    var text: String { "\(evidence.label) — \(subjects)" }
}

enum EvidenceLegend {
    /// Builds the legend from the statements actually on the screen.
    ///
    /// Derived rather than hardcoded on purpose: a legend that advertises a class
    /// the screen does not contain is itself an unsupported claim about how much
    /// we know. If the summary produced no hypothesis — which happens whenever
    /// there is no attribution to reason from — there is no "Likely" line.
    static func entries(
        for summary: IncidentSummary,
        incident: Incident,
        attribution: CPUAttribution?
    ) -> [EvidenceLegendEntry] {
        var entries: [EvidenceLegendEntry] = []

        var measured: [String] = ["how long the condition lasted"]
        if incident.conditions.contains(.cpuSaturation) || incident.peakCPUBusyFraction > 0 {
            measured.append("peak CPU")
        }
        if incident.peakMemoryPressure > .normal {
            measured.append("memory pressure level")
        }
        if attribution != nil {
            measured.append("per-process CPU we are permitted to read")
        }
        entries.append(EvidenceLegendEntry(
            evidence: .measured, subjects: measured.joined(separator: ", ")))

        let hasCalculated = (summary.conclusions + summary.ruledOut)
            .contains { $0.evidence == .calculated } || attribution != nil
        if hasCalculated {
            entries.append(EvidenceLegendEntry(
                evidence: .calculated,
                subjects: "contributor share, unattributed remainder"))
        }

        if let hypothesis = summary.hypotheses.first {
            let confidence = hypothesis.confidence?.label ?? Confidence.low.label
            entries.append(EvidenceLegendEntry(
                evidence: .heuristic,
                subjects: "which application led the load (\(confidence))"))
        }

        return entries
    }
}

// MARK: - Verdict

/// The plain-language opening: what happened, in the words a user would use.
enum IncidentVerdict {
    /// A headline that describes the experience rather than the metric name.
    ///
    /// Every phrase here restates a measurement — a pressure level, a busy
    /// fraction, a duration — so the headline makes no causal claim and needs no
    /// confidence label. Causation lives further down the screen, labelled.
    static func headline(for incident: Incident, duration: String) -> String {
        let phrases = incident.conditions
            .sorted { $0.label < $1.label }
            .map(phrase(for:))
        let joined = list(phrases)
        let tail = incident.isOpen ? "for \(duration) so far, and it is still going"
                                   : "for \(duration)"
        return joined.isEmpty
            ? "Your Mac was under sustained load \(tail)"
            : "\(joined) \(tail)"
    }

    private static func phrase(for condition: IncidentCondition) -> String {
        switch condition {
        case .memoryPressure: "Your Mac ran short of comfortable memory"
        case .cpuSaturation: "Your Mac's processors were close to fully busy"
        case .thermalPressure: "macOS reported raised thermal conditions"
        case .lowStorage: "Free space on the startup disk stayed low"
        // A statement of what the process table showed, with no claim about why.
        // "Crashed", "froze" and "stopped responding" are all unavailable to us
        // (FR-046) and none of them appears here.
        case .repeatedApplicationQuits: "An application quit and started again, repeatedly"
        }
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + ", and "
            + (items.last?.prefix(1).lowercased() ?? "") + (items.last?.dropFirst() ?? "")
        }
    }

    /// The paragraph under the headline.
    ///
    /// Deliberately built only from measured and calculated facts: the window, the
    /// peaks, the largest measurable contributor as a *figure*, and how the episode
    /// ended. It names no cause. The design's opening paragraph reads causally
    /// ("Chrome's memory had been climbing"), and the honest version of that
    /// sentence is a labelled hypothesis in "What we found", not an unlabelled
    /// sentence at the top of the screen (FR-013).
    static func paragraph(
        incident: Incident,
        attribution: CPUAttribution?,
        duration: String
    ) -> String {
        var sentences: [String] = []

        let began = Self.time(incident.beganAt)
        if let closedAt = incident.closedAt {
            sentences.append("Between \(began) and \(Self.time(closedAt)), "
                             + "\(conditionList(incident)) was sustained for \(duration).")
        } else {
            sentences.append("Since \(began), \(conditionList(incident)) has been sustained "
                             + "for \(duration).")
        }

        if incident.peakMemoryPressure > .normal {
            sentences.append("Memory pressure peaked at "
                             + "\(incident.peakMemoryPressure.label.lowercased()).")
        }
        if incident.peakCPUBusyFraction > 0 {
            let peak = Int((incident.peakCPUBusyFraction * 100).rounded())
            sentences.append("Total CPU peaked at \(peak)% of this Mac's capacity.")
        }
        if let leader = attribution?.contributors.first {
            sentences.append("\(leader.label) was the largest single user of CPU we are "
                             + "permitted to measure at "
                             + "\(Int(leader.percentOfOneCore.rounded()))% of one core.")
        }
        sentences.append(incident.isOpen
            ? "Conditions have not yet returned to normal for long enough to close it."
            : "Conditions returned to normal and the incident closed.")

        return sentences.joined(separator: " ")
    }

    static func conditionList(_ incident: Incident) -> String {
        incident.conditions.map(\.label).sorted().joined(separator: " and ").lowercased()
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Timeline

/// The incident window with its lifecycle points, plus whatever series we actually
/// retained across it.
///
/// The window, the trigger and the recovery are measured timestamps carried on the
/// `Incident` itself, so those are always drawable. The *series* are a different
/// matter: `MetricsHistory` retains aggregate CPU and the leading contributors per
/// sample and nothing else, so the design's memory-pressure and swap-written traces
/// have no stored values behind them. They are reported as gaps by name.
struct IncidentTimeline {
    struct Marker: Identifiable, Equatable {
        enum Kind: String { case began, trigger, recoveryStarted, closed }
        let kind: Kind
        let at: Date
        let label: String
        var id: String { kind.rawValue }
    }

    /// A series the design asks for that we do not hold, and why.
    struct MissingSeries: Identifiable, Equatable {
        let name: String
        let reason: String
        var id: String { name }
    }

    let start: Date
    let end: Date
    /// The shaded incident window: first breach until close, or until `end` while open.
    let windowStart: Date
    let windowEnd: Date
    let markers: [Marker]
    /// Retained samples covering the window. Empty is a normal case, not an error.
    let samples: [HistorySample]
    let missingSeries: [MissingSeries]

    /// Padding either side of the incident, so the run-up and the recovery are
    /// visible rather than the window filling the whole axis.
    static let padding: TimeInterval = 120

    static func build(
        incident: Incident,
        samples: [HistorySample] = [],
        now: Date = Date()
    ) -> IncidentTimeline {
        let windowStart = incident.beganAt
        let windowEnd = incident.closedAt ?? now
        let start = windowStart.addingTimeInterval(-padding)
        let end = max(windowEnd.addingTimeInterval(padding), start.addingTimeInterval(1))

        var markers: [Marker] = [
            Marker(kind: .began, at: incident.beganAt, label: "first breach")
        ]
        if incident.triggeredAt > incident.beganAt {
            markers.append(Marker(kind: .trigger, at: incident.triggeredAt, label: "opened"))
        }
        if let recovery = incident.recoveryStartedAt {
            markers.append(Marker(
                kind: .recoveryStarted, at: recovery, label: "conditions cleared"))
        }
        if let closed = incident.closedAt {
            markers.append(Marker(kind: .closed, at: closed, label: "closed"))
        }

        let covering = samples
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }

        return IncidentTimeline(
            start: start, end: end,
            windowStart: windowStart, windowEnd: windowEnd,
            markers: markers.sorted { $0.at < $1.at },
            samples: covering,
            missingSeries: Self.missingSeries)
    }

    /// Named gaps rather than silent omissions (FR-002).
    static let missingSeries: [MissingSeries] = [
        MissingSeries(
            name: "Memory pressure over time",
            reason: "Only the peak level reached is retained with the incident, not a "
                + "reading per sample."),
        MissingSeries(
            name: "Swap written over time",
            reason: "Paging is measured as a live rate and is not retained per sample."),
        MissingSeries(
            name: "Memory by application over time",
            reason: "Resident memory is retained only for the leading contributors of each "
                + "sample, so a continuous per-application series would have gaps we would "
                + "have to invent values to fill."),
    ]

    /// Where a moment sits across the axis, 0...1. Clamped, so a marker outside the
    /// drawn range lands on the edge rather than off it.
    func fraction(of date: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }

    var hasSeries: Bool { !samples.isEmpty }

    /// The one series we do retain: total busy CPU, as a percentage of one core.
    var peakTotalPercentOfOneCore: Double {
        samples.map(\.totalBusyPercentOfOneCore).max() ?? 0
    }

    var caption: String {
        let from = IncidentVerdict.time(start)
        let to = IncidentVerdict.time(end)
        return hasSeries
            ? "\(from) – \(to) · \(samples.count) retained samples"
            : "\(from) – \(to)"
    }

    static let noSeriesNote =
        "No retained samples cover this window, so no series is drawn. The window, the "
        + "trigger and the recovery below are recorded timestamps."

    /// Accessible description of a picture, since the picture is evidence (FR-034).
    var accessibilityDescription: String {
        let points = markers.map { "\($0.label) at \(IncidentVerdict.time($0.at))" }
            .joined(separator: ", ")
        return "Timeline \(caption). Incident window from "
            + "\(IncidentVerdict.time(windowStart)) to \(IncidentVerdict.time(windowEnd)). "
            + "\(points)."
    }
}

// MARK: - Events

/// One timestamped thing that happened, including things *we* did.
///
/// Our own behaviour belongs in the same list as the machine's. A user reading the
/// evidence should be able to see that we started sampling faster at 3:14, because
/// that changes the resolution of everything after it.
struct IncidentEventEntry: Identifiable, Equatable {
    enum Origin: String { case system, ourOwnBehaviour }

    let at: Date
    let text: String
    let origin: Origin
    let evidence: Evidence

    var id: String { "\(at.timeIntervalSince1970)-\(text)" }
    var timeLabel: String { IncidentVerdict.time(at) }
}

enum IncidentEventLog {
    /// The events we can state as fact.
    ///
    /// Every entry derives from a timestamp the detector actually recorded on the
    /// incident, or from a cadence reading taken now. Nothing is inferred from
    /// policy: we know when the cadence controller *would* have raised the rate,
    /// but "would have" is not a measurement, and this list is evidence.
    static func entries(
        incident: Incident,
        policy: IncidentPolicy = .default,
        cadence: SamplingCadence? = nil,
        cadenceObservedAt: Date = Date()
    ) -> [IncidentEventEntry] {
        var entries: [IncidentEventEntry] = []

        entries.append(IncidentEventEntry(
            at: incident.beganAt,
            text: "\(IncidentVerdict.conditionList(incident).capitalizedFirst) crossed its "
                + "threshold",
            origin: .system, evidence: .measured))

        if incident.triggeredAt > incident.beganAt {
            let held = DateComponentsFormatter.incidentDuration.string(
                from: incident.triggeredAt.timeIntervalSince(incident.beganAt)) ?? "long enough"
            entries.append(IncidentEventEntry(
                at: incident.triggeredAt,
                text: "Sustained for \(held) — incident opened",
                origin: .system, evidence: .measured))
        }

        // Our own behaviour, only where we can read it rather than assume it.
        if let cadence {
            entries.append(IncidentEventEntry(
                at: cadenceObservedAt,
                text: cadence.description.capitalizedFirst,
                origin: .ourOwnBehaviour, evidence: .measured))
        }

        if let recovery = incident.recoveryStartedAt {
            let hold = Int(policy.recoveryDuration.totalSeconds)
            entries.append(IncidentEventEntry(
                at: recovery,
                text: "Conditions cleared — waiting \(hold) s to be sure",
                origin: .system, evidence: .measured))
        }

        if let closed = incident.closedAt {
            let hold = Int(policy.recoveryDuration.totalSeconds)
            entries.append(IncidentEventEntry(
                at: closed,
                text: "Normal for \(hold) s — incident closed",
                origin: .system, evidence: .measured))
        }

        return entries.sorted { $0.at < $1.at }
    }

    /// Stated on screen whenever the list carries none of our own behaviour, so the
    /// absence reads as a limitation rather than as "nothing happened".
    static let noOwnBehaviourNote =
        "Changes to our own sampling rate are not retained with a closed incident, so this "
        + "list covers the machine only."
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Conditions at the time (FR-049)

/// The machine's surroundings, with an explicit answer to "when was this read?".
struct IncidentConditions {
    struct Row: Identifiable, Equatable {
        let label: String
        let value: String
        var id: String { label }
    }

    let provenance: EvidenceProvenance
    let rows: [Row]
    /// Things the design asks for that this build cannot supply at all.
    let unavailable: [Row]
    /// FR-049's build and schema footer.
    let footer: String

    /// Builds the section.
    ///
    /// The `isOpen` split is the point of this type. While an incident is open a
    /// live reading genuinely describes it. Once it has closed, nothing here was
    /// stored with it, and showing the current battery level under "Conditions at
    /// the time" would attribute a reading to a moment we never took it.
    static func build(
        incident: Incident,
        power: PowerContext?,
        thermal: ThermalState?,
        startupVolume: VolumeCapacity?,
        machine: MachineContext,
        now: Date = Date()
    ) -> IncidentConditions {
        let footer = "App \(machine.appVersion) (\(machine.appBuild)) · "
            + "schema \(machine.schemaVersion) · \(machine.hardwareModel)"

        // Retained on the incident itself, so it is stateable either way.
        var rows: [Row] = [
            Row(label: "Peak memory pressure", value: incident.peakMemoryPressure.label)
        ]

        let unavailable: [Row] = [
            Row(label: "Profile active",
                value: "This build has no activity profiles, so none was in effect."),
        ]

        guard incident.isOpen else {
            return IncidentConditions(
                provenance: .notRetained(reason:
                    "Power, thermal and storage state were not stored with this incident, so "
                    + "we cannot say what they were when it happened. Only what the detector "
                    + "recorded is shown."),
                rows: rows,
                unavailable: unavailable,
                footer: footer)
        }

        if let power {
            rows.append(Row(label: "Power", value: power.summary))
            rows.append(Row(label: "Low Power Mode",
                            value: power.lowPowerModeEnabled ? "On" : "Off"))
        }
        if let thermal {
            rows.append(Row(label: "Thermal state", value: thermal.label))
        }
        if let volume = startupVolume {
            let available = ByteCountFormatStyle().format(Int64(volume.availableBytes))
            let total = ByteCountFormatStyle().format(Int64(volume.totalBytes))
            rows.append(Row(label: "Free storage", value: "\(available) of \(total)"))
        }
        _ = now

        return IncidentConditions(
            provenance: .observedNow, rows: rows, unavailable: unavailable, footer: footer)
    }
}

// MARK: - What happened after you acted (FR-050)

/// The before/after section, which must never become a claim of cause.
struct PostActionReport {
    let verification: ActionVerification?

    /// The sentence that keeps FR-050 true. Shown whenever a comparison is shown,
    /// never as a footnote that could be separated from it.
    static let disclaimer =
        "A change that follows an action is not proof the action produced it. We can say "
        + "what we measured before and after, and that the two line up in time."

    static let noneRecorded =
        "No action taken from this incident has been recorded, so there is nothing to "
        + "compare. This build does not keep a before-and-after with a closed incident."

    var hasComparison: Bool { verification?.before != nil && verification?.after != nil }

    var text: String { verification?.summary ?? Self.noneRecorded }

    var outcomeLabel: String? { verification?.outcome.label }

    /// The before/after pair, formatted as busy percentages of the machine.
    var beforeAfter: (before: String, after: String)? {
        guard let before = verification?.before, let after = verification?.after else {
            return nil
        }
        return ("\(Int((before * 100).rounded()))%", "\(Int((after * 100).rounded()))%")
    }
}
