import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// The unattributable incident (design 1h, TASK-65.8, FR-013, FR-038, FR-039, FR-055).
///
/// These tests exist to hold four lines this screen must not cross:
///   - the parts of the CPU split always account for the whole;
///   - a suggested cause is never stated without the sentence that demotes it to
///     timing;
///   - absence is claimed only where our observation actually covers the window;
///   - a user's label changes what we say and never what was measured.

private let base = Date(timeIntervalSince1970: 1_770_000_000)

private func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

/// Microseconds since the epoch, the unit `ProcessIdentity.startTime` uses.
private func startTime(_ date: Date) -> UInt64 {
    UInt64(date.timeIntervalSince1970 * 1_000_000)
}

private func protectedProcess(_ command: String, pid: pid_t, started: Date) -> ProtectedProcess {
    ProtectedProcess(
        identity: ProcessIdentity(pid: pid, startTime: startTime(started)),
        command: command, uid: 0)
}

private func attributionSample(
    applications: [(String, Double)] = [("Safari", 30)],
    total: Double = 900,
    attributed: Double = 189,
    cores: Int = 10
) -> AttributionSample {
    AttributionSample(
        applications: applications.map {
            IncidentContributor(applicationID: "/Applications/\($0.0).app",
                                displayName: $0.0, peakPercentOfOneCore: $0.1)
        },
        totalBusyPercentOfOneCore: total,
        attributedPercentOfOneCore: attributed,
        unattributedPercentOfOneCore: total - attributed,
        logicalCoreCount: cores)
}

private func incident(
    began: TimeInterval = 0,
    closed: TimeInterval? = 480,
    attribution: AttributionSample? = attributionSample(),
    id: UUID = UUID()
) -> Incident {
    var incident = Incident(
        id: id,
        beganAt: at(began),
        triggeredAt: at(began + 180),
        recoveryStartedAt: nil,
        closedAt: closed.map(at),
        conditions: [.cpuSaturation],
        severity: .high,
        peakCPUBusyFraction: 0.91,
        peakMemoryPressure: .normal)
    if let attribution {
        incident.attribution = IncidentAttribution(sample: attribution, at: at(began + 60))
    }
    return incident
}

private func report(
    incident subject: Incident = incident(),
    protected: [ProtectedProcess] = [],
    lifecycle: [LifecycleEvent] = [],
    observedFrom: Date? = at(-3600),
    enumerationSucceeded: Bool = true,
    samples: [HistorySample] = [],
    recent: [Incident] = [],
    labels: [UUID: String] = [:],
    now: Date = at(600)
) -> UnattributedIncidentReport? {
    UnattributedIncidentReport.build(
        incident: subject,
        liveAttribution: nil,
        protected: protected,
        lifecycle: lifecycle,
        lifecycleObservedFrom: observedFrom,
        enumerationSucceeded: enumerationSucceeded,
        samples: samples,
        recentIncidents: recent,
        labels: labels,
        now: now)
}

/// Phrases that would overstate what timing evidence supports.
private let forbidden = [
    "caused by", "was responsible", "because of", "we know it was", "definitely",
    "proves", "optimi", "free up", "clean up",
]

private func assertNoOverstatement(_ text: String, _ comment: Comment) {
    let lowered = text.lowercased()
    for phrase in forbidden {
        #expect(!lowered.contains(phrase), comment)
    }
}

// MARK: - The split accounts for the whole (FR-055, AC#1)

