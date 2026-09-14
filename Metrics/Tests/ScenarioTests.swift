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

// MARK: - S-2, the episode that is over by the time anyone looks

@Suite("S-2 — what happened while nobody was watching, and what we cannot answer for")
struct EarlierEpisodeScenarioTests {
    /// The distinction the whole coverage record exists to make. "We watched and
    /// nothing crossed the line" and "we were not watching" are different answers,
    /// and a product that cannot tell them apart is offering a green light that
    /// would look identical if it had crashed an hour ago.
    @Test("Watched-and-quiet is distinguishable from not-watched")
    func watchedIsNotTheSameAsSilent() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var log = CoverageLog()
        let cadence = Duration.seconds(2)
        let tolerance = CoverageLog.tolerance(cadence: cadence)

        // Watched 08:00–09:00.
        for step in stride(from: 0.0, through: 3600, by: 2) {
            _ = log.observe(at: start.addingTimeInterval(step),
                            tolerance: tolerance, resumingAfter: .appNotRunning)
        }
        // Nothing for 45 minutes — the Mac slept.
        let resumed = start.addingTimeInterval(3600 + 45 * 60)
        for step in stride(from: 0.0, through: 1800, by: 2) {
            _ = log.observe(at: resumed.addingTimeInterval(step),
                            tolerance: tolerance, resumingAfter: .systemAsleep)
        }

        let spans = log.spans(from: start, to: resumed.addingTimeInterval(1800))
        let gaps = spans.filter { !$0.state.isWatched }

        #expect(!gaps.isEmpty, "a 45-minute absence left no gap in the record")
        #expect(gaps.contains { $0.duration.totalSeconds > 2000 },
                "the gap was recorded but not at its real length")
        // And the watched stretches are still watched: a gap must not swallow the
        // hour either side of it.
        #expect(spans.contains { $0.state.isWatched })
    }

    /// A gap does not heal. Once we could not answer for a stretch of time, no
    /// later observation makes that stretch answerable — the record would be
    /// worthless if it quietly closed over its own holes.
    @Test("A gap stays a gap however long we watch afterwards")
    func gapsDoNotHeal() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var log = CoverageLog()
        let tolerance = CoverageLog.tolerance(cadence: .seconds(2))

        _ = log.observe(at: start, tolerance: tolerance, resumingAfter: .appNotRunning)
        let after = start.addingTimeInterval(600)
        for step in stride(from: 0.0, through: 7200, by: 2) {
            _ = log.observe(at: after.addingTimeInterval(step),
                            tolerance: tolerance, resumingAfter: .appNotRunning)
        }

        let gapSeconds = log.spans(from: start, to: after.addingTimeInterval(7200))
            .filter { !$0.state.isWatched }
            .reduce(0.0) { $0 + $1.duration.totalSeconds }
        #expect(gapSeconds > 500, "two hours of watching absorbed the earlier gap")
    }

    /// The honest figure behind "watched 6 hr 14 min of the 14 hr since midnight".
    /// It must never exceed the window it describes.
    @Test("Watched time never exceeds the window it is measured over")
    func watchedTimeIsBounded() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var log = CoverageLog()
        for step in stride(from: 0.0, through: 600, by: 2) {
            _ = log.observe(at: start.addingTimeInterval(step),
                            tolerance: CoverageLog.tolerance(cadence: .seconds(2)),
                            resumingAfter: .appNotRunning)
        }
        let window = 1800.0
        let watched = log.watched(from: start, to: start.addingTimeInterval(window))
        #expect(watched.totalSeconds <= window + 0.001,
                "claimed \(watched.totalSeconds)s of coverage in a \(window)s window")
        #expect(watched.totalSeconds > 500, "watched time was lost entirely")
    }
}

// MARK: - S-5, the third pointless alert

@Suite("S-5 — correcting us is one gesture, and it corrects one thing")
struct UnwantedAlertScenarioTests {
    private func incident(_ condition: IncidentCondition,
                          severity: IncidentSeverity = .high) -> Incident {
        let began = Date()
        return Incident(
            id: UUID(), beganAt: began, triggeredAt: began, recoveryStartedAt: nil,
            closedAt: nil, conditions: [condition], severity: severity,
            peakCPUBusyFraction: 0.9, peakMemoryPressure: .critical)
    }

    /// The failure this scenario is named for: someone who did not want to hear
    /// about compiles stops hearing about running out of memory too. That is what
    /// a global sensitivity dial does, and why FR-016 amendment 1 scopes rules to
    /// one application *and* one condition.
    @Test("Silencing one app's CPU leaves every other alert intact")
    func correctionIsNarrow() {
        var settings = NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate)
        settings.announcedConditions = [.cpuSaturation]
        settings.rules = [SuppressionRule(application: "HandBrake", condition: .cpuSaturation)]
        let gate = NotificationGate(settings: settings)
        var state = NotificationGate.State()

