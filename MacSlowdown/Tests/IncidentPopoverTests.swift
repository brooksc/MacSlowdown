import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

// The live-incident popover (design 1b). Everything the screen says is built by a
// pure function so that the copy — which is a requirement, not decoration — is
// reachable from a test rather than trapped inside a `body`.

private func identity(_ pid: pid_t) -> ProcessIdentity {
    ProcessIdentity(pid: pid, startTime: UInt64(pid) * 1000)
}

private func record(_ pid: pid_t, command: String, measurable: Bool = true) -> ProcessRecord {
    ProcessRecord(
        identity: identity(pid), command: command,
        uid: measurable ? getuid() : 0, ppid: 1,
        metrics: measurable
            ? .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1 << 20))
            : .notPermitted)
}

private func familyRow(
    _ name: String, percent: Double, members: [ProcessRecord], bundlePath: String? = nil
) -> MonitorStore.FamilyRow {
    let family = ProcessFamily(
        id: bundlePath ?? name, displayName: name, bundlePath: bundlePath,
        members: members.map {
            FamilyMember(
                record: $0,
                resolved: ResolvedIdentity(
                    executablePath: bundlePath.map { $0 + "/Contents/MacOS/" + name },
                    appBundlePath: bundlePath, bundleID: nil, teamID: nil),
                membership: .certain)
        })
    return MonitorStore.FamilyRow(
        family: family, percentOfOneCore: percent, residentBytes: 1 << 20)
}

private func attribution(total: Double, attributed: Double) -> CPUAttribution {
    CPUAttribution(
        totalBusyPercentOfOneCore: total,
        attributedPercentOfOneCore: attributed,
        unattributedPercentOfOneCore: max(0, total - attributed),
        contributors: [],
        protectedProcesses: [],
        logicalCoreCount: 10)
}

private func episode(
    conditions: Set<IncidentCondition>,
    beganAt: Date,
    severity: IncidentSeverity = .high
) -> Incident {
    Incident(
        id: UUID(), beganAt: beganAt, triggeredAt: beganAt.addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: nil, conditions: conditions,
        severity: severity, peakCPUBusyFraction: 0.94, peakMemoryPressure: .normal)
}

@Suite("Incident headline")
struct IncidentHeadlineTests {
    let began = Date(timeIntervalSince1970: 1_000_000)

    /// The design's headline: what the condition is, and how long it has held.
    @Test("The headline names the condition and its duration")
    func headlineStatesConditionAndDuration() {
        let text = PopoverPresentation.incidentHeadline(
            episode(conditions: [.cpuSaturation], beganAt: began),
            now: began.addingTimeInterval(6 * 60))
        #expect(text == "CPU has been maxed for 6 min")
    }

    /// Duration runs from when the condition first breached, not from when our
    /// sustained-duration threshold elapsed — a user asking "how long has this been
    /// going on" means the slowdown, not our bookkeeping.
    @Test("Duration is measured from the first breach, not from the trigger")
    func durationRunsFromBeganAt() {
        let incident = episode(conditions: [.cpuSaturation], beganAt: began)
        #expect(PopoverPresentation.incidentHeadline(incident, now: incident.triggeredAt)
            .contains("3 min"))
    }

    /// A `Set` has no order, so without an explicit one the headline would reword
    /// itself between samples.
    @Test("Several conditions are joined in a stable order")
    func multipleConditionsAreOrdered() {
        let text = PopoverPresentation.incidentHeadline(
            episode(conditions: [.memoryPressure, .cpuSaturation], beganAt: began),
            now: began.addingTimeInterval(120))
        #expect(text == "CPU has been maxed and memory has been under pressure for 2 min")
    }

    @Test("Every condition has plain-language copy of its own",
          arguments: IncidentCondition.allCases)
    func everyConditionHasAPhrase(condition: IncidentCondition) {
        let phrase = PopoverPresentation.conditionPhrase(condition)
        #expect(!phrase.isEmpty)
        #expect(phrase != condition.label)
    }

    /// A second-resolution figure would imply a precision the sampling cadence does
    /// not have.
    @Test("Elapsed time is deliberately coarse", arguments: [
        (0.0, "less than a minute"), (59.0, "less than a minute"),
        (60.0, "1 min"), (390.0, "6 min"), (3600.0, "1 hr"), (4500.0, "1 hr 15 min"),
    ])
    func elapsedPhrasing(seconds: Double, expected: String) {
        #expect(PopoverPresentation.elapsedPhrase(seconds) == expected)
    }
}

