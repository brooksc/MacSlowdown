import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// The evidence-room presentation model (design 1e, FR-013, FR-038, FR-049, FR-050).
///
/// These tests exist to hold the two lines the screen must not cross: nothing is
/// reconstructed from values we never retained, and nothing that follows a user
/// action is described as having been caused by it.
private let base = Date(timeIntervalSince1970: 1_770_000_000)

private func incident(
    conditions: Set<IncidentCondition> = [.memoryPressure],
    began: TimeInterval = 0,
    triggered: TimeInterval = 90,
    recoveryStarted: TimeInterval? = nil,
    closed: TimeInterval? = 660,
    severity: IncidentSeverity = .severe,
    peakCPU: Double = 0.22,
    peakPressure: MemoryPressureLevel = .critical
) -> Incident {
    Incident(
        id: UUID(),
        beganAt: base.addingTimeInterval(began),
        triggeredAt: base.addingTimeInterval(triggered),
        recoveryStartedAt: recoveryStarted.map(base.addingTimeInterval),
        closedAt: closed.map(base.addingTimeInterval),
        conditions: conditions,
        severity: severity,
        peakCPUBusyFraction: peakCPU,
        peakMemoryPressure: peakPressure)
}

private func summary(for incident: Incident) -> IncidentSummary {
    IncidentSummarizer.summarize(incident: incident, attribution: nil)
}

/// Phrases that would overstate what any of this evidence supports.
private let forbidden = [
    "caused by", "because of", "will fix", "fixed", "freed", "free up", "optimi",
    "clean up", "boost", "memory leak", "guaranteed", "proves",
]

private func assertNoOverstatement(_ text: String, _ comment: Comment) {
    let lowered = text.lowercased()
    for phrase in forbidden {
        // "we cannot prove" is the disclaimer itself, not a claim.
        if phrase == "proves" && lowered.contains("not proof") { continue }
        #expect(!lowered.contains(phrase), comment)
    }
}

// MARK: - Verdict

@Test func verdictHeadlineIsPlainLanguageAndClaimsNoCause() {
    let text = IncidentVerdict.headline(for: incident(), duration: "11 minutes")
    #expect(text.contains("comfortable memory"))
    #expect(text.contains("11 minutes"))
    assertNoOverstatement(text, "the headline must restate measurements, not explain them")
}

@Test func openIncidentHeadlineSaysItIsStillGoing() {
    let text = IncidentVerdict.headline(
        for: incident(closed: nil), duration: "4 minutes")
    #expect(text.contains("still going"))
}

@Test func headlineNamesEveryConditionThatWasSustained() {
    let text = IncidentVerdict.headline(
        for: incident(conditions: [.memoryPressure, .cpuSaturation]), duration: "3 minutes")
    #expect(text.contains("comfortable memory"))
    #expect(text.contains("processors"))
}

@Test func verdictParagraphReportsPeaksWithoutNamingACause() {
    let text = IncidentVerdict.paragraph(
        incident: incident(), attribution: nil, duration: "11 minutes")
    #expect(text.contains("critical"))
    #expect(text.contains("22%"))
    #expect(text.contains("closed"))
    assertNoOverstatement(text, "the opening paragraph must make no causal claim")
}

// MARK: - Legend

@Test func legendOffersNoLikelyLineWhenThereIsNoHypothesis() {
    let subject = incident()
    let entries = EvidenceLegend.entries(
        for: summary(for: subject), incident: subject, attribution: nil)
    #expect(entries.contains { $0.evidence == .measured })
    #expect(!entries.contains { $0.evidence == .heuristic },
            "a legend must not advertise a class the screen does not contain")
}

@Test func legendNamesWhatEachClassCovers() {
    let subject = incident()
    let entries = EvidenceLegend.entries(
        for: summary(for: subject), incident: subject, attribution: nil)
    let measured = entries.first { $0.evidence == .measured }
    #expect(measured != nil)
    #expect(measured?.subjects.contains("memory pressure level") == true)
    #expect(measured?.text.hasPrefix("Measured — ") == true)
}