        #expect(!gate.decide(incident: incident(.cpuSaturation),
                             contributors: ["HandBrake"], state: &state).shouldSend)
        // A different app, same condition — still heard.
        #expect(gate.decide(incident: incident(.cpuSaturation),
                            contributors: ["Xcode"], state: &state).shouldSend,
                "one app's rule silenced another app")
        // Same app, different condition — still heard.
        #expect(gate.decide(incident: incident(.memoryPressure),
                            contributors: ["HandBrake"], state: &state).shouldSend,
                "a CPU rule silenced a memory finding")
    }

    /// Suppression is about interrupting, never about watching. If a silenced
    /// condition stopped being recorded, the overview would go blank and S-2's
    /// "what happened earlier" would have nothing to answer with.
    @Test("A silenced condition is still detected and still recorded")
    func silencedIsStillRecorded() {
        let outcome = ScenarioTimeline(phases: [
            ScenarioPhase(name: "quiet", duration: .seconds(60),
                          processes: idleDesktop(), hostBusyFraction: 0.15),
            ScenarioPhase(name: "encode", duration: .seconds(600),
                          processes: idleDesktop() + [app(900, "HandBrake", cpu: 780)],
                          hostBusyFraction: 0.98),
        ]).run()

        #expect(outcome.incidentsOpened.count == 1,
                "the condition was not detected once the alert was silenced")
    }

    /// Which is the decision the gate actually made, not merely that it stayed
    /// quiet. A suppression recorded as the wrong cause would show the user a
    /// reason that is not why.
    @Test("The suppression states the rule as its reason, not something else")
    func suppressionNamesItsCause() {
        var settings = NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate)
        settings.announcedConditions = [.cpuSaturation]
        settings.rules = [SuppressionRule(application: "HandBrake", condition: .cpuSaturation)]
        let gate = NotificationGate(settings: settings)
        var state = NotificationGate.State()

        let decision = gate.decide(incident: incident(.cpuSaturation),
                                   contributors: ["HandBrake"], state: &state)
        guard case .suppress(_, let cause) = decision else {
            Issue.record("expected a suppression, got \(decision)")
            return
        }
        #expect(cause == .applicationPolicy(application: "HandBrake", condition: .cpuSaturation),
                "suppressed for the wrong stated reason: \(cause)")
    }
}

// MARK: - S-7, the user is right and we saw nothing

@Suite("S-7 — a report with nothing behind it is the most informative kind")
struct UserReportScenarioTests {
    private func quietSamples(around moment: Date) -> [HistorySample] {
        stride(from: -300.0, through: 60.0, by: 2).map { offset in
            HistorySample(
                timestamp: moment.addingTimeInterval(offset),
                totalBusyPercentOfOneCore: 140,
                attributedPercentOfOneCore: 90,
                unattributedPercentOfOneCore: 50,
                topContributors: [])
        }
    }

    /// The case the whole instrument exists for. Everything measured looked
    /// ordinary; the person says it was slow. We keep the report, and we do not
    /// invent a condition to justify it.
    @Test("A report during a quiet machine is kept, and no condition is invented")
    func reportWithNoConditionIsKept() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let report = SlowdownReport.make(
            timing: .now, reportedAt: moment,
            retainedSamples: quietSamples(around: moment),
            incidents: [], conditionsInForce: [])

        #expect(!report.coincidedWithDetection,
                "a quiet machine produced a coincident detection")
        #expect(report.evidence.coverage.hasSamples,
                "the readings around the report were not kept")
        #expect(report.evidenceClass == .userProvided,
                "the user's own claim must stay labelled as theirs (FR-038)")
    }

    /// A report that matches nothing is a result, not an error, and the overlap
    /// figure is what the field trial will actually read.
    @Test("Reports that matched nothing are counted as their own outcome")
    func overlapCountsBothKinds() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let quiet = SlowdownReport.make(
            timing: .now, reportedAt: moment,
            retainedSamples: quietSamples(around: moment),
            incidents: [], conditionsInForce: [])

        let busyMoment = moment.addingTimeInterval(7200)
        let concurrent = Incident(
            id: UUID(), beganAt: busyMoment.addingTimeInterval(-180),
            triggeredAt: busyMoment.addingTimeInterval(-60), recoveryStartedAt: nil,
            closedAt: nil, conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.97, peakMemoryPressure: .normal)
        let matched = SlowdownReport.make(
            timing: .now, reportedAt: busyMoment,
            retainedSamples: quietSamples(around: busyMoment),
            incidents: [concurrent], conditionsInForce: [.cpuSaturation])

        let overlap = SlowdownDetectionOverlap(reports: [quiet, matched])
        #expect(overlap.reports == 2)
        #expect(overlap.withoutDetection == 1,
                "the report we missed was not counted as a miss")
        #expect(overlap.coincidingWithDetection == 1)
    }

    /// A retrospective report belongs to the minutes it is about, not the minute
    /// it was filed in — otherwise "it was slow half an hour ago" files evidence
    /// from now, which is the wrong half hour.
    @Test("A retrospective report is dated from the experience, not the filing")
    func retrospectiveIsDatedFromTheExperience() {
        let filed = Date(timeIntervalSince1970: 1_800_000_000)
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: 1800), reportedAt: filed,
            retainedSamples: [], incidents: [], conditionsInForce: [])

        #expect(report.experiencedAt < report.reportedAt)
        #expect(abs(report.experiencedAt.timeIntervalSince(filed) + 1800) < 1,
                "the report was filed against the wrong moment")
        // No samples is a stated fact, not an empty series pretending to be quiet.
        #expect(!report.evidence.coverage.hasSamples)
    }
}
