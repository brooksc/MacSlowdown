import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// Which application an incident row is about (TASK-82, FR-002).
///
/// Observed on screen 2026-08-09, on one incident, at the same moment:
///
///   - the incidents list said **"Repeated unexpected quits — Xcode"**
///   - the detail inspector said **"yes quit unexpectedly 30 times in 1 minute"**
///
/// Both were reporting a real measurement. `IncidentsView` read
/// `incident.attribution?.leadingApplication` — the largest *CPU* contributor —
/// for every row, while `RepeatedQuitReport` read the relaunch pattern's command.
/// For a lifecycle episode those are routinely different processes: Xcode was busy,
/// `yes` was the thing exiting.
///
/// The subject rule now lives on `IncidentHistory.Entry` and the view only adopts
/// it, so these tests hold the rule rather than the rendering.

private let origin = Date(timeIntervalSince1970: 1_770_000_000)

private func pattern(
    _ command: String, exits: Int = 30, confidence: Confidence = .moderate
) -> RelaunchPattern {
    RelaunchPattern(
        command: command, exits: exits, firstAt: origin,
        lastAt: origin.addingTimeInterval(60), confidence: confidence)
}

private func busyXcode() -> IncidentAttribution {
    IncidentAttribution(
        sample: AttributionSample(
            applications: [IncidentContributor(
                applicationID: "/Applications/Xcode.app", displayName: "Xcode",
                peakPercentOfOneCore: 678)],
            totalBusyPercentOfOneCore: 900,
            attributedPercentOfOneCore: 240,
            unattributedPercentOfOneCore: 660,
            logicalCoreCount: 8),
        at: origin)
}

private func incident(
    conditions: Set<IncidentCondition>,
    findings: [RelaunchPattern] = [],
    attribution: IncidentAttribution? = nil
) -> Incident {
    var subject = Incident(
        id: UUID(), beganAt: origin, triggeredAt: origin,
        recoveryStartedAt: nil, closedAt: origin.addingTimeInterval(600),
        conditions: conditions, severity: .high,
        peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal,
        lifecycleFindings: findings)
    subject.attribution = attribution
    return subject
}

@Suite("An incident row names the right application")
struct IncidentRowSubjectTests {
    /// The observed defect, as a test.
    @Test("A lifecycle incident is about the process that quit, not the busy one")
    func lifecycleSubjectIsTheQuittingProcess() {
        let entry = IncidentHistory.Entry(incident(
            conditions: [.repeatedApplicationQuits],
            findings: [pattern("yes")],
            attribution: busyXcode()))

        #expect(entry.subject?.command == "yes")
        #expect(entry.subject?.applicationName == nil)
        #expect(entry.subject?.text == "yes")
        #expect(entry.subject?.sentenceTextAtStart == "The process “yes”")
    }

    /// The list and the detail must reach the same name from the same incident.
    /// This is the assertion that the two surfaces cannot diverge again: both are
    /// asked for the same episode and their answers are compared.
    @Test("The list row and the repeated-quit report name the same process")
    func listAndDetailAgree() {
        let subject = incident(
            conditions: [.repeatedApplicationQuits],
            findings: [pattern("yes")],
            attribution: busyXcode())
        let report = RepeatedQuitReport.build(
            pattern: pattern("yes"), lifecycle: [], now: origin)

        #expect(IncidentHistory.Entry(subject).subject?.text == report.command)
        #expect(IncidentHistory.Entry(subject).subject?.sentenceText == report.subject)
    }

    @Test("A resource incident is still about the largest measurable contributor")
    func resourceSubjectIsTheContributor() {
        let entry = IncidentHistory.Entry(incident(
            conditions: [.cpuSaturation], attribution: busyXcode()))
        #expect(entry.subject?.applicationName == "Xcode")
        #expect(entry.subject?.text == "Xcode")
    }

    /// A resource condition alongside the quits: the CPU leader is a legitimate
    /// subject there, because the machine really did run short of something.
    @Test("A mixed incident is about the busy application")
    func mixedIsAboutTheContributor() {
        let entry = IncidentHistory.Entry(incident(
            conditions: [.cpuSaturation, .repeatedApplicationQuits],
            findings: [pattern("yes")],
            attribution: busyXcode()))
        #expect(entry.subject?.applicationName == "Xcode")
    }

    @Test("An incident that recorded nothing names nobody")
    func nothingRecordedNamesNobody() {
        #expect(IncidentHistory.Entry(incident(conditions: [.cpuSaturation])).subject == nil)
    }