@Test func recordedSplitAccountsForAllBusyCPU() throws {
    let subject = incident(attribution: attributionSample(total: 900, attributed: 189))
    let split = CPUSplit.build(from: try #require(subject.attribution))
    #expect(split.accountsForTotal)
    #expect(split.slices.reduce(0) { $0 + $1.percentOfOneCore } == 900)
}

@Test func unattributedIsTheLargestSliceWhenItIsTheLargest() throws {
    let subject = incident(attribution: attributionSample(total: 900, attributed: 189))
    let split = CPUSplit.build(from: try #require(subject.attribution))
    #expect(split.slices.first?.kind == .unattributed)
    #expect(Int((split.unattributedShare * 100).rounded()) == 79)
}

/// The remainder is arithmetic on two readings, so it carries the calculated
/// class — never "measured", which would claim we read it directly, and never a
/// hypothesis, which would suggest it might not be there.
@Test func unattributedSliceIsCalculatedNotMeasuredAndNotAHypothesis() throws {
    let split = CPUSplit.build(from: try #require(incident().attribution))
    #expect(split.unattributedSlice?.evidence == .calculated)
}

/// Per-application maxima and a single-interval total are different aggregations.
/// Stacking them would produce a chart whose parts can exceed its whole.
@Test func recordedApplicationPeaksAreNotStackedIntoTheTotal() throws {
    let sample = attributionSample(
        applications: [("Safari", 400), ("Mail", 300)], total: 500, attributed: 100)
    let split = CPUSplit.build(from: IncidentAttribution(sample: sample, at: base))
    #expect(split.coherence == .peaksAcrossIncident)
    #expect(!split.slices.contains { $0.kind == .application })
    #expect(split.applicationPeaks.count == 2)
    #expect(split.accountsForTotal)
    #expect(split.coherence.note.contains("separate"))
}

@Test func liveSplitStacksContributorsAndStillSums() {
    let attribution = CPUAttribution(
        totalBusyPercentOfOneCore: 400,
        attributedPercentOfOneCore: 120,
        unattributedPercentOfOneCore: 280,
        contributors: [],
        protectedProcesses: [],
        logicalCoreCount: 8)
    let split = CPUSplit.build(from: attribution)
    #expect(split.coherence == .singleInterval)
    #expect(split.accountsForTotal)
}

// MARK: - The presentation only applies where it is warranted (AC#1)

@Test func anIncidentOurOwnAppsExplainDoesNotGetTheUnattributablePresentation() {
    let explained = incident(attribution: attributionSample(total: 500, attributed: 450))
    #expect(report(incident: explained) == nil)
}

@Test func aClosedIncidentNeverBorrowsLiveAttributionToFillTheGap() {
    let closed = incident(attribution: nil)
    let live = CPUAttribution(
        totalBusyPercentOfOneCore: 900, attributedPercentOfOneCore: 100,
        unattributedPercentOfOneCore: 800, contributors: [],
        protectedProcesses: [], logicalCoreCount: 10)
    let built = UnattributedIncidentReport.build(
        incident: closed, liveAttribution: live, protected: [], lifecycle: [],
        lifecycleObservedFrom: at(-3600), enumerationSucceeded: true,
        samples: [], recentIncidents: [], now: at(600))
    #expect(built == nil)
}

// MARK: - The remainder is stated as a measurement (AC#2)

@Test func theLimitIsExplainedAsOwnershipNotAsTheSandbox() {
    // Our own measurements: other-uid processes are denied identically sandboxed
    // and unsandboxed. Blaming the sandbox would be tidier and false.
    let text = UnattributedExplanation.limit.lowercased()
    #expect(text.contains("processes you own"))
    #expect(text.contains("sandboxed or not"))
}

@Test func theRemainderIsCalledAMeasurementAndNotARoundingError() {
    let text = UnattributedExplanation.remainderIsMeasured(share: 0.79)
    #expect(text.contains("79%"))
    #expect(text.contains("measured difference"))
    #expect(text.contains("not a rounding error"))
    assertNoOverstatement(text, "the explanation of the remainder")
}

@Test func theExplanationPointsAtATheToolThatCanSeeInside() {
    #expect(UnattributedExplanation.handOff.contains("Activity Monitor"))
    #expect(UnattributedExplanation.handOff.contains("more privilege"))
}

@Test func theOpeningStatesTheLimitWithoutNamingACause() throws {
    let built = try #require(report())
    #expect(built.headline.contains("Something outside your apps"))
    #expect(built.opening.contains("79%"))
    #expect(built.opening.contains("not how much CPU"))
    assertNoOverstatement(built.opening, "the opening paragraph")
    assertNoOverstatement(built.headline, "the headline")
}

// MARK: - What was running: names and timing only (AC#3)

@Test func systemProcessesAreListedByNameAndTimingWithTheirCPUDeclaredUnmeasurable() throws {
    let built = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
        protectedProcess("mds_stores", pid: 200, started: at(-90_000)),
    ]))
    let commands = built.roster.running.map(\.command)
    #expect(commands.contains("backupd"))
    #expect(commands.contains("mds_stores"))
    // The descriptor table turns a name into an answer.
    #expect(built.roster.running.first { $0.command == "backupd" }?.displayName == "Time Machine")
    #expect(SystemProcessRoster.cpuLimitation.contains("does not report per-process CPU"))
    #expect(SystemProcessRoster.evidenceNote.contains("never their CPU"))

    let backup = try #require(built.roster.running.first { $0.command == "backupd" })
    let timing = backup.timing(window: built.window)
    #expect(timing.contains("2 minutes before the window"))
    #expect(timing.contains("still running"))
}

