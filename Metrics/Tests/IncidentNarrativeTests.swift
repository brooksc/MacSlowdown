import Foundation
import Testing

@testable import Metrics

/// What an incident is *about*, and what may therefore be said about it (TASK-82).
///
/// The defect these tests defend against was observed on screen on 2026-08-09. The
/// Now banner read:
///
///     Repeated unexpected quits for 27 minutes, 51 seconds
///     Calculated. 15% of busy CPU could not be attributed to any process…
///     Likely, high confidence. Xcode was the largest measurable contributor…
///
/// Every figure in it was real. None of it was about the incident. `IncidentDetailView`
/// already suppressed the same narrative for the same episode, so the product
/// described one event two ways depending on which screen you were looking at — and
/// nothing failed, because each surface was locally correct.
///
/// So these tests are written against the **rule**, not against the two call sites:
/// if `IncidentNarrative` ever stops deciding this, they fail.

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

private func pattern(
    _ command: String = "yes",
    exits: Int = 30,
    from: TimeInterval = 0,
    to: TimeInterval = 60,
    confidence: Confidence = .moderate
) -> RelaunchPattern {
    RelaunchPattern(
        command: command, exits: exits,
        firstAt: origin.addingTimeInterval(from), lastAt: origin.addingTimeInterval(to),
        confidence: confidence)
}

/// An attribution that names a busy application, exactly as the observed incident
/// carried one. The point of every test below is that this being present changes
/// nothing about how a lifecycle episode is described.
private func busyXcode(unattributed: Double = 200) -> IncidentAttribution {
    IncidentAttribution(
        sample: AttributionSample(
            applications: [IncidentContributor(
                applicationID: "/Applications/Xcode.app", displayName: "Xcode",
                peakPercentOfOneCore: 671)],
            totalBusyPercentOfOneCore: 900,
            attributedPercentOfOneCore: 900 - unattributed,
            unattributedPercentOfOneCore: unattributed,
            logicalCoreCount: 8),
        at: origin)
}

private func incident(
    conditions: Set<IncidentCondition>,
    findings: [RelaunchPattern] = [],
    attribution: IncidentAttribution? = nil,
    peakMemory: MemoryPressureLevel = .normal
) -> Incident {
    var subject = Incident(
        id: UUID(), beganAt: origin, triggeredAt: origin,
        recoveryStartedAt: nil, closedAt: origin.addingTimeInterval(600),
        conditions: conditions, severity: .high,
        peakCPUBusyFraction: 0.9, peakMemoryPressure: peakMemory,
        lifecycleFindings: findings)
    subject.attribution = attribution
    return subject
}

private func text(_ summary: IncidentSummary) -> String {
    (summary.conclusions + summary.ruledOut).map(\.display).joined(separator: " ")
}

// MARK: - The rule itself

@Suite("An incident knows what it is about")
struct IncidentNarrativeRuleTests {
    @Test("Every resource condition produces a resource narrative")
    func resourceConditionsAreResourceNarratives() {
        for condition in IncidentCondition.allCases where condition.isResourceCondition {
            #expect(incident(conditions: [condition]).narrative == .resource)
        }
    }

    @Test("Repeated quits alone produce a lifecycle narrative")
    func lifecycleAlone() {
        let subject = incident(conditions: [.repeatedApplicationQuits], findings: [pattern()])
        #expect(subject.narrative == .applicationLifecycle)
        #expect(!subject.narrative.narratesResourceAttribution)
    }

    /// A resource condition alongside the quits is still a resource episode: the
    /// machine really did run short of something, and saying so is not a
    /// distraction. Only the lifecycle-*only* case suppresses the account.
    @Test("Quits alongside a resource condition stay a resource narrative")
    func mixedIsResource() {
        let subject = incident(
            conditions: [.repeatedApplicationQuits, .cpuSaturation], findings: [pattern()])
        #expect(subject.narrative == .resource)
    }

    /// An incident with no conditions at all cannot be narrated as a resource one.
    /// The safe direction: withhold a CPU account rather than volunteer one for an
    /// episode whose conditions we cannot name.
    @Test("No conditions is not a resource narrative")
    func emptyIsNotResource() {
        #expect(incident(conditions: []).narrative == .applicationLifecycle)
    }