    /// A standalone relaunch row — one the tracker holds that no incident covers.
    @Test("A standalone relaunch row names its command as a process")
    func standaloneRow() {
        let entry = IncidentHistory.Entry(pattern("yes"))
        #expect(entry.subject?.sentenceTextAtStart == "The process “yes”")
    }
}

@Suite("A p_comm fragment is shown as a fragment")
struct IncidentRowTruncationTests {
    /// The observed row read "Repeated unexpected quits — BackgroundShortc…". The
    /// ellipsis was there; nothing said the kernel had cut the name rather than the
    /// interface, and it was presented in the position an application's name
    /// occupies (FR-002). `p_comm` is 16 bytes.
    @Test("A 16-byte command is marked as shortened")
    func truncatedCommandIsMarked() {
        let entry = IncidentHistory.Entry(incident(
            conditions: [.repeatedApplicationQuits],
            findings: [pattern("BackgroundShortc")]))

        #expect(entry.subject?.isShortenedCommand == true)
        #expect(entry.subject?.text == "BackgroundShortc…")
        #expect(entry.subject?.sentenceText == "the process “BackgroundShortc…”")
        #expect(entry.subject?.accessibilityText.contains(ProcessNaming.truncationNote) == true)
    }

    @Test("A short command is not marked")
    func shortCommandIsNotMarked() {
        let entry = IncidentHistory.Entry(incident(
            conditions: [.repeatedApplicationQuits], findings: [pattern("yes")]))
        #expect(entry.subject?.isShortenedCommand == false)
        #expect(entry.subject?.accessibilityText == "yes")
    }

    /// Under-reports rather than guessing: grouping may itself have fallen back to
    /// a labelled command, and by the time a display name reaches a row the
    /// evidence for that is gone.
    @Test("A resolved application name is taken at face value")
    func resolvedNameIsNotSecondGuessed() {
        let entry = IncidentHistory.Entry(incident(
            conditions: [.cpuSaturation], attribution: busyXcode()))
        #expect(entry.subject?.isShortenedCommand == false)
    }
}

@Suite("The verdict paragraph follows the same rule")
struct IncidentVerdictSubjectTests {
    private func liveAttribution() -> CPUAttribution {
        CPUAttribution(
            totalBusyPercentOfOneCore: 900, attributedPercentOfOneCore: 700,
            unattributedPercentOfOneCore: 200,
            contributors: [ProcessCPUUsage(
                identity: ProcessIdentity(pid: 1, startTime: 1),
                command: "Xcode", percentOfOneCore: 678, residentBytes: 1 << 30)],
            protectedProcesses: [], logicalCoreCount: 8)
    }

    @Test("A lifecycle verdict names the process that exited, not the busiest one")
    func lifecycleVerdict() {
        let paragraph = IncidentVerdict.paragraph(
            incident: incident(
                conditions: [.repeatedApplicationQuits], findings: [pattern("yes")]),
            attribution: liveAttribution(),
            duration: "10 minutes")
        #expect(!paragraph.contains("Xcode"))
        #expect(!paragraph.contains("largest single user of CPU"))
        #expect(paragraph.contains("The process “yes” exited 30 times"))
    }

    @Test("A resource verdict still names the largest single user of CPU")
    func resourceVerdict() {
        let paragraph = IncidentVerdict.paragraph(
            incident: incident(conditions: [.cpuSaturation]),
            attribution: liveAttribution(),
            duration: "10 minutes")
        #expect(paragraph.contains("Xcode was the largest single user of CPU"))
    }
}

@Suite("A repeated-quit report reads as a sentence")
struct RepeatedQuitSubjectTests {
    /// "yes quit unexpectedly 30 times in 1 minute" — the command was right and the
    /// sentence was unreadable.
    @Test("A command subject is introduced rather than dropped in bare")
    func commandHeadline() {
        let report = RepeatedQuitReport.build(
            pattern: pattern("yes"), lifecycle: [], now: origin)
        #expect(report.headline.hasPrefix("The process “yes” quit unexpectedly"))
    }

    @Test("A named application still reads plainly")
    func namedHeadline() {
        let report = RepeatedQuitReport.build(
            pattern: pattern("Final Cut Pro"), displayName: "Final Cut Pro",
            lifecycle: [], now: origin)
        #expect(report.headline.hasPrefix("Final Cut Pro quit unexpectedly"))
    }
}
