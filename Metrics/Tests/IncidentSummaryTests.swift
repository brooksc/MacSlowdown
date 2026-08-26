import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

/// - Parameter open: whether the incident is still running. It matters for any
///   test that passes a *live* attribution: a closed incident is never narrated
///   from live state, because the live reading describes a machine that has since
///   recovered. Tests about evidence labelling therefore describe an open incident,
///   which is the case where a live reading is a measurement of the thing being
///   summarised.
private func incident(
    conditions: Set<IncidentCondition> = [.cpuSaturation],
    severity: IncidentSeverity = .high,
    peakCPU: Double = 0.94,
    peakMemory: MemoryPressureLevel = .normal,
    minutes: Double = 6,
    open: Bool = true
) -> Incident {
    Incident(
        id: UUID(), beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
        recoveryStartedAt: nil,
        closedAt: open ? nil : origin.addingTimeInterval(minutes * 60),
        conditions: conditions, severity: severity,
        peakCPUBusyFraction: peakCPU, peakMemoryPressure: peakMemory)
}

private func attribution(
    total: Double = 800, attributed: Double = 600,
    leader: (String, Double)? = ("Xcode", 412)
) -> CPUAttribution {
    let contributors = leader.map {
        [ProcessCPUUsage(identity: ProcessIdentity(pid: 1, startTime: 1),
                         command: $0.0, percentOfOneCore: $0.1, residentBytes: 1 << 30)]
    } ?? []
    return CPUAttribution(
        totalBusyPercentOfOneCore: total,
        attributedPercentOfOneCore: attributed,
        unattributedPercentOfOneCore: total - attributed,
        contributors: contributors, protectedProcesses: [], logicalCoreCount: 8)
}

@Suite("Conclusion labelling")
struct ConclusionTests {
    /// FR-013/FR-038: a confidence level appears if and only if the statement is
    /// a hypothesis.
    @Test("A heuristic always carries a confidence, even if none is supplied")
    func heuristicAlwaysHasConfidence() {
        let bare = Conclusion("Xcode is probably responsible.", evidence: .heuristic)
        #expect(bare.confidence != nil, "an unlabelled causal claim is what FR-013 forbids")
        #expect(bare.isWellFormed)
    }

    @Test("A measured fact never carries a confidence")
    func measuredHasNoConfidence() {
        let stated = Conclusion("CPU peaked at 94%.", evidence: .measured, confidence: .high)
        #expect(stated.confidence == nil, "a measurement is not more or less likely")
        #expect(stated.isWellFormed)
    }

    @Test("Display text leads with the evidence class")
    func displayLeadsWithEvidence() {
        #expect(Conclusion("x", evidence: .measured).display.hasPrefix("Measured."))
        #expect(Conclusion("x", evidence: .calculated).display.hasPrefix("Calculated."))
        #expect(Conclusion("x", evidence: .heuristic, confidence: .moderate)
            .display.hasPrefix("Likely, moderate confidence."))
        #expect(Conclusion("x", evidence: .userProvided).display.hasPrefix("You told us."))
    }

    @Test("All four FR-038 classes exist")
    func fourClasses() {
        #expect(Evidence.allCases.count == 4)
        #expect(Evidence.allCases.contains(.measured))
        #expect(Evidence.allCases.contains(.calculated))
        #expect(Evidence.allCases.contains(.heuristic))
        #expect(Evidence.allCases.contains(.userProvided))
    }
}

@Suite("Incident summary")
struct IncidentSummaryTests {
    @Test("Every statement is well formed")
    func wellFormed() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(), attribution: attribution())
        #expect(summary.isWellFormed)
        #expect(!summary.conclusions.isEmpty)
    }

    /// FR-038: measured, calculated and heuristic are all present and distinct.
    @Test("The summary separates measurement from calculation from hypothesis")
    func separatesEvidenceClasses() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(), attribution: attribution())

        #expect(!summary.measured.isEmpty, "no measured facts")
        #expect(summary.conclusions.contains { $0.evidence == .calculated },
                "the unattributed share is calculated, not measured")
        #expect(!summary.hypotheses.isEmpty, "no hypothesis about a contributor")
    }

    /// FR-013: every causal phrase is labelled by confidence. Naming a contributor
    /// is the only causal move the summary makes, and it must be a hypothesis.
    @Test("Naming a contributor is a hypothesis, never a measurement")
    func contributorIsHypothesis() throws {
        let summary = IncidentSummarizer.summarize(
            incident: incident(), attribution: attribution())

        let naming = summary.conclusions.filter { $0.text.contains("Xcode") }
        #expect(!naming.isEmpty)
        for statement in naming {
            #expect(statement.evidence == .heuristic,
                    "naming a contributor as measured fact would overstate causation")
            #expect(statement.confidence != nil)
        }
    }

    /// The judgement that matters most: a leader we can see may only be the
    /// largest thing we are permitted to see.
    @Test("Confidence falls as the unattributable share rises")
    func confidenceFallsWithUnattributed() {
        #expect(IncidentSummarizer.confidence(leaderShare: 0.7, unattributedShare: 0.1) == .high)
        #expect(IncidentSummarizer.confidence(leaderShare: 0.7, unattributedShare: 0.4) == .moderate)
        #expect(IncidentSummarizer.confidence(leaderShare: 0.7, unattributedShare: 0.6) == .low)
    }

    @Test("A mostly unattributable incident says so in the hypothesis itself")
    func caveatAppearsInText() throws {
        let summary = IncidentSummarizer.summarize(
            incident: incident(),
            attribution: attribution(total: 800, attributed: 300, leader: ("Xcode", 200)))

        let hypothesis = try #require(summary.hypotheses.first)
        #expect(hypothesis.confidence == .low)
        #expect(hypothesis.text.contains("only the largest we can see"))
    }

    @Test("Ruled-out statements are measured facts, not hedges")
    func ruledOutAreMeasured() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(conditions: [.cpuSaturation]), attribution: attribution())
        #expect(!summary.ruledOut.isEmpty)
        for statement in summary.ruledOut {
            #expect(statement.evidence == .measured)
            #expect(statement.confidence == nil)
        }
    }

    /// FR-036 and FR-013: no unsupported claims anywhere in the output.
    @Test("No statement overstates causation or promises a remedy")
    func noUnsupportedClaims() {
        for conditions in [Set<IncidentCondition>([.cpuSaturation]),
                           [.memoryPressure], [.cpuSaturation, .memoryPressure]] {
            let summary = IncidentSummarizer.summarize(
                incident: incident(conditions: conditions, peakMemory: .critical),
                attribution: attribution())

            let everything = (summary.conclusions + summary.ruledOut)
                .map(\.text).joined(separator: " ").lowercased() + " "
                + summary.headline.lowercased()

            for forbidden in ["caused by", "will fix", "freed", "free up", "wasted",
                              "memory leak", "optimi", "clean up", "guaranteed",
                              "frozen", "hung", "unresponsive"] {
                #expect(!everything.contains(forbidden),
                        "summary contains an unsupported claim: \(forbidden)")
            }
        }
    }

    @Test("A summary without attribution still states what was measured")
    func worksWithoutAttribution() {
        let summary = IncidentSummarizer.summarize(incident: incident(), attribution: nil)
        #expect(summary.isWellFormed)
        #expect(!summary.measured.isEmpty)
        #expect(summary.hypotheses.isEmpty, "no attribution means no basis for a hypothesis")
    }

    @Test("The headline names the condition and the duration")
    func headlineIsInformative() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(conditions: [.memoryPressure], peakMemory: .critical),
            attribution: attribution())
        #expect(summary.headline.contains("Memory pressure"))
        #expect(summary.headline.contains("minute"))
    }
}