@Suite("The one causal sentence")
struct IncidentCauseTests {
    /// FR-013 requires causal language to carry a confidence label; FR-038 requires
    /// an evidence class. `cause` returns a `Conclusion` rather than a `String`
    /// precisely so neither can be omitted at the call site.
    @Test("The cause is a labelled heuristic, never a bare assertion")
    func causeIsLabelled() {
        let conclusion = PopoverPresentation.cause(
            leaderName: "Xcode", leaderPercentOfOneCore: 412,
            totalBusyPercentOfOneCore: 940, unattributedShare: 0.1,
            confidence: .moderate)
        #expect(conclusion.evidence == .heuristic)
        #expect(conclusion.confidence == .moderate)
        #expect(conclusion.isWellFormed)
        #expect(conclusion.display.hasPrefix("Likely, moderate confidence."))
    }

    @Test("The sentence names the contributor, its magnitude and the consequence")
    func causeNamesAllThree() {
        let text = PopoverPresentation.cause(
            leaderName: "Xcode", leaderPercentOfOneCore: 412,
            totalBusyPercentOfOneCore: 500, unattributedShare: 0.1,
            confidence: .high).text
        #expect(text.contains("Xcode"))
        #expect(text.contains("412%"))
        #expect(text.contains("cores"))
        #expect(text.contains("slower"))
    }

    @Test("'Most of it' is claimed only when it really is most of it")
    func majorityClaimRequiresAMajority() {
        let majority = PopoverPresentation.cause(
            leaderName: "Xcode", leaderPercentOfOneCore: 412,
            totalBusyPercentOfOneCore: 500, unattributedShare: 0, confidence: .high)
        #expect(majority.text.hasPrefix("Most of it is Xcode"))

        let minority = PopoverPresentation.cause(
            leaderName: "Xcode", leaderPercentOfOneCore: 100,
            totalBusyPercentOfOneCore: 500, unattributedShare: 0, confidence: .low)
        #expect(!minority.text.contains("Most of it"))
        #expect(minority.text.contains("largest contributor we can measure"))
    }

    /// The leader may only be the largest thing we are permitted to see.
    @Test("A large unattributable share qualifies the claim in the sentence itself")
    func unattributableShareQualifiesTheClaim() {
        let text = PopoverPresentation.cause(
            leaderName: "Xcode", leaderPercentOfOneCore: 412,
            totalBusyPercentOfOneCore: 940, unattributedShare: 0.38,
            confidence: .low).text
        #expect(text.contains("may not be the largest contributor overall"))
    }

    /// We cannot see whether the work is finite, so we never say when it will end.
    @Test("The consequence is not a prediction about when it stops")
    func consequenceMakesNoPromise() {
        let text = PopoverPresentation.cause(
            leaderName: "Xcode", leaderPercentOfOneCore: 412,
            totalBusyPercentOfOneCore: 500, unattributedShare: 0, confidence: .high).text
        #expect(!text.contains("until it finishes"))
    }
}

@Suite("Share of the busy time")
struct ShareOfBusyTimeTests {
    private func shares(
        _ families: [MonitorStore.FamilyRow], total: Double, attributed: Double
    ) -> [PopoverPresentation.ShareRow] {
        PopoverPresentation.shareRows(
            families: families,
            attribution: attribution(total: total, attributed: attributed))
    }

    /// The section is labelled "adds up to 100%". That has to survive rounding, not
    /// nearly survive it — the label is a promise the user can check.
    @Test("The whole numbers shown add to exactly 100")
    func sharesSumToExactlyOneHundred() {
        let families = [
            familyRow("Xcode", percent: 412, members: (1...14).map { record($0, command: "xc") }),
            familyRow("Spotlight", percent: 84, members: [record(20, command: "mds")]),
            familyRow("Safari", percent: 56, members: [record(21, command: "Safari")]),
            familyRow("Photos", percent: 28, members: [record(22, command: "Photos")]),
            familyRow("Notes", percent: 7, members: [record(23, command: "Notes")]),
        ]
        let rows = shares(families, total: 940, attributed: 587)
        #expect(rows.reduce(0) { $0 + $1.percentOfBusy } == 100)
    }

    /// Awkward thirds are the classic way a rounded list lands on 99 or 101.
    @Test("Largest-remainder rounding still totals 100")
    func roundingIsLargestRemainder() {
        let whole = PopoverPresentation.wholePercents([1, 1, 1], total: 3)
        #expect(whole.reduce(0, +) == 100)
        #expect(whole.sorted() == [33, 33, 34])
    }