/// Absence is evidence — but only when we were watching the whole window.
@Test func absenceIsListedWhenOurObservationCoversTheWindow() throws {
    let built = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
    ]))
    #expect(built.roster.absenceClaimable)
    #expect(built.roster.absent.contains { $0.command == "softwareupdated" })
    let absent = try #require(built.roster.absent.first { $0.command == "softwareupdated" })
    #expect(absent.displayName == "Software Update")
    #expect(absent.timing(window: built.window).contains("not running"))
    #expect(built.roster.absenceLimitation == nil)
}

@Test func absenceIsNotClaimedWhenMonitoringBeganAfterTheWindow() throws {
    let built = try #require(report(
        protected: [protectedProcess("backupd", pid: 900, started: at(-120))],
        observedFrom: at(300)))
    #expect(!built.roster.absenceClaimable)
    #expect(built.roster.absent.isEmpty)
    let limitation = try #require(built.roster.absenceLimitation)
    #expect(limitation.contains("not listing anything as absent"))
}

@Test func absenceIsNotClaimedWhenTheProcessTableCouldNotBeRead() throws {
    let built = try #require(report(
        protected: [protectedProcess("backupd", pid: 900, started: at(-120))],
        enumerationSucceeded: false))
    #expect(built.roster.absent.isEmpty)
    #expect(built.roster.absenceLimitation?.contains("could not be read") == true)
}

/// A daemon that has been up for eleven days is not evidence about eight minutes.
@Test func aLongRunningProcessOffTheWatchlistIsNotOfferedAsTiming() throws {
    let built = try #require(report(protected: [
        protectedProcess("someotherd", pid: 500, started: at(-11 * 86_400)),
    ]))
    #expect(!built.roster.running.contains { $0.command == "someotherd" })
}

@Test func aProcessThatStartedJustBeforeTheWindowIsIncludedEvenOffTheWatchlist() throws {
    let built = try #require(report(protected: [
        protectedProcess("someotherd", pid: 500, started: at(-60)),
    ]))
    #expect(built.roster.running.contains { $0.command == "someotherd" })
}

@Test func aClosedIncidentExplainsHowALiveRosterDescribesAWindowThatHasEnded() throws {
    let built = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
    ]))
    #expect(built.roster.provenanceNote.contains("deduction from two measured times"))
}

@Test func anExitIsDeclaredAccurateOnlyToASamplingInterval() {
    #expect(SystemProcessRoster.timingPrecisionNote.contains("one sampling interval"))
    #expect(SystemProcessRoster.timingPrecisionNote.contains("Start times come from the kernel"))
}

// MARK: - Any cause is an inference from timing (AC#4)

@Test func aTimingCandidateAlwaysCarriesTheInferenceDisclaimer() throws {
    let built = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
    ]))
    let inference = try #require(built.inferences.first)
    #expect(inference.command == "backupd")
    #expect(inference.conclusion.evidence == .heuristic)
    #expect(inference.conclusion.text.contains(TimingInference.disclaimer))
    #expect(inference.conclusion.text.contains("inference from timing, not an attribution"))
    assertNoOverstatement(inference.conclusion.text, "the timing inference")
    // The supporting evidence is shown, not merely asserted.
    #expect(inference.supporting.contains { $0.evidence == .measured })
}