/// Finding 5 of the 2026-08-26 review. `conditions` holds only what *sustained*
/// past its duration threshold — 60 s for storage, 120 s for thermal — so on
/// `conditions` alone a machine that sat at serious thermal for 110 s produced a
/// report asserting, as a measured fact, that nothing thermal happened.
@Suite("Ruling something out needs a measurement, not an absence")
struct RuledOutEvidenceTests {
    private func incident(
        thermal: ThermalState?, lowStorage: Bool?
    ) -> Incident {
        var subject = Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(),
            recoveryStartedAt: nil, closedAt: Date(),
            conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.95, peakMemoryPressure: .normal)
        subject.peakThermalState = thermal
        subject.lowStorageObserved = lowStorage
        return subject
    }

    private func ruledOut(_ subject: Incident) -> [String] {
        IncidentSummarizer.summarize(incident: subject, attribution: nil)
            .ruledOut.map(\.text)
    }

    @Test("A recorded nominal peak supports the claim")
    func recordedEvidenceSupportsTheClaim() {
        let text = ruledOut(incident(thermal: .nominal, lowStorage: false))
        #expect(text.contains { $0.contains("Not thermal throttling") })
        #expect(text.contains { $0.contains("Not a storage problem") })
    }

    /// The defect: raised thermal that never lasted long enough to open a condition.
    @Test("A raised peak withholds it, even though no condition opened")
    func aRaisedPeakWithholdsTheClaim() {
        let text = ruledOut(incident(thermal: .serious, lowStorage: true))
        #expect(!text.contains { $0.contains("Not thermal throttling") })
        #expect(!text.contains { $0.contains("Not a storage problem") })
    }

    /// An incident recorded before these fields existed knows nothing either way,
    /// and silence is the honest answer to a question nobody measured.
    @Test("An unrecorded peak says nothing rather than reassuring")
    func unknownSaysNothing() {
        let text = ruledOut(incident(thermal: nil, lowStorage: nil))
        #expect(!text.contains { $0.contains("Not thermal throttling") })
        #expect(!text.contains { $0.contains("Not a storage problem") })
        // Memory is unaffected: it was already corroborated by its recorded peak.
        #expect(text.contains { $0.contains("Not a memory problem") })
    }
}

/// Finding 19: the function's doc promised a guard the code did not have.
@Suite("A closed incident is never narrated from live state")
struct ClosedIncidentNarrationTests {
    private func attribution() -> CPUAttribution {
        CPUAttribution(
            totalBusyPercentOfOneCore: 100, attributedPercentOfOneCore: 100,
            unattributedPercentOfOneCore: 0,
            contributors: [ProcessCPUUsage(
                identity: ProcessIdentity(pid: 1, startTime: 1), command: "Passer By",
                percentOfOneCore: 100, residentBytes: 0)],
            protectedProcesses: [], logicalCoreCount: 8)
    }

    private func incident(open: Bool) -> Incident {
        Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(),
            recoveryStartedAt: nil, closedAt: open ? nil : Date(),
            conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.95, peakMemoryPressure: .normal)
    }

    @Test("A closed incident with no recorded attribution names nobody")
    func closedNamesNobody() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(open: false), attribution: attribution())
        #expect(!summary.conclusions.contains { $0.text.contains("Passer By") })
    }

    @Test("An open one may still use the live reading, which is about it")
    func openMayUseLive() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(open: true), attribution: attribution())
        #expect(summary.conclusions.contains { $0.text.contains("Passer By") })
    }
}