    @Test("Unattributed system activity is a peer row, not a footnote")
    func unattributedIsAPeer() {
        let families = [familyRow("Xcode", percent: 400, members: [record(1, command: "xc")])]
        let rows = shares(families, total: 900, attributed: 400)
        let unattributed = rows.first { $0.kind == .unattributed }
        #expect(unattributed != nil)
        #expect(unattributed?.percentOfBusy == 56)
    }

    /// Present even at zero: an absent row would read as "everything is accounted
    /// for", which is a different claim from "nothing was unattributable".
    @Test("Unattributed is listed even when it is zero")
    func unattributedSurvivesAtZero() {
        let families = [familyRow("Xcode", percent: 100, members: [record(1, command: "xc")])]
        let rows = shares(families, total: 100, attributed: 100)
        #expect(rows.contains { $0.kind == .unattributed && $0.percentOfBusy == 0 })
        #expect(rows.reduce(0) { $0 + $1.percentOfBusy } == 100)
    }

    /// Truncation must not be allowed to break the sum any more than permissions are.
    @Test("Families beyond the listed few are folded into a residual row")
    func residualKeepsTheSumHonest() {
        let families = (1...8).map {
            familyRow("App \($0)", percent: 50, members: [record(pid_t($0), command: "a")])
        }
        let rows = shares(families, total: 400, attributed: 400)
        #expect(rows.contains { $0.kind == .other })
        #expect(rows.reduce(0) { $0 + $1.percentOfBusy } == 100)
        #expect(rows.last?.kind == .other)
    }

    @Test("Nothing is claimed when no CPU was busy")
    func noBusyTimeMeansNoShares() {
        #expect(shares([], total: 0, attributed: 0).isEmpty)
    }

    @Test("Rows carry the process count and the partial marker")
    func rowsCarryQualifiers() {
        let members = (1...14).map { record($0, command: "xc", measurable: $0 > 2) }
        let rows = shares(
            [familyRow("Xcode", percent: 400, members: members)],
            total: 400, attributed: 400)
        let xcode = rows.first { $0.kind == .application }
        #expect(xcode?.processCount == 14)
        #expect(xcode?.isPartial == true)
    }
}

@Suite("Reconciling the two conventions, and the standing promises")
struct IncidentFooterTests {
    /// FR-004: the convention does not vary by surface. Percentages of CPU are
    /// still of one core; the shares above are a different quantity, and saying so
    /// is what keeps it from reading as a second convention.
    @Test("The note explains both figures without introducing a second convention")
    func conventionsAreReconciled() {
        let note = PopoverPresentation.conventionReconciliation(
            leaderName: "Xcode", leaderPercentOfOneCore: 412,
            topology: CoreTopology(logical: 10, performance: 6, efficiency: 4))
        #expect(note.contains("412%"))
        #expect(note.contains("of one core"))
        #expect(note.contains("10"))
        #expect(note.contains("add up to 100%"))
    }

    /// FR-037, stated at the moment a user is most likely to fear otherwise.
    @Test("The standing line promises no process control")
    func controlAssuranceIsExplicit() {
        let line = PopoverPresentation.controlAssurance
        #expect(line.contains("doesn't quit or pause"))
        #expect(line.contains("unsaved work"))
    }

    @Test("The show action names the application")
    func showActionNamesTheApp() {
        #expect(PopoverPresentation.showActionTitle(for: "Xcode") == "Show Xcode")
    }

    /// FR-015: muting suppresses the interruption, never the monitoring. A user who
    /// muted and then found no history would be right to feel misled.
    @Test("A mute states that monitoring continues")
    func muteStatusSaysMonitoringContinues() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let status = PopoverPresentation.muteStatus(
            MuteState(until: now.addingTimeInterval(30 * 60)), now: now)
        #expect(status?.contains("30 min") == true)
        #expect(status?.contains("Monitoring is still running") == true)
    }

    @Test("No mute, no status line")
    func noMuteNoStatus() {
        #expect(PopoverPresentation.muteStatus(.notMuted, now: Date()) == nil)
    }

    @Test("Every mute choice has a readable title",
          arguments: PopoverPresentation.muteChoices)
    func muteChoicesAreReadable(minutes: Int) {
        let title = PopoverPresentation.muteChoiceTitle(minutes: minutes)
        #expect(!title.isEmpty)
        #expect(!title.contains("240 minutes"))
    }
}