    /// Two callers asking for the subject must get the same answer, including when
    /// findings tie. `lifecycleFindings` is sorted on exit count alone, which leaves
    /// equal counts in whatever order the merge dictionary produced.
    @Test("The lifecycle subject is the most-exiting command, deterministically")
    func subjectIsDeterministic() {
        let subject = incident(
            conditions: [.repeatedApplicationQuits],
            findings: [pattern("zsh", exits: 4), pattern("yes", exits: 9)])
        #expect(subject.lifecycleSubject?.command == "yes")

        // A tie is broken by the earlier episode, then by the command, so the two
        // orderings of the same evidence cannot name different processes.
        let tieA = incident(
            conditions: [.repeatedApplicationQuits],
            findings: [pattern("zsh", exits: 4, from: 30), pattern("yes", exits: 4, from: 0)])
        let tieB = incident(
            conditions: [.repeatedApplicationQuits],
            findings: [pattern("yes", exits: 4, from: 0), pattern("zsh", exits: 4, from: 30)])
        #expect(tieA.lifecycleSubject?.command == "yes")
        #expect(tieB.lifecycleSubject?.command == "yes")
    }

    @Test("A resource incident has no lifecycle subject to name")
    func resourceHasNoSubject() {
        #expect(incident(conditions: [.cpuSaturation]).lifecycleSubject == nil)
    }
}

// MARK: - The summariser

@Suite("A lifecycle incident is not narrated as a CPU problem")
struct LifecycleSummaryTests {
    /// The observed banner, reproduced: a lifecycle-only incident that nonetheless
    /// recorded a busy Xcode. Before TASK-82 this produced the unattributable share
    /// and a high-confidence contributor claim.
    @Test("No CPU attribution appears for a lifecycle-only incident")
    func noCPUNarrative() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(
                conditions: [.repeatedApplicationQuits],
                findings: [pattern()],
                attribution: busyXcode()),
            attribution: nil)
        let account = text(summary)

        #expect(!account.contains("busy CPU"))
        #expect(!account.contains("largest measurable contributor"))
        #expect(!account.contains("Xcode"))
        #expect(!account.contains("of one core"))
        #expect(summary.hypotheses.isEmpty, "we cannot see why a process ended")
    }

    /// The live reading is the other door into the same narrative, and the observed
    /// banner may have come through either. Both are shut.
    @Test("A live attribution cannot narrate a lifecycle incident either")
    func liveAttributionIsAlsoSuppressed() {
        let live = CPUAttribution(
            totalBusyPercentOfOneCore: 900, attributedPercentOfOneCore: 700,
            unattributedPercentOfOneCore: 200,
            contributors: [ProcessCPUUsage(
                identity: ProcessIdentity(pid: 1, startTime: 1),
                command: "Xcode", percentOfOneCore: 671, residentBytes: 1 << 30)],
            protectedProcesses: [], logicalCoreCount: 8)
        let summary = IncidentSummarizer.summarize(
            incident: incident(conditions: [.repeatedApplicationQuits], findings: [pattern()]),
            attribution: live)
        #expect(!text(summary).contains("Xcode"))
        #expect(!text(summary).contains("busy CPU"))
    }

    @Test("The process that kept exiting is named, and named as a process")
    func namesTheSubject() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(
                conditions: [.repeatedApplicationQuits],
                findings: [pattern("yes", exits: 30)],
                attribution: busyXcode()),
            attribution: nil)
        let account = text(summary)

        #expect(account.contains("The process “yes”"))
        #expect(account.contains("exited 30 times"))
        // Never at the head of a clause as a bare word.
        #expect(!account.contains("yes exited"))
    }

    /// FR-046's caveat travels from its single source, so the framework and the
    /// screen cannot come to say different things about what a quit means.
    @Test("The hang limitation is stated from its one home")
    func statesTheHangLimitation() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(conditions: [.repeatedApplicationQuits], findings: [pattern()]),
            attribution: nil)
        #expect(text(summary).contains(RelaunchPattern.limitation))
    }

    @Test("Nothing in a lifecycle account implies a hang or a crash")
    func neverClaimsAHang() {
        let account = text(IncidentSummarizer.summarize(
            incident: incident(
                conditions: [.repeatedApplicationQuits], findings: [pattern()],
                attribution: busyXcode()),
            attribution: nil)).lowercased()
        for forbidden in [
            "crash", "hang", "hung", "froze", "frozen", "unresponsive", "beachball",
        ] {
            #expect(!account.contains(forbidden), "\(forbidden) is not observable")
        }
    }

    /// Criterion #3, and the constraint TASK-71 set for itself. Suppressing the CPU
    /// account must not become the opposite claim.
    @Test("Suppressing the resource account is not a clean bill of health")
    func notObservedIsNotAnAssertion() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(conditions: [.repeatedApplicationQuits], findings: [pattern()]),
            attribution: nil)
        let ruledOut = summary.ruledOut.map(\.text).joined(separator: " ")

        #expect(ruledOut.contains("not a finding that the machine was fine"))
        #expect(ruledOut.contains("nothing here rules a resource cause out"))
        // The flat denials a resource incident makes are exactly what must not be
        // volunteered here.
        #expect(!ruledOut.contains("Not a memory problem"))
        #expect(!ruledOut.contains("Not a storage problem"))
        #expect(!ruledOut.contains("Not thermal throttling"))
    }

    @Test("Every statement in a lifecycle summary is still well formed")
    func wellFormed() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(
                conditions: [.repeatedApplicationQuits], findings: [pattern()],
                attribution: busyXcode()),
            attribution: nil)
        #expect(summary.isWellFormed)
        #expect(summary.headline.contains("Repeated unexpected quits"))
    }
}