// MARK: - Timeline

@Test func timelineMarksTheWindowTheTriggerAndTheRecovery() {
    let subject = incident(recoveryStarted: 600)
    let line = IncidentTimeline.build(incident: subject, samples: [])
    #expect(line.windowStart == subject.beganAt)
    #expect(line.windowEnd == subject.closedAt)
    let kinds = Set(line.markers.map(\.kind))
    #expect(kinds == [.began, .trigger, .recoveryStarted, .closed])
    #expect(line.markers.map(\.at) == line.markers.map(\.at).sorted())
}

@Test func timelineWithNoRetainedSamplesDrawsNoSeriesAndSaysSo() {
    let line = IncidentTimeline.build(incident: incident(), samples: [])
    #expect(!line.hasSeries)
    #expect(line.samples.isEmpty)
    #expect(IncidentTimeline.noSeriesNote.contains("recorded timestamps"))
}

@Test func timelineNamesTheSeriesWeDoNotRetainRatherThanOmittingThem() {
    let line = IncidentTimeline.build(incident: incident())
    let names = line.missingSeries.map(\.name)
    #expect(names.contains("Memory pressure over time"))
    #expect(names.contains("Swap written over time"))
    #expect(names.contains("Memory by application over time"))
    #expect(line.missingSeries.allSatisfy { !$0.reason.isEmpty })
}

@Test func timelineKeepsOnlySamplesInsideTheDrawnRange() {
    let subject = incident()
    let inside = HistorySample(
        timestamp: base.addingTimeInterval(300), totalBusyPercentOfOneCore: 400,
        attributedPercentOfOneCore: 300, unattributedPercentOfOneCore: 100,
        topContributors: [])
    let outside = HistorySample(
        timestamp: base.addingTimeInterval(100_000), totalBusyPercentOfOneCore: 10,
        attributedPercentOfOneCore: 10, unattributedPercentOfOneCore: 0, topContributors: [])
    let line = IncidentTimeline.build(incident: subject, samples: [outside, inside])
    #expect(line.samples.count == 1)
    #expect(line.samples.first?.timestamp == inside.timestamp)
    #expect(line.peakTotalPercentOfOneCore == 400)
}

@Test func timelineFractionIsClampedToTheAxis() {
    let line = IncidentTimeline.build(incident: incident())
    #expect(line.fraction(of: base.addingTimeInterval(-100_000)) == 0)
    #expect(line.fraction(of: base.addingTimeInterval(100_000)) == 1)
    let middle = line.fraction(of: base.addingTimeInterval(300))
    #expect(middle > 0 && middle < 1)
}

// MARK: - Events

@Test func eventsCoverTheWholeLifecycleInOrder() {
    let entries = IncidentEventLog.entries(incident: incident(recoveryStarted: 600))
    #expect(entries.count == 4)
    #expect(entries.map(\.at) == entries.map(\.at).sorted())
    #expect(entries.contains { $0.text.contains("incident opened") })
    #expect(entries.contains { $0.text.contains("incident closed") })
    #expect(entries.allSatisfy { $0.evidence == .measured })
}

@Test func eventsIncludeOurOwnSamplingCadenceWhenWeCanReadIt() {
    let cadence = SamplingCadence(
        mode: .investigation, interval: .seconds(1), reason: "an incident is open")
    let entries = IncidentEventLog.entries(
        incident: incident(closed: nil), cadence: cadence,
        cadenceObservedAt: base.addingTimeInterval(120))
    let ours = entries.first { $0.origin == .ourOwnBehaviour }
    #expect(ours != nil)
    #expect(ours?.text.contains("Sampling every 1 s") == true)
    #expect(ours?.evidence == .measured)
}

@Test func eventsNeverInventACadenceChangeWeDidNotObserve() {
    let entries = IncidentEventLog.entries(incident: incident(), cadence: nil)
    #expect(!entries.contains { $0.origin == .ourOwnBehaviour },
            "a cadence change we did not record must not be inferred from policy")
    #expect(IncidentEventLog.noOwnBehaviourNote.contains("not retained"))
}

