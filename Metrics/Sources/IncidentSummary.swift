import Foundation

/// One statement the app makes about an incident, with how it is known (FR-038).
///
/// The invariant this type exists to enforce: a statement carries a confidence
/// level **if and only if** it is a heuristic. A measured fact does not need one,
/// and a hypothesis must never appear without one.
public struct Conclusion: Sendable, Equatable, Codable {
    public let text: String
    public let evidence: Evidence
    public let confidence: Confidence?

    public init(_ text: String, evidence: Evidence, confidence: Confidence? = nil) {
        self.text = text
        self.evidence = evidence
        // A heuristic without a stated confidence would be an unlabelled causal
        // claim, which FR-013 forbids; default rather than allow the omission.
        self.confidence = evidence.requiresConfidence ? (confidence ?? .low) : nil
    }

    /// How this reads to a user, always leading with the evidence class.
    public var display: String {
        if let confidence {
            return "\(evidence.label), \(confidence.label). \(text)"
        }
        return "\(evidence.label). \(text)"
    }

    public var isWellFormed: Bool {
        evidence.requiresConfidence ? confidence != nil : confidence == nil
    }
}

/// An evidence-based account of an incident (FR-013, FR-038).
public struct IncidentSummary: Sendable {
    public let headline: String
    public let conclusions: [Conclusion]
    /// Things the evidence rules out. Stating these is what stops a user chasing
    /// the wrong cause.
    public let ruledOut: [Conclusion]

    public var measured: [Conclusion] { conclusions.filter { $0.evidence == .measured } }
    public var hypotheses: [Conclusion] { conclusions.filter { $0.evidence == .heuristic } }

    /// Every statement carries an evidence class, and every hypothesis carries a
    /// confidence. Checked rather than assumed.
    public var isWellFormed: Bool {
        (conclusions + ruledOut).allSatisfy(\.isWellFormed)
    }
}

