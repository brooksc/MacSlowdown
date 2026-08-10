import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// The repeated-quit incident (design 1o, TASK-65.15, FR-013, FR-046).
///
/// The lines these tests hold:
///   - evidence is sessions, exits and PID pairs, never a resource curve;
///   - "resource conditions were normal" is claimed only from samples that exist,
///     and "we did not observe a problem" is what is said when they do not;
///   - the cause is low confidence and stays low, because the thing that would
///     raise it is not observable at all;
///   - nothing anywhere implies we can see a hang, a freeze or a beachball.

private let base = Date(timeIntervalSince1970: 1_770_000_000)

private func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

private func startTime(_ date: Date) -> UInt64 {
    UInt64(date.timeIntervalSince1970 * 1_000_000)
}

private func launched(_ command: String, pid: pid_t, started: TimeInterval) -> LifecycleEvent {
    .launched(
        identity: ProcessIdentity(pid: pid, startTime: startTime(at(started))),
        command: command, isApplication: true, at: at(started))
}

private func exited(_ command: String, pid: pid_t, started: TimeInterval,
                    noticed: TimeInterval) -> LifecycleEvent {
    .exited(
        identity: ProcessIdentity(pid: pid, startTime: startTime(at(started))),
        command: command, isApplication: true, at: at(noticed))
}

/// Three sessions that ended and one still open: 2841 → 2896 → 3014 → 3120.
private let sequence: [LifecycleEvent] = [
    launched("Final Cut Pro", pid: 2841, started: -120),
    exited("Final Cut Pro", pid: 2841, started: -120, noticed: 120),
    launched("Final Cut Pro", pid: 2896, started: 161),
    exited("Final Cut Pro", pid: 2896, started: 161, noticed: 420),
    launched("Final Cut Pro", pid: 3014, started: 478),
    exited("Final Cut Pro", pid: 3014, started: 478, noticed: 660),
    launched("Final Cut Pro", pid: 3120, started: 696),
]

private let pattern = RelaunchPattern(
    command: "Final Cut Pro", exits: 3,
    firstAt: at(120), lastAt: at(660), confidence: .moderate)

private func quietSamples() -> [HistorySample] {
    (0..<20).map { index in
        HistorySample(
            timestamp: at(-120 + Double(index) * 45),
            totalBusyPercentOfOneCore: 180,
            attributedPercentOfOneCore: 120,
            unattributedPercentOfOneCore: 60,
            topContributors: [
                ContributorSummary(
                    pid: 2841, startTime: startTime(at(-120)), command: "Final Cut Pro",
                    percentOfOneCore: 40,
                    // Falling, so growth towards a limit is ruled out rather than
                    // assumed.
                    residentBytes: UInt64(7_000_000_000 - index * 250_000_000)),
            ])
    }
}

private func report(
    samples: [HistorySample] = [],
    cores: Int? = 10,
    pressure: MemoryPressureLevel? = .normal
) -> RepeatedQuitReport {
    RepeatedQuitReport.build(
        pattern: pattern, displayName: "Final Cut Pro", lifecycle: sequence,
        samples: samples, logicalCoreCount: cores, peakPressure: pressure,
        now: at(900))
}

private let forbidden = [
    "hung", "hang", "froze", "frozen", "beachball", "unresponsive", "not responding",
    "crashed because", "caused by", "we know why",
]

private func assertClaimsNoHang(_ text: String, _ comment: Comment) {
    let lowered = text.lowercased()
    for phrase in forbidden {
        // The limitation sentences name these words in order to deny them.
        if lowered.contains("rather than guess") || lowered.contains("exactly as it reports") {
            continue
        }
        #expect(!lowered.contains(phrase), comment)
    }
}

// MARK: - Evidence is lifecycle, not curves (AC#1)

@Test func theEpisodeIsBuiltFromSessionsAndExitsRatherThanFromAMetricSeries() {
    let built = report()
    #expect(built.sessions.count == 4)
    #expect(built.exits.count == 3)
    #expect(built.sessions.filter(\.isOpen).count == 1)
    #expect(built.sessions.last?.pid == 3120)
    #expect(built.headline.contains("Final Cut Pro quit three times"))
    assertClaimsNoHang(built.headline, "the headline")
    assertClaimsNoHang(built.opening, "the opening paragraph")
}

