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

        // MARK: Calculated

        if let attribution {
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
        if !incident.conditions.contains(.lowStorage) {
            ruledOut.append(Conclusion(
                "Not a storage problem — free space stayed above the warning level.",
                evidence: .measured))
        }
        if !incident.conditions.contains(.thermalPressure) {
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