public enum IncidentSummarizer {
    /// Builds a summary from measurements alone.
    ///
    /// Every causal statement is emitted as `.heuristic` with an explicit
    /// confidence, and confidence is *lowered* when a large share of the machine's
    /// activity is unattributable — because a contributor we can see may simply be
    /// the largest thing we are permitted to see, not the largest thing running.
    ///
    /// The `attribution` argument is a **live** reading. Where the incident carries
    /// its own recorded attribution that one wins, and the live one is not
    /// consulted for anything causal: for a closed incident the live reading
    /// describes a machine that has since recovered, and using it would put a
    /// currently-busy application's name on a slowdown it had nothing to do with.
    public static func summarize(
        incident: Incident,
        attribution: CPUAttribution?,
        formatter: DateComponentsFormatter = .incidentDuration
    ) -> IncidentSummary {
        var conclusions: [Conclusion] = []
        var ruledOut: [Conclusion] = []

        let duration = formatter.string(from: incident.duration.totalSeconds) ?? "a period"
        let conditions = incident.conditions
            .map(\.label)
            .sorted()
            .joined(separator: " and ")

        // MARK: Measured

        conclusions.append(Conclusion(
            "\(conditions) persisted for \(duration), from "
                + "\(Self.time(incident.beganAt)).",
            evidence: .measured))

        if incident.conditions.contains(.cpuSaturation) {
            let peak = Int((incident.peakCPUBusyFraction * 100).rounded())
            conclusions.append(Conclusion(
                "Total CPU peaked at \(peak)% of this Mac's capacity.", evidence: .measured))
        }
        if incident.peakMemoryPressure > .normal {
            conclusions.append(Conclusion(
                "Memory pressure reached \(incident.peakMemoryPressure.label.lowercased()).",
                evidence: .measured))
        }

        // The subject of a repeated-quit episode, named wherever one was recorded —
        // including on an incident that also breached a resource threshold, where
        // the two findings are about different processes and the reader needs both
        // names (TASK-82).
        if let subject = incident.lifecycleSubject {
            conclusions.append(Conclusion(
                "\(ProcessNaming.sentenceSubject(command: subject.command, capitalized: true)) "
                    + "exited \(subject.exits) times over that window, each time replaced by a "
                    + "process with a new PID.",
                evidence: .measured))
            conclusions.append(Conclusion(RelaunchPattern.limitation, evidence: .measured))
        }

        // MARK: The lifecycle account, which is a different kind of account
        //
        // A repeated-quit episode is not a resource episode narrated with different
        // numbers — it is the case where the machine was, as far as we measured,
        // fine. Everything below this branch is about what was busy, and none of it
        // bears on why an application failed (TASK-82).
        //
        // Note what is *not* emitted: no hypothesis. The one the detail screen makes
        // ("it probably met the same problem each time") is built there from the
        // pattern's own `causeConfidence` and is not copied here — a second copy is
        // how the two surfaces came to disagree in the first place. A banner that
        // states the episode and stops is the honest short form.
        //
        // The ruled-out list below is skipped for the same reason. "Not a storage
        // problem — free space stayed above the warning level" is a fair thing to
        // say about a slowdown; said about an application that kept exiting it
        // volunteers a clean bill of health for a cause nobody proposed, on evidence
        // that cannot support one.
        guard incident.narrative.narratesResourceAttribution else {
            ruledOut.append(Conclusion(
                IncidentNarrative.noResourceConditionRecorded, evidence: .measured))
            return IncidentSummary(
                headline: Self.headline(incident: incident, duration: duration),
                conclusions: conclusions,
                ruledOut: ruledOut)
        }

        // MARK: Calculated

        if let recorded = incident.attribution {
            let share = Int((recorded.unattributedShare * 100).rounded())
            if recorded.unattributedPercentOfOneCoreAtPeak > 0 {
                conclusions.append(Conclusion(
                    "\(share)% of busy CPU could not be attributed to any process we are "
                        + "permitted to measure. That is the difference between total CPU "
                        + "and everything we can read, not an estimate.",
                    evidence: .calculated))
            }

            // MARK: Heuristic — the only place causation is suggested at all.
            //
            // Carries the confidence recorded at the time, not one recomputed from
            // the machine's current state (FR-013, FR-038).
            if let conclusion = recorded.conclusion {
                conclusions.append(conclusion)
            }
        // The `isOpen` guard is what this function's own contract already promised
        // and did not enforce: "for a closed incident the live reading describes a
        // machine that has since recovered, and using it would put a currently-busy
        // application's name on a slowdown it had nothing to do with". Without it,
        // any incident that recorded no attribution of its own — an older file, or
        // one that opened before an attribution was offered — was narrated from
        // whatever happened to be busiest at the moment somebody opened the report
        // (FR-002, FR-038).
        } else if let attribution, incident.isOpen {
            let share = Int((attribution.unattributedShare * 100).rounded())
            if attribution.unattributedPercentOfOneCore > 0 {
                conclusions.append(Conclusion(
                    "\(share)% of busy CPU could not be attributed to any process we are "
                        + "permitted to measure. That is the difference between total CPU "
                        + "and everything we can read, not an estimate.",
                    evidence: .calculated))
            }

            // MARK: Heuristic — the only place causation is suggested at all.

            if let leader = attribution.contributors.first,
               attribution.attributedPercentOfOneCore > 0 {
                let leaderShare = leader.percentOfOneCore / attribution.totalBusyPercentOfOneCore
                let confidence = Self.confidence(
                    leaderShare: leaderShare, unattributedShare: attribution.unattributedShare)

                var text = "\(leader.label) was the largest measurable contributor, at "
                text += "\(Int(leader.percentOfOneCore.rounded()))% of one core."
                if attribution.unattributedShare > 0.3 {
                    text += " Because a large share of activity is unattributable, it may not "
                    text += "be the largest contributor overall — only the largest we can see."
                }
                conclusions.append(Conclusion(text, evidence: .heuristic, confidence: confidence))
            }
        }

        // MARK: Ruled out

        if !incident.conditions.contains(.memoryPressure), incident.peakMemoryPressure == .normal {
            ruledOut.append(Conclusion(
                "Not a memory problem — pressure stayed normal throughout.", evidence: .measured))
        }
        // Both of these are corroborated the way the memory clause above is, and
        // for the same reason. `conditions` holds only what *sustained* past its
        // duration threshold — 60 s for storage, 120 s for thermal — so on
        // `conditions` alone a machine that sat at serious thermal for 110 s
        // produced a report asserting, as a measured fact, that nothing thermal
        // happened. A recorded peak is a measurement; the absence of a sustained
        // condition is not (FR-002, FR-038).
        //
        // Nil means the incident predates the recording and the claim goes unsaid.
        // Silence is the honest answer to a question nobody measured.
        if !incident.conditions.contains(.lowStorage), incident.lowStorageObserved == false {
            ruledOut.append(Conclusion(
                "Not a storage problem — free space stayed above the warning level.",
                evidence: .measured))
        }
        if !incident.conditions.contains(.thermalPressure),
           let peak = incident.peakThermalState, peak < .serious {
            ruledOut.append(Conclusion(
                "Not thermal throttling — macOS did not report serious thermal conditions.",
                evidence: .measured))
        }

        return IncidentSummary(
            headline: Self.headline(incident: incident, duration: duration),
            conclusions: conclusions,
            ruledOut: ruledOut)
    }

    /// Confidence falls as the unattributable share rises, because the leader may
    /// only be the largest thing we are *allowed* to see.
    static func confidence(leaderShare: Double, unattributedShare: Double) -> Confidence {
        if unattributedShare > 0.5 { return .low }
        if leaderShare > 0.5 && unattributedShare < 0.25 { return .high }
        return .moderate
    }

    static func headline(incident: Incident, duration: String) -> String {
        let conditions = incident.conditions.map(\.label).sorted().joined(separator: " and ")
        return "\(conditions) for \(duration)"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

extension DateComponentsFormatter {
    public static let incidentDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter
    }()
}