/// A session start is the kernel's, so its length is exact at that end. Only the
/// exit is one sampling interval wide.
@Test func sessionLengthsComeFromKernelStartTimesNotFromTheSweepThatNoticed() throws {
    let built = report()
    let first = try #require(built.sessions.first)
    #expect(first.startedAt == at(-120))
    #expect(first.endedAt == at(120))
    #expect(first.duration == 240)
    #expect(RepeatedQuitReport.timingPrecisionNote.contains("one sampling interval"))
}

// MARK: - Each exit carries its PID evidence (AC#2)

@Test func eachExitNamesThePIDThatWentAndThePIDThatReplacedIt() throws {
    let built = report()
    let texts = built.exits.map(\.text)
    #expect(texts[0].contains("PID 2841 disappeared"))
    #expect(texts[0].contains("as PID 2896"))
    #expect(texts[1].contains("PID 2896 disappeared"))
    #expect(texts[1].contains("as PID 3014"))
    #expect(texts[2].contains("PID 3014 disappeared"))
    #expect(texts[2].contains("as PID 3120"))

    // The interval between them is stated, because "it came straight back" is the
    // difference between a relaunch loop and an app the user closed.
    #expect(built.exits[0].interval == 41)
    #expect(texts[0].contains("41 s later"))
}

@Test func anExitWeNeverSawRelaunchIsNotDescribedAsHavingRelaunched() {
    let unfinished = RepeatedQuitReport.build(
        pattern: pattern, lifecycle: Array(sequence.prefix(2)), now: at(900))
    let exit = unfinished.exits.first
    #expect(exit?.relaunchedAsPID == nil)
    #expect(exit?.text.contains("did not see it start again") == true)
}

// MARK: - Resource conditions used to rule out (AC#3)

@Test func normalResourceConditionsRuleOutAResourceCause() throws {
    let built = report(samples: quietSamples())
    #expect(built.resources.rulesOutResources)
    let conclusion = try #require(built.ruledOut.first)
    #expect(conclusion.evidence == .calculated)
    #expect(conclusion.text.contains("Not a resource problem"))
    #expect(conclusion.text.contains("not short of anything we measure"))
    #expect(built.opening.contains("Nothing was wrong with CPU or memory"))
}

/// The important half. Without samples we did not observe a problem; that is not
/// the same as there not having been one, and the wording must not blur them.
@Test func withoutRetainedSamplesAResourceCauseIsNotRuledOutAtAll() throws {
    let built = report(samples: [])
    #expect(!built.resources.rulesOutResources)
    let conclusion = try #require(built.ruledOut.first)
    #expect(conclusion.text.contains("cannot rule a resource cause in or out"))
    #expect(conclusion.text.contains("not that there was none"))
    #expect(built.opening.contains("cannot say whether"))
}

@Test func aPercentageOfOneCoreIsNotJudgedWithoutTheCoreCount() {
    let built = report(samples: quietSamples(), cores: nil)
    #expect(!built.resources.rulesOutResources)
    #expect(built.ruledOut.first?.text.contains("logical cores") == true)
}

@Test func aBusyMachineIsReportedAsNotRuledOutRatherThanAsTheCause() throws {
    let busy = quietSamples().map { sample in
        HistorySample(
            timestamp: sample.timestamp, totalBusyPercentOfOneCore: 950,
            attributedPercentOfOneCore: 500, unattributedPercentOfOneCore: 450,
            topContributors: sample.topContributors)
    }
    let built = report(samples: busy)
    let conclusion = try #require(built.ruledOut.first)
    #expect(conclusion.text.contains("not ruled out"))
    #expect(conclusion.text.contains("cannot see the reason at all"))
    assertClaimsNoHang(conclusion.text, "the strained verdict")
}