@Suite("A resource incident is unaffected")
struct ResourceSummaryIsUnchangedTests {
    @Test("The CPU narrative still appears for a resource incident")
    func resourceStillNarrated() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(conditions: [.cpuSaturation], attribution: busyXcode()),
            attribution: nil)
        let account = text(summary)
        #expect(account.contains("Xcode was the largest measurable contributor"))
        #expect(account.contains("could not be attributed"))
        #expect(account.contains("Not a memory problem"))
    }

    /// The mixed case: both findings are real and the reader needs both names. The
    /// CPU account is legitimate here, *and* the process that kept exiting is still
    /// named — the list and the detail must not have to pick one.
    @Test("A mixed incident names the busy application and the quitting process")
    func mixedNamesBoth() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(
                conditions: [.cpuSaturation, .repeatedApplicationQuits],
                findings: [pattern("yes", exits: 30)],
                attribution: busyXcode()),
            attribution: nil)
        let account = text(summary)
        #expect(account.contains("Xcode was the largest measurable contributor"))
        #expect(account.contains("The process “yes”"))
    }

    /// The rule, asserted as a rule: whether a CPU account appears is decided by
    /// `IncidentNarrative` and by nothing else, across every combination of
    /// conditions. This is what stops a third surface re-deriving it.
    @Test("The presence of a CPU account tracks the narrative exactly")
    func accountTracksTheNarrative() {
        for conditions in IncidentCondition.allCases.map({ Set([$0]) })
            + [[], [.cpuSaturation, .repeatedApplicationQuits]] {
            let subject = incident(
                conditions: conditions, findings: [pattern()], attribution: busyXcode())
            let mentionsCPUAttribution = text(IncidentSummarizer.summarize(
                incident: subject, attribution: nil)).contains("largest measurable contributor")
            #expect(
                mentionsCPUAttribution == subject.narrative.narratesResourceAttribution,
                "conditions \(conditions) disagreed with the narrative rule")
        }
    }
}

// MARK: - Naming a command as a subject

@Suite("A command is not a noun")
struct SentenceSubjectTests {
    /// "yes quit unexpectedly 30 times in 1 minute", seen on screen. The sentence
    /// falls apart before the verb.
    @Test("A bare command is introduced as a process")
    func bareCommand() {
        #expect(ProcessNaming.sentenceSubject(command: "yes") == "the process “yes”")
        #expect(
            ProcessNaming.sentenceSubject(command: "yes", capitalized: true)
                == "The process “yes”")
    }

    /// A rule about command-named subjects, not a special case for one command.
    @Test("Commands that are also English words all get the same treatment")
    func everydayWords() {
        for command in ["yes", "sh", "find", "open", "who", "top", "make", "sleep"] {
            #expect(ProcessNaming.sentenceSubject(command: command).contains("“\(command)”"))
        }
    }

    @Test("A real application name needs no scaffolding")
    func applicationName() {
        #expect(
            ProcessNaming.sentenceSubject(command: "Xcode", applicationName: "Xcode") == "Xcode")
        #expect(
            ProcessNaming.sentenceSubject(command: "yes", applicationName: "") == "the process “yes”",
            "an empty name is not a name")
    }

    /// FR-002: a `p_comm` fragment is shown as a fragment. The ellipsis says the
    /// kernel cut it, and the surrounding words say it is a command rather than
    /// what the application is called.
    @Test("A truncated command is marked as truncated")
    func truncatedCommand() {
        let subject = ProcessNaming.sentenceSubject(command: "BackgroundShortc")
        #expect(subject == "the process “BackgroundShortc…”")
        #expect(
            ProcessNaming.sentenceSubjectAccessibilityLabel(command: "BackgroundShortc")
                .contains(ProcessNaming.truncationNote),
            "an ellipsis conveys nothing to VoiceOver")
    }

    @Test("The spoken form drops the scaffolding for a named application")
    func spokenApplicationName() {
        #expect(
            ProcessNaming.sentenceSubjectAccessibilityLabel(
                command: "BackgroundShortc", applicationName: "Shortcuts") == "Shortcuts")
    }
}
