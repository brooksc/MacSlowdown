import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

private func incident(open: Bool = false) -> Incident {
    Incident(id: UUID(), beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
             recoveryStartedAt: nil, closedAt: open ? nil : origin.addingTimeInterval(600),
             conditions: [.cpuSaturation], severity: .high,
             peakCPUBusyFraction: 0.94, peakMemoryPressure: .normal)
}

private func attribution(unattributed: Double = 200) -> CPUAttribution {
    CPUAttribution(
        totalBusyPercentOfOneCore: 800,
        attributedPercentOfOneCore: 800 - unattributed,
        unattributedPercentOfOneCore: unattributed,
        contributors: [ProcessCPUUsage(
            identity: ProcessIdentity(pid: 1, startTime: 1),
            command: "Xcode", percentOfOneCore: 412, residentBytes: 1 << 30)],
        protectedProcesses: [], logicalCoreCount: 8)
}

private func investigation(
    open: Bool = false,
    unattributed: Double = 200,
    expected: Set<String> = [],
    relaunches: [RelaunchPattern] = []
) -> GuidedInvestigation {
    let subject = incident(open: open)
    let attrib = attribution(unattributed: unattributed)
    return InvestigationBuilder.build(
        incident: subject,
        summary: IncidentSummarizer.summarize(incident: subject, attribution: attrib),
        attribution: attrib,
        relaunchPatterns: relaunches,
        expectedApplications: expected)
}

@Suite("Guided investigation structure")
struct InvestigationStructureTests {
    @Test("The workflow covers all five FR-054 questions in order")
    func coversAllStages() {
        let flow = investigation()
        #expect(flow.steps.map(\.stage) == InvestigationStage.allCases)
        for stage in InvestigationStage.allCases {
            #expect(flow.step(stage) != nil)
            #expect(!stage.question.isEmpty)
        }
    }

    @Test("The whole workflow is well formed")
    func wellFormed() {
        #expect(investigation().isWellFormed)
    }

    /// FR-054: raw evidence remains accessible. A user must be able to check the
    /// working at any point, not only at the end.
    @Test("Every step exposes the measurements behind it")
    func everyStepHasRawEvidence() {
        for step in investigation().steps {
            #expect(step.hasRawEvidence, "\(step.stage) hides its evidence")
            #expect(step.rawEvidence.allSatisfy { !$0.label.isEmpty })
        }
    }

    /// FR-054: no step requires accepting an unsupported conclusion.
    @Test("No step can block a user who declines a hypothesis")
    func noStepBlocks() {
        for step in investigation().steps {
            #expect(step.canContinue, "\(step.stage) requires agreement to proceed")
        }
    }

    @Test("Every hypothesis carries a confidence level")
    func hypothesesAreLabelled() {
        for step in investigation().steps {
            for hypothesis in step.hypotheses {
                #expect(hypothesis.confidence != nil,
                        "\(step.stage) states a hypothesis without confidence")
            }
        }
    }
}

@Suite("Investigation content")
struct InvestigationContentTests {
    @Test("What happened states measured facts, not interpretation")
    func whatHappenedIsFactual() throws {
        let step = try #require(investigation().step(.whatHappened))
        #expect(!step.findings.isEmpty)
        #expect(step.hypotheses.isEmpty,
                "the first step should not lead with interpretation")
    }

    @Test("A large unattributed share is flagged as incompleteness, not error")
    func unattributedFlagged() throws {
        let step = try #require(investigation(unattributed: 500).step(.whoContributed))
        let text = step.findings.map(\.text).joined(separator: " ")
        #expect(text.contains("incomplete rather than wrong"))
    }

    @Test("A small unattributed share does not add the caveat")
    func smallUnattributedIsQuiet() throws {
        let step = try #require(investigation(unattributed: 50).step(.whoContributed))
        #expect(!step.findings.map(\.text).joined().contains("incomplete rather than wrong"))
    }

    @Test("A relaunch pattern appears with its limitation attached")
    func relaunchIncludesLimitation() throws {
        let pattern = RelaunchPattern(
            command: "Final Cut Pro", exits: 3,
            firstAt: origin, lastAt: origin.addingTimeInterval(720), confidence: .moderate)
        let step = try #require(investigation(relaunches: [pattern]).step(.whoContributed))

        let text = step.findings.map(\.text).joined(separator: " ")
        #expect(text.contains("exited and restarted"))
        #expect(text.contains("cannot tell whether an app has stopped responding"),
                "the limitation must travel with the finding")
    }

    /// FR-016 and FR-038: a user's own classification is its own evidence class.
    @Test("A user's expected marking is labelled as user-provided")
    func expectedIsUserProvided() throws {
        let step = try #require(investigation(expected: ["Xcode"]).step(.wasItExpected))
        let userStatements = step.findings.filter { $0.evidence == .userProvided }
        #expect(!userStatements.isEmpty)
        #expect(userStatements.first?.text.contains("Xcode") == true)
    }

    @Test("Marking something expected is offered and described as reversible")
    func expectedActionIsReversible() throws {
        let step = try #require(investigation().step(.wasItExpected))
        let action = try #require(step.actions.first { $0.id == "mark-expected" })
        #expect(action.explanation.lowercased().contains("reversible"))
        #expect(action.explanation.lowercased().contains("history"),
                "must say the incident is still recorded")
    }
}

@Suite("Investigation actions are safe")
struct InvestigationActionTests {
    /// DR-06 and FR-017: the MAS build offers no process control at all.
    @Test("No action quits, pauses, throttles or kills anything")
    func noDestructiveActions() {
        for step in investigation().steps {
            for action in step.actions {
                let text = (action.id + " " + action.title + " " + action.explanation).lowercased()
                for forbidden in ["quit", "kill", "force", "suspend", "pause",
                                  "throttle", "renice", "limit", "terminate"] {
                    #expect(!text.contains(forbidden),
                            "action '\(action.title)' suggests process control: \(forbidden)")
                }
            }
        }
    }

    @Test("The workflow says plainly that it does not control applications")
    func statesNoControl() throws {
        let step = try #require(investigation().step(.whatCanIDo))
        let text = step.findings.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("does not quit, pause or throttle"))
    }

    @Test("Activity Monitor is offered for what we cannot see")
    func offersActivityMonitor() throws {
        let step = try #require(investigation().step(.whatCanIDo))
        let action = try #require(step.actions.first { $0.id == "open-activity-monitor" })
        #expect(action.explanation.contains("cannot"))
    }

    /// FR-017: an unavailable action is never shown as though it worked.
    @Test("Availability is explicit on every action")
    func availabilityIsExplicit() {
        for step in investigation().steps {
            for action in step.actions {
                #expect(action.isAvailable, "an unavailable action should not be offered at all")
            }
        }
    }
}

@Suite("Investigation outcome")
struct InvestigationOutcomeTests {
    @Test("An open incident reports no outcome yet rather than claiming one")
    func openIncidentHasNoOutcome() throws {
        let step = try #require(investigation(open: true).step(.whatChanged))
        let text = step.findings.map(\.text).joined().lowercased()
        #expect(text.contains("no outcome to report yet"))
    }

    @Test("A closed incident reports that conditions returned to normal")
    func closedIncidentReportsRecovery() throws {
        let step = try #require(investigation(open: false).step(.whatChanged))
        let text = step.findings.map(\.text).joined().lowercased()
        #expect(text.contains("returned to normal"))
        // FR-050: recovery is not attributed to anything the user did.
        for forbidden in ["because you", "your action fixed", "resolved by"] {
            #expect(!text.contains(forbidden))
        }
    }
}