@Test func confidenceIsNeverHigherThanModerateAndFallsWhenSeveralProcessesFit() throws {
    let single = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
    ]))
    #expect(single.inferences.first?.conclusion.confidence == .moderate)

    let several = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
        protectedProcess("softwareupdated", pid: 901, started: at(-100)),
    ]))
    #expect(several.inferences.allSatisfy { $0.conclusion.confidence == .low })
    #expect(several.inferences.first?.conclusion.text.contains("does not single one out") == true)
}

@Test func noCandidateProducesARefusalRatherThanAGuess() throws {
    let built = try #require(report(protected: [
        protectedProcess("mds_stores", pid: 200, started: at(-90_000)),
    ]))
    #expect(built.inferences.isEmpty)
    #expect(TimingInference.noneFound.contains("not going to name one"))
}

/// The shape of a load is arithmetic over samples. It supports a suggestion; it
/// never makes one, and it never names a kind of work.
@Test func loadShapeIsCalculatedAndDeclaresThatItIdentifiesNothing() throws {
    let samples = (0..<10).map { index in
        HistorySample(
            timestamp: at(Double(index) * 40),
            totalBusyPercentOfOneCore: 880 + Double(index % 2) * 10,
            attributedPercentOfOneCore: 180,
            unattributedPercentOfOneCore: 700,
            topContributors: [])
    }
    let built = try #require(report(
        protected: [protectedProcess("backupd", pid: 900, started: at(-120))],
        samples: samples))
    let shape = try #require(built.shape)
    #expect(shape.isSteady)
    #expect(shape.conclusion.evidence == .calculated)
    #expect(shape.conclusion.text.contains("does not identify what produced it"))
    for name in ["backup", "Time Machine", "index"] {
        #expect(!shape.conclusion.text.contains(name))
    }
}

@Test func aShapeIsNotDescribedFromTooFewSamples() {
    let samples = (0..<3).map { index in
        HistorySample(
            timestamp: at(Double(index) * 40), totalBusyPercentOfOneCore: 880,
            attributedPercentOfOneCore: 180, unattributedPercentOfOneCore: 700,
            topContributors: [])
    }
    #expect(LoadShape.build(
        samples: samples,
        window: DateInterval(start: at(0), end: at(480))) == nil)
}

// MARK: - The user's own label (AC#5, FR-039)

@Test func aLabelIsStoredLocallyAndIsReversible() {
    let defaults = UserDefaults(suiteName: "unattributed-label-\(UUID().uuidString)")!
    let labels = IncidentLabels(defaults: defaults)
    let id = UUID()

    labels.set("Time Machine backup", for: id)
    #expect(labels.label(for: id) == "Time Machine backup")
    // Read back through a second instance: it is on disk, not in this object.
    #expect(IncidentLabels(defaults: defaults).label(for: id) == "Time Machine backup")

    labels.clear(for: id)
    #expect(labels.label(for: id) == nil)
    #expect(IncidentLabels(defaults: defaults).label(for: id) == nil)
}

@Test func anEmptyLabelRemovesRatherThanStoringABlank() {
    let defaults = UserDefaults(suiteName: "unattributed-blank-\(UUID().uuidString)")!
    let labels = IncidentLabels(defaults: defaults)
    let id = UUID()
    labels.set("Something", for: id)
    labels.set("   ", for: id)
    #expect(labels.label(for: id) == nil)
}

@Test func storedLabelsAreBounded() {
    let defaults = UserDefaults(suiteName: "unattributed-bound-\(UUID().uuidString)")!
    let labels = IncidentLabels(defaults: defaults)
    for _ in 0..<(IncidentLabels.maximumLabels + 20) {
        labels.set("A label", for: UUID())
    }
    #expect(labels.labels.count == IncidentLabels.maximumLabels)
}

@Test func aLabelIsUserProvidedEvidenceAndPromisesNotToRewriteWhatWasMeasured() {
    let conclusion = IncidentLabels.conclusion(for: "Time Machine backup")
    #expect(conclusion.evidence == .userProvided)
    #expect(IncidentLabels.promise.contains("only on this Mac"))
    #expect(IncidentLabels.promise.contains("never changes what was measured"))
}