// MARK: - Conditions (FR-049)

@Test func closedIncidentNeverShowsCurrentReadingsAsConditionsAtTheTime() {
    let context = IncidentConditions.build(
        incident: incident(),
        power: PowerContext(source: .battery, batteryPercentage: 46,
                            isCharging: false, lowPowerModeEnabled: false),
        thermal: .serious,
        startupVolume: nil,
        machine: MachineContext.current())
    if case .notRetained = context.provenance {} else {
        Issue.record("a closed incident's surroundings were never stored, so nothing may be presented as though they were")
    }
    #expect(!context.provenance.isShowable)
    #expect(context.provenance.note.contains("not stored with this incident"))
    let labels = context.rows.map(\.label)
    #expect(!labels.contains("Power"))
    #expect(!labels.contains("Thermal state"))
    #expect(labels.contains("Peak memory pressure"),
            "what the detector did record is still shown")
}

@Test func openIncidentShowsLiveReadingsAndSaysTheyAreLive() {
    let context = IncidentConditions.build(
        incident: incident(closed: nil),
        power: PowerContext(source: .battery, batteryPercentage: 46,
                            isCharging: false, lowPowerModeEnabled: true),
        thermal: .fair,
        startupVolume: nil,
        machine: MachineContext.current())
    #expect(context.provenance == .observedNow)
    let labels = context.rows.map(\.label)
    #expect(labels.contains("Power"))
    #expect(labels.contains("Low Power Mode"))
    #expect(labels.contains("Thermal state"))
    #expect(context.provenance.note.contains("still open"))
}

@Test func conditionsCarryTheBuildAndSchemaFooter() {
    let machine = MachineContext.current()
    let context = IncidentConditions.build(
        incident: incident(), power: nil, thermal: nil,
        startupVolume: nil, machine: machine)
    #expect(context.footer.contains("App \(machine.appVersion)"))
    #expect(context.footer.contains("schema \(machine.schemaVersion)"))
}

@Test func aCapabilityWeDoNotHaveIsStatedRatherThanLeftBlank() {
    let context = IncidentConditions.build(
        incident: incident(), power: nil, thermal: nil,
        startupVolume: nil, machine: MachineContext.current())
    #expect(context.unavailable.contains { $0.label == "Profile active" })
}

// MARK: - Post-action (FR-050)

@Test func withNoRecordedActionTheSectionSaysThereIsNothingToCompare() {
    let report = PostActionReport(verification: nil)
    #expect(!report.hasComparison)
    #expect(report.beforeAfter == nil)
    #expect(report.text == PostActionReport.noneRecorded)
}

@Test func anImprovementIsReportedAsCorrelationAndNeverAsCause() {
    let verification = ActionVerifier.verify(
        action: .activate, target: "Chrome", result: .succeeded,
        before: 0.82, after: 0.31, window: .seconds(180))
    let report = PostActionReport(verification: verification)
    #expect(report.hasComparison)
    #expect(report.beforeAfter?.before == "82%")
    #expect(report.beforeAfter?.after == "31%")
    #expect(report.outcomeLabel == VerificationOutcome.improved.label)
    assertNoOverstatement(report.text, "FR-050: a measured change is not a proven cause")
    #expect(PostActionReport.disclaimer.contains("not proof"))
}

@Test func anInconclusiveOutcomeIsAnAnswerNotAnError() {
    let verification = ActionVerifier.verify(
        action: .activate, target: "Chrome",
        result: .failed(reason: "macOS did not bring Chrome forward."),
        before: 0.8, after: nil, window: .seconds(180))
    let report = PostActionReport(verification: verification)
    #expect(report.outcomeLabel == VerificationOutcome.inconclusive.label)
    #expect(!report.hasComparison)
    assertNoOverstatement(report.text, "an inconclusive result must not imply an improvement")
}
