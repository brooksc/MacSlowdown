import Darwin
import Foundation
import Testing

@testable import Metrics

/// The situations in `scenarios.md`, as tests.
///
/// Those seven situations are the product's actual claims, and until now every
/// one of them was asserted only in prose. "A capped build must not interrupt
/// you" is the difference between this product being kept and being uninstalled,
/// and nothing checked it.
///
/// Every figure below comes from a measurement in `probe/FINDINGS.md` or from an
/// episode recorded on the owner's machine, not from invention. Where a number is
/// a guess it says so.
///
/// These run deterministically: no real load, no timing, no dependence on how
/// busy the machine is. That is the point — the one pre-existing end-to-end test
/// spawns real `yes` processes, and is skipped in CI for exactly that reason.

// MARK: - Shared shapes

private let me = getuid()
/// Another user. `probe/FINDINGS.md`: measurability is decided by uid, exactly —
/// 229 other-uid processes, 229 denied, no exceptions.
private let other: uid_t = 0

private func app(_ pid: pid_t, _ name: String, cpu: Double,
                 memory: UInt64 = 256 * 1024 * 1024) -> ScriptedProcess {
    ScriptedProcess(pid: pid, command: name, uid: me, ppid: 1,
                    executablePath: "/Applications/\(name).app/Contents/MacOS/\(name)",
                    percentOfOneCore: cpu, residentBytes: memory)
}

private func systemProcess(_ pid: pid_t, _ name: String, cpu: Double) -> ScriptedProcess {
    ScriptedProcess(pid: pid, command: name, uid: other, ppid: 1,
                    executablePath: "/usr/libexec/\(name)", percentOfOneCore: cpu)
}

private func idleDesktop() -> [ScriptedProcess] {
    [app(501, "Safari", cpu: 4), app(502, "Notes", cpu: 0.5),
     systemProcess(90, "WindowServer", cpu: 12)]
}

// MARK: - S-4, the one the product survives or does not

@Suite("S-4 — heavy work started on purpose must not interrupt")
struct ExpectedWorkScenarioTests {
    /// The measured shape of a capped build, from `probe/FINDINGS.md` (TASK-103):
    /// median 63% of the machine busy, peaking at 100%, about four minutes.
    ///
    /// This is the scenario that killed the run-queue amendment and the one
    /// FR-046's false positives trained the owner to distrust. A build looks
    /// exactly like a slowdown to every measurement this product can take.
    private func cappedBuild() -> ScenarioTimeline {
        let building = (0..<6).map { app(700 + $0, "Xcode", cpu: 95) }
        return ScenarioTimeline(phases: [
            ScenarioPhase(name: "before", duration: .seconds(60),
                          processes: idleDesktop(), hostBusyFraction: 0.20),
            ScenarioPhase(name: "build", duration: .seconds(240),
                          processes: idleDesktop() + building, hostBusyFraction: 0.63),
            ScenarioPhase(name: "after", duration: .seconds(120),
                          processes: idleDesktop(), hostBusyFraction: 0.20),
        ])
    }

    /// **The claim the product lives on.** FR-014 amendment 1 makes sustained CPU
    /// recorded rather than announced precisely so this cannot happen.
    @Test("A four-minute capped build sends no notification")
    func buildDoesNotInterrupt() {
        let gate = NotificationGate(settings: NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate))
        let outcome = cappedBuild().run(gate: gate)

        #expect(outcome.notificationsSent.isEmpty,
                "a build interrupted the user: \(outcome.notificationsSent.map(\.reason))")
    }

    /// Not announcing is not the same as not watching, and the distinction is the
    /// whole of FR-014 amendment 1. If a build stopped being *recorded* the
    /// overview would have nothing to show and S-2 would break.
    @Test("The load is still measured and still visible")
    func buildIsStillRecorded() {
        let outcome = cappedBuild().run()
        let during = outcome.frames(inPhase: "build")

        #expect(!during.isEmpty)
        let busiest = during.compactMap(\.attribution).map(\.totalBusyPercentOfOneCore).max() ?? 0
        #expect(busiest > 100, "the build's load never reached the attribution: \(busiest)")
    }

    /// One tap on "this is expected work" must end it permanently, and must not
    /// silence anything else — FR-016 amendment 1. A rule scoped to the app alone
    /// would take memory warnings with it.
    @Test("Marking it expected suppresses CPU for that app and nothing else")
    func expectedRuleIsScoped() {
        var settings = NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate)
        settings.announcedConditions = [.cpuSaturation]   // opt in, to prove the rule bites
        settings.rules = [SuppressionRule(application: "Xcode", condition: .cpuSaturation)]

        let gate = NotificationGate(settings: settings)
        var state = NotificationGate.State()
        let began = Date()

        let cpu = Incident(
            id: UUID(), beganAt: began, triggeredAt: began, recoveryStartedAt: nil,
            closedAt: nil, conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.95, peakMemoryPressure: .normal)
        #expect(!gate.decide(incident: cpu, contributors: ["Xcode"], state: &state).shouldSend,
                "the CPU rule did not suppress")

        let memory = Incident(
            id: UUID(), beganAt: began, triggeredAt: began, recoveryStartedAt: nil,
            closedAt: nil, conditions: [.memoryPressure], severity: .high,
            peakCPUBusyFraction: 0.20, peakMemoryPressure: .critical)
        #expect(gate.decide(incident: memory, contributors: ["Xcode"], state: &state).shouldSend,
                "a CPU rule silenced a memory finding — FR-016 amendment 1")
    }
}

// MARK: - S-1, the slowdown that is real