/// Suggestions come from processes we saw, and only ones with a published role.
@Test func labelSuggestionsComeFromTheEvidenceRatherThanFromOurImagination() throws {
    let built = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
        protectedProcess("someotherd", pid: 901, started: at(-60)),
    ]))
    let suggestions = IncidentLabels.suggestions(from: built.roster)
    #expect(suggestions.contains("Time Machine"))
    #expect(!suggestions.contains("someotherd"))
}

// MARK: - Recurrence (AC#6)

@Test func aTimeOfDayPatternIsSurfacedAcrossUnattributedIncidents() throws {
    // Three unattributed incidents, each a day apart, at the same hour.
    let calendar = Calendar(identifier: .gregorian)
    let day: TimeInterval = 86_400
    let subject = incident(began: 0, closed: 480)
    let recent = [
        incident(began: -day, closed: -day + 480),
        incident(began: -2 * day, closed: -2 * day + 480),
    ]
    let pattern = try #require(UnattributedRecurrenceFinder.pattern(
        in: recent, including: subject, calendar: calendar, now: at(600)))

    #expect(pattern.incidentCount == 3)
    #expect(pattern.count.evidence == .measured)
    #expect(pattern.hasTimeOfDayPattern)
    #expect(pattern.clustering?.evidence == .calculated)
    // The interpretation — and only the interpretation — is the hypothesis.
    let hint = try #require(pattern.hint)
    #expect(hint.evidence == .heuristic)
    #expect(hint.text.contains("does not say which scheduled work"))
}

@Test func twoOccurrencesAreNotCalledAPattern() {
    let day: TimeInterval = 86_400
    #expect(UnattributedRecurrenceFinder.pattern(
        in: [incident(began: -day, closed: -day + 480)],
        including: incident(), now: at(600)) == nil)
}

@Test func incidentsOurAppsExplainAreNotCountedIntoTheUnattributedPattern() {
    let day: TimeInterval = 86_400
    let explained = (1...4).map {
        incident(began: -Double($0) * day,
                 closed: -Double($0) * day + 480,
                 attribution: attributionSample(total: 500, attributed: 450))
    }
    #expect(UnattributedRecurrenceFinder.pattern(
        in: explained, including: incident(), now: at(600)) == nil)
}

@Test func earlierLabelsAreRecalledAsTheUsersOwnWords() throws {
    let day: TimeInterval = 86_400
    let older = incident(began: -day, closed: -day + 480)
    let oldest = incident(began: -2 * day, closed: -2 * day + 480)
    let pattern = try #require(UnattributedRecurrenceFinder.pattern(
        in: [older, oldest], including: incident(),
        labels: [older.id: "Time Machine backup"], now: at(600)))
    let recall = try #require(pattern.labelRecall)
    #expect(recall.evidence == .userProvided)
    #expect(recall.text.contains("Time Machine backup"))
}

// MARK: - The tools offered follow the evidence

@Test func toolsFollowWhatWasRunningAndAlwaysIncludeTheOneThatSeesMore() throws {
    let built = try #require(report(protected: [
        protectedProcess("backupd", pid: 900, started: at(-120)),
    ]))
    let ids = built.tools.map(\.id)
    #expect(ids.first == SystemTool.activityMonitor.id)
    #expect(ids.contains(SystemTool.timeMachine.id))
    // softwareupdated was absent, and absence is exactly when a user wants to look.
    #expect(ids.contains(SystemTool.softwareUpdate.id))
}

@Test func noHandOffClaimsWeReadWhatWeCannotRead() {
    for tool in [SystemTool.activityMonitor, .console, .timeMachine,
                 .softwareUpdate, .appUpdates, .spotlight] {
        assertNoOverstatement(tool.explanation, "\(tool.id) explanation")
        #expect(!tool.explanation.lowercased().contains("we will read"))
    }
    #expect(SystemTool.console.explanation.contains("We cannot read those reports"))
}