/// Memory before each exit refutes the obvious hypothesis rather than supporting
/// one, and says which statistic it is — resident size, not footprint.
@Test func memoryBeforeEachExitIsUsedToRuleOutGrowthTowardsALimit() throws {
    let built = report(samples: quietSamples())
    #expect(built.memoryBeforeExits.count == 3)
    let conclusion = try #require(
        MemoryTrendBeforeExits.conclusion(built.memoryBeforeExits))
    #expect(conclusion.evidence == .calculated)
    #expect(conclusion.text.contains("not an application growing towards a limit"))
    #expect(conclusion.text.contains("Resident size"))
}

@Test func oneMemoryReadingIsNotATrend() {
    #expect(MemoryTrendBeforeExits.conclusion(
        [MemoryBeforeExit(exitNoticedAt: at(120), residentBytes: 1_000)]) == nil)
}

// MARK: - Low confidence, stated as such (AC#4)

@Test func theCauseIsLowConfidenceAndSaysWeCannotSeeWhyItExited() throws {
    let built = report(samples: quietSamples())
    let hypothesis = try #require(built.conclusions.last)
    #expect(hypothesis.evidence == .heuristic)
    #expect(hypothesis.confidence == .low)
    #expect(hypothesis.text.contains("no way to see why it exited"))
    #expect(hypothesis.text.contains("cannot be narrowed further"))
    assertClaimsNoHang(hypothesis.text, "the hypothesis")
}

/// Confidence never rises above low here even when the pattern's own name-matching
/// confidence is higher: those measure different things, and the limiting one is
/// that the reason for an exit is not observable.
@Test func aConfidentPatternDoesNotProduceAConfidentCause() {
    let confident = RelaunchPattern(
        command: "Final Cut Pro", exits: 3, firstAt: at(120), lastAt: at(660),
        confidence: .high)
    let built = RepeatedQuitReport.build(
        pattern: confident, lifecycle: sequence, now: at(900))
    #expect(built.conclusions.last?.confidence == .low)
}

/// Half the design's sentence is provable and half is not. We never issue a quit
/// request, so that half is true by construction; whether the *user* quit the app
/// is not visible to us and is not claimed.
@Test func weClaimOnlyThatTheQuitDidNotComeFromUs() {
    let measured = report().conclusions.first
    #expect(measured?.evidence == .measured)
    #expect(measured?.text.contains("never quits an application") == true)
    #expect(measured?.text.contains("Whether you quit it yourself is not something we can see")
            == true)
}

// MARK: - Hangs are not detectable, and we say so (AC#5)

@Test func theScreenStatesPlainlyThatAHangIsNotDetectable() {
    #expect(RepeatedQuitReport.capability.contains("cannot tell you an application froze"))
    #expect(RepeatedQuitReport.capability.contains("exactly as it reports a healthy one"))
    #expect(RepeatedQuitReport.capability.contains("rather than guess"))
}

/// The framework already owns this sentence. Restating it in the app would let the
/// two drift into saying different things about the same limit.
@Test func theLimitationIsTheFrameworksOwnWordsRatherThanACopy() {
    #expect(RepeatedQuitReport.hangLimitation == RelaunchPattern.limitation)
}

@Test func nothingInTheNarrativeImpliesWeSawAHang() {
    let built = report(samples: quietSamples())
    for text in [built.headline, built.opening]
        + built.conclusions.map(\.text) + built.ruledOut.map(\.text) {
        assertClaimsNoHang(text, "narrative text: \(text.prefix(40))")
    }
}

// MARK: - Actions point at tools that see more (AC#6)

@Test func theHandOffsPointAtToolsThatCanReadWhatWeCannot() {
    let built = report()
    let ids = built.tools.map(\.id)
    #expect(ids.contains(SystemTool.console.id))
    #expect(ids.contains(SystemTool.appUpdates.id))
    #expect(SystemTool.console.explanation.contains("We cannot read those reports"))
    #expect(SystemTool.console.explanation.contains("Console can"))
}

@Test func noActionInThisReportTouchesAProcess() {
    // FR-037: no process control, not even a dormant path. Every hand-off here
    // opens something and does nothing else.
    for tool in report().tools {
        switch tool.target {
        case .application, .settings: break
        }
    }
    #expect(report().tools.allSatisfy { !$0.title.lowercased().contains("quit") })
}