@Suite("S-1 — a sustained condition is recorded once, and attributed honestly")
struct RealSlowdownScenarioTests {
    /// The episode actually observed on 2026-08-31: roughly 99% of eight cores,
    /// sustained. Recorded in TASK-100 and in the incident store.
    private func sustainedLoad() -> ScenarioTimeline {
        let hogs = (0..<8).map { app(800 + $0, "Renderer", cpu: 98) }
        return ScenarioTimeline(phases: [
            ScenarioPhase(name: "quiet", duration: .seconds(60),
                          processes: idleDesktop(), hostBusyFraction: 0.15),
            ScenarioPhase(name: "slowdown", duration: .seconds(600),
                          processes: idleDesktop() + hogs, hostBusyFraction: 0.99),
            ScenarioPhase(name: "recovered", duration: .seconds(180),
                          processes: idleDesktop(), hostBusyFraction: 0.15),
        ])
    }

    /// **One incident, not several.** The defect TASK-100 fixed was the opposite:
    /// the sustained clock was cleared by any single sub-threshold sample, so an
    /// hour at 99% produced nothing at all. A timeline test is how that stays
    /// fixed without an hour of real load.
    @Test("Ten minutes at 99% opens exactly one incident, and closes it on recovery")
    func oneIncidentThenRecovery() {
        let outcome = sustainedLoad().run()

        #expect(outcome.incidentsOpened.count == 1,
                "expected one incident, got \(outcome.incidentsOpened.count)")
        #expect(outcome.incidentsClosed.count == 1, "the incident never closed")

        #expect(outcome.incidentsOpened.first?.conditions.contains(.cpuSaturation) == true)
    }

    /// The incident is dated from when the condition began, not from when the
    /// sustained threshold elapsed — otherwise a ten-minute episode is recorded as
    /// having started seven minutes in.
    @Test("The incident is dated from the breach, not from the trigger")
    func datedFromTheBreach() throws {
        let outcome = sustainedLoad().run()
        let incident = try #require(outcome.incidentsOpened.first)
        #expect(incident.beganAt < incident.triggeredAt,
                "began and triggered are the same instant; the lead-in was lost")
    }
}

// MARK: - S-3, the load we cannot attribute

@Suite("S-3 — when the load is not ours, we say so rather than blaming an app")
struct UnattributableScenarioTests {
    /// A backup and an indexer: real processes, owned by another user, and denied
    /// identically whether or not we are sandboxed. This is the ~40 points of busy
    /// CPU `probe/FINDINGS.md` says cannot be attributed in any build we can ship.
    @Test("Other-uid load lands in the unattributable share, not on an application")
    func systemLoadIsNotBlamedOnAnApp() throws {
        let outcome = ScenarioTimeline(phases: [
            ScenarioPhase(
                name: "backup",
                duration: .seconds(300),
                processes: idleDesktop() + [
                    systemProcess(200, "backupd", cpu: 340),
                    systemProcess(201, "mds_stores", cpu: 180),
                ],
                hostBusyFraction: 0.92),
        ]).run()

        let attribution = try #require(outcome.frames.compactMap(\.attribution).last)

        // The machine is busy...
        #expect(attribution.totalBusyPercentOfOneCore > 500)
        // ...and most of it is admitted as unattributable rather than pinned on
        // Safari, which is the only measurable thing doing anything.
        #expect(attribution.unattributedPercentOfOneCore
                > attribution.attributedPercentOfOneCore,
                Comment(rawValue: "the unattributable share should dominate: "
                    + "attributed \(attribution.attributedPercentOfOneCore), "
                    + "unattributed \(attribution.unattributedPercentOfOneCore)"))
    }

    /// FR-055's invariant, which a contributor list silently failing to sum would
    /// break. Checked on every frame rather than the last, because the two figures
    /// are read at slightly different instants and the bug this guards against
    /// appeared only under load.
    @Test("The parts always account for the whole")
    func partsSumToTheWhole() {
        let outcome = ScenarioTimeline(phases: [
            ScenarioPhase(name: "mixed", duration: .seconds(120),
                          processes: idleDesktop() + [
                            app(600, "Xcode", cpu: 210),
                            systemProcess(200, "backupd", cpu: 300),
                          ],
                          hostBusyFraction: 0.85),
        ]).run()

        for frame in outcome.frames {
            guard let a = frame.attribution else { continue }
            let parts = a.attributedPercentOfOneCore + a.unattributedPercentOfOneCore
            #expect(abs(parts - a.totalBusyPercentOfOneCore) < 0.01,
                    "parts \(parts) != whole \(a.totalBusyPercentOfOneCore)")
            #expect(a.unattributedPercentOfOneCore >= 0, "negative unattributed share")
        }
    }
}

// MARK: - S-6, the ordinary day

@Suite("S-6 — an idle machine produces nothing at all")
struct QuietMachineScenarioTests {
    /// The most common case by a wide margin, and the one a monitoring tool is
    /// most likely to get wrong by inventing something to report.
    @Test("An hour of ordinary use opens no incident and sends no notification")
    func quietMachineIsQuiet() {
        let gate = NotificationGate(settings: NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate))
        let outcome = ScenarioTimeline(phases: [
            ScenarioPhase(name: "ordinary", duration: .seconds(3600),
                          processes: idleDesktop(), hostBusyFraction: 0.20),
        ]).run(gate: gate)

        #expect(outcome.incidentsOpened.isEmpty)
        #expect(outcome.notificationsSent.isEmpty)
        // And it was genuinely watching, rather than producing nothing because
        // nothing ran: "we watched and saw nothing" is a different claim from
        // "we were not watching" (S-2, and the coverage record).
        #expect(outcome.frames.count > 1000, "the timeline did not actually sample")
    }
}
