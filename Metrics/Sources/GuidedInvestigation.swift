import Foundation

/// The five questions FR-054 organises an investigation around.
public enum InvestigationStage: Int, Sendable, CaseIterable, Comparable {
    case whatHappened
    case whoContributed
    case wasItExpected
    case whatCanIDo
    case whatChanged

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var question: String {
        switch self {
        case .whatHappened: "What happened?"
        case .whoContributed: "What was involved?"
        case .wasItExpected: "Was this expected?"
        case .whatCanIDo: "What can I do?"
        case .whatChanged: "Did anything change?"
        }
    }
}

/// A safe, non-destructive action (FR-017).
///
/// The MAS build offers no process control at all, so every action here either
/// reveals something or hands off to another tool. `isAvailable` exists because
/// FR-017 forbids showing an unavailable action as though it worked.
public struct InvestigationAction: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let explanation: String
    public let isAvailable: Bool

    public init(id: String, title: String, explanation: String, isAvailable: Bool = true) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.isAvailable = isAvailable
    }
}

/// One step of the workflow.
///
/// Two invariants, both required by FR-054 and both tested:
///   - **Raw evidence is always reachable.** Every step carries the measurements
///     behind it, so a user can check the working rather than take our word.
///   - **No step requires agreeing with a hypothesis to continue.** Interpretation
///     is offered, never demanded — `canContinue` is unconditionally true.
public struct InvestigationStep: Sendable, Identifiable {
    public let stage: InvestigationStage
    /// Statements, each carrying its evidence class.
    public let findings: [Conclusion]
    /// Actions offered, if any.
    public let actions: [InvestigationAction]
    /// The underlying measurements, always available.
    public let rawEvidence: [AttributedFigure]

    public var id: Int { stage.rawValue }
    public var question: String { stage.question }

    /// Always true. A user must never be blocked because they decline to accept
    /// an interpretation the evidence does not compel.
    public var canContinue: Bool { true }

    public var hypotheses: [Conclusion] { findings.filter { $0.evidence == .heuristic } }
    public var hasRawEvidence: Bool { !rawEvidence.isEmpty }
}

public struct GuidedInvestigation: Sendable {
    public let incident: Incident
    public let steps: [InvestigationStep]

    public func step(_ stage: InvestigationStage) -> InvestigationStep? {
        steps.first { $0.stage == stage }
    }

    /// Every step is optional to accept and every step exposes its evidence.
    public var isWellFormed: Bool {
        steps.allSatisfy { $0.canContinue }
            && steps.allSatisfy(\.hasRawEvidence)
            && steps.allSatisfy { step in step.findings.allSatisfy(\.isWellFormed) }
    }
}

public enum InvestigationBuilder {
    public static func build(
        incident: Incident,
        summary: IncidentSummary,
        attribution: CPUAttribution?,
        relaunchPatterns: [RelaunchPattern] = [],
        expectedApplications: Set<String> = []
    ) -> GuidedInvestigation {
        // Raw evidence accompanies every step, so "show me the numbers" is never
        // more than one interaction away (FR-054).
        let evidence = attribution?.figures ?? [
            AttributedFigure(label: "Peak CPU",
                             percentOfOneCore: incident.peakCPUBusyFraction * 100,
                             evidence: .measured)
        ]

        var steps: [InvestigationStep] = []

        steps.append(InvestigationStep(
            stage: .whatHappened,
            findings: summary.conclusions.filter { $0.evidence != .heuristic } + summary.ruledOut,
            actions: [],
            rawEvidence: evidence))

        var involved = summary.hypotheses
        if let attribution, attribution.unattributedShare > 0.3 {
            involved.append(Conclusion(
                "A large share of activity could not be attributed, so this list may be "
                    + "incomplete rather than wrong.",
                evidence: .calculated))
        }
        for pattern in relaunchPatterns {
            involved.append(Conclusion(
                pattern.summary + ". " + RelaunchPattern.limitation,
                evidence: .heuristic, confidence: pattern.confidence))
        }
        steps.append(InvestigationStep(
            stage: .whoContributed, findings: involved, actions: [], rawEvidence: evidence))

        let leader = attribution?.contributors.first?.command
        var expectation: [Conclusion] = []
        if let leader, expectedApplications.contains(leader) {
            expectation.append(Conclusion(
                "You marked \(leader) as expected, so incidents it leads are recorded but "
                    + "not announced.", evidence: .userProvided))
        } else {
            expectation.append(Conclusion(
                "Nothing here has been marked expected. If this is normal for your Mac, "
                    + "you can say so and future incidents like it will be recorded "
                    + "without interrupting you.", evidence: .measured))
        }
        steps.append(InvestigationStep(
            stage: .wasItExpected, findings: expectation,
            actions: leader.map {
                [InvestigationAction(
                    id: "mark-expected",
                    title: "Treat \($0)'s load as expected",
                    explanation: "Future incidents it leads stay in your history but do not "
                        + "interrupt you. Reversible at any time.")]
            } ?? [],
            rawEvidence: evidence))

        steps.append(InvestigationStep(
            stage: .whatCanIDo,
            findings: [Conclusion(
                "MacSlowdown does not quit, pause or throttle applications. These actions "
                    + "show you what is happening so you can decide.", evidence: .measured)],
            actions: Self.actions(leader: leader),
            rawEvidence: evidence))

        steps.append(InvestigationStep(
            stage: .whatChanged,
            findings: [Conclusion(
                incident.isOpen
                    ? "This incident is still open, so there is no outcome to report yet."
                    : "Conditions returned to normal and the incident closed.",
                evidence: .measured)],
            actions: [],
            rawEvidence: evidence))

        return GuidedInvestigation(incident: incident, steps: steps)
    }

    /// Only non-destructive actions, and only ones that actually exist in a
    /// sandboxed build (FR-017, DR-06).
    static func actions(leader: String?) -> [InvestigationAction] {
        var actions: [InvestigationAction] = [
            InvestigationAction(
                id: "open-activity-monitor",
                title: "Open Activity Monitor",
                explanation: "It runs outside the App Store sandbox and can see the system "
                    + "processes we cannot."),
            InvestigationAction(
                id: "copy-diagnostics",
                title: "Copy diagnostics",
                explanation: "Copies the measurements behind this incident to the clipboard."),
        ]
        if let leader {
            actions.insert(InvestigationAction(
                id: "reveal",
                title: "Show \(leader)",
                explanation: "Brings it to the front so you can decide what to do."), at: 0)
        }
        return actions
    }
}
