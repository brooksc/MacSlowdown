import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

private func incident(
    id: UUID = UUID(),
    severity: IncidentSeverity = .high,
    // **Memory pressure, not CPU saturation.** Since FR-014 amendment 1 a CPU
    // incident is recorded rather than announced, so a CPU fixture would make
    // every test below pass for the wrong reason — suppressed as unannounceable
    // rather than by the muting, Focus or escalation rule each one is about.
    // Memory pressure announces by default, which is what these tests need.
    conditions: Set<IncidentCondition> = [.memoryPressure]
) -> Incident {
    Incident(id: id, beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
             recoveryStartedAt: nil, closedAt: origin.addingTimeInterval(600),
             conditions: conditions, severity: severity,
             peakCPUBusyFraction: 0.95, peakMemoryPressure: .normal)
}

@Suite("Notification policy")
struct NotificationPolicyTests {
    /// FR-014: no more than one notification per incident unless severity
    /// materially increases. An incident that grumbles on must not alert every
    /// sample.
    @Test("An incident is announced once, however many times it is evaluated")
    func announcedOnce() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let ongoing = incident()

        let decisions = (0..<20).map { _ in
            gate.decide(incident: ongoing, at: origin, state: &state)
        }
        #expect(decisions.filter(\.shouldSend).count == 1,
                "an ongoing incident alerted \(decisions.filter(\.shouldSend).count) times")
        #expect(decisions.dropFirst().allSatisfy { $0.reason.contains("already announced") })
    }

    @Test("A material escalation announces again, but only once more")
    func escalationAnnouncesAgain() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let id = UUID()

        #expect(gate.decide(incident: incident(id: id, severity: .high),
                            at: origin, state: &state).shouldSend)
        #expect(!gate.decide(incident: incident(id: id, severity: .high),
                             at: origin, state: &state).shouldSend)

        let escalated = gate.decide(incident: incident(id: id, severity: .severe),
                                    at: origin, state: &state)
        #expect(escalated.shouldSend)
        #expect(escalated.reason.contains("severity rose"))

        #expect(!gate.decide(incident: incident(id: id, severity: .severe),
                             at: origin, state: &state).shouldSend)
    }

    @Test("A drop in severity does not re-announce")
    func deEscalationIsSilent() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let id = UUID()

        _ = gate.decide(incident: incident(id: id, severity: .severe), at: origin, state: &state)
        let quieter = gate.decide(incident: incident(id: id, severity: .high),
                                  at: origin, state: &state)
        #expect(!quieter.shouldSend)
    }

    @Test("A separate incident gets its own notification")
    func separateIncidentsAnnounceSeparately() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        #expect(gate.decide(incident: incident(), at: origin, state: &state).shouldSend)
        #expect(gate.decide(incident: incident(), at: origin, state: &state).shouldSend)
    }

    @Test("Incidents below the chosen severity are recorded but not announced")
    func belowThresholdIsSilent() {
        let gate = NotificationGate(settings: NotificationSettings(minimumSeverity: .severe))
        var state = NotificationGate.State()
        let decision = gate.decide(incident: incident(severity: .high),
                                   at: origin, state: &state)
        #expect(!decision.shouldSend)
        #expect(decision.reason.contains("below the severity"))
    }
}

@Suite("Interruption suppression")
struct InterruptionSuppressionTests {
    /// FR-014: Focus is respected.
    @Test("Focus suppresses the alert and says where to find it")
    func focusSuppresses() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let decision = gate.decide(incident: incident(),
                                   context: InterruptionContext(focusActive: true),
                                   at: origin, state: &state)
        #expect(!decision.shouldSend)
        #expect(decision.reason.contains("Focus"))
        #expect(decision.reason.contains("Incidents"), "must say the finding is not lost")
    }

    /// FR-019, now implementable: TASK-28 measured per-application audio activity
    /// as available with no microphone permission.
    @Test("Active audio defers the alert and names the application")
    func audioDefers() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let decision = gate.decide(
            incident: incident(),
            context: InterruptionContext(audioActive: true, audioApplication: "Zoom"),
            at: origin, state: &state)

        #expect(!decision.shouldSend)
        #expect(decision.reason.contains("microphone") || decision.reason.contains("audio"))
        #expect(decision.reason.contains("Zoom"))
    }

    @Test("Audio deferral can be turned off")
    func audioDeferralConfigurable() {
        let gate = NotificationGate(settings: NotificationSettings(deferDuringAudio: false))
        var state = NotificationGate.State()
        #expect(gate.decide(incident: incident(),
                            context: InterruptionContext(audioActive: true),
                            at: origin, state: &state).shouldSend)
    }

    /// FR-016: an application marked expected suppresses the alert, and the
    /// reason names it so the rule is discoverable rather than mysterious.
    @Test("An expected application suppresses the alert by name")
    func expectedApplicationSuppresses() {
        let gate = NotificationGate(
            settings: NotificationSettings(expectedApplications: ["HandBrake"]))
        var state = NotificationGate.State()
        let decision = gate.decide(incident: incident(), leadingContributor: "HandBrake",
                                   at: origin, state: &state)
        #expect(!decision.shouldSend)
        #expect(decision.reason.contains("HandBrake"))
    }
}

@Suite("Muting")
struct MutingTests {
    /// FR-015: muting suppresses interruption only. Monitoring continues, so the
    /// history is intact when the mute expires.
    @Test("A mute suppresses alerts and reports the time remaining")
    func muteSuppresses() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let mute = MuteState(until: origin.addingTimeInterval(3_600))

        let decision = gate.decide(incident: incident(), mute: mute, at: origin, state: &state)
        #expect(!decision.shouldSend)
        #expect(decision.reason.contains("muted"))
        #expect(decision.reason.contains("59") || decision.reason.contains("60"))
    }

    @Test("A mute expires on its own")
    func muteExpires() {
        let gate = NotificationGate()
        var state = NotificationGate.State()
        let mute = MuteState(until: origin.addingTimeInterval(600))

        #expect(!gate.decide(incident: incident(), mute: mute,
                             at: origin, state: &state).shouldSend)
        #expect(gate.decide(incident: incident(), mute: mute,
                            at: origin.addingTimeInterval(700), state: &state).shouldSend)
    }

    @Test("Remaining time is reported while muted and nil afterwards")
    func remainingTime() {
        let mute = MuteState(until: origin.addingTimeInterval(1_800))
        #expect(mute.isMuted(at: origin))
        #expect(mute.remaining(at: origin)?.totalSeconds == 1_800)
        #expect(!mute.isMuted(at: origin.addingTimeInterval(1_801)))
        #expect(mute.remaining(at: origin.addingTimeInterval(1_801)) == nil)
    }

    @Test("Not muting is the default")
    func notMutedByDefault() {
        #expect(!MuteState.notMuted.isMuted(at: origin))
    }
}

@Suite("Notification copy")
struct NotificationCopyTests {
    @Test("The message names the resource and the contributor without claiming cause")
    func messageIsHonest() {
        let (title, body) = NotificationGate.message(
            for: incident(severity: .severe), leadingContributor: "Xcode")

        #expect(title.contains("Memory pressure"))
        #expect(title.contains("minute"))
        #expect(body.contains("Xcode"))
        #expect(body.lowercased().contains("largest measurable contributor"),
                "must be framed as measurable, not as the cause")

        let everything = (title + " " + body).lowercased()
        for forbidden in ["caused", "because", "fix", "free up", "wasted",
                          "hung", "frozen", "unresponsive"] {
            #expect(!everything.contains(forbidden), "notification claims \(forbidden)")
        }
    }

    @Test("A message without a known contributor still describes the incident")
    func messageWithoutContributor() {
        let (title, body) = NotificationGate.message(
            for: incident(conditions: [.memoryPressure]), leadingContributor: nil)
        #expect(title.contains("Memory pressure"))
        #expect(!body.isEmpty)
        #expect(!body.contains("contributor"))
    }
}

/// FR-014 amendment 1 — what may interrupt, and what is only recorded.
///
/// The rule is not about severity. Severity orders measurements; it says nothing
/// about whether the user can act, and this product used it as though it did. The
/// question is whether a decision plausibly attaches to the condition.
@Suite("Recorded, not announced (FR-014 amendment 1)")
struct RecordedNotAnnouncedTests {
    private func gate() -> (NotificationGate, NotificationGate.State) {
        (NotificationGate(settings: NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate)),
         NotificationGate.State())
    }


    /// The case the amendment exists for. A capped build produces exactly this
    /// incident, and interrupting for it tells the user we misread their work.
    @Test("A CPU incident is recorded and never announced, at any severity")
    func cpuNeverAnnounces() {
        for severity in [IncidentSeverity.moderate, .high, .severe] {
            let (policy, state0) = gate(); var state = state0
            let decision = policy.decide(
                incident: incident(severity: severity, conditions: [.cpuSaturation]),
                state: &state)
            guard case .suppress(_, let cause) = decision else {
                Issue.record("a \(severity) CPU incident announced")
                return
            }
            #expect(cause == .recordedNotAnnounced,
                    "suppressed for the wrong reason at \(severity)")
        }
    }

    /// Something can be closed, and the machine's behaviour will change.
    @Test("Memory pressure and low storage still announce")
    func actionableConditionsAnnounce() {
        for condition in [IncidentCondition.memoryPressure, .lowStorage] {
            let (policy, state0) = gate(); var state = state0
            let decision = policy.decide(
                incident: incident(conditions: [condition]), state: &state)
            #expect(decision.shouldSend, "\(condition.label) stopped announcing")
        }
    }

    /// A mixed incident announces on the strength of the condition that can be
    /// acted on. Suppressing it because CPU happens to be in the set would lose a
    /// memory warning to an unrelated measurement.
    @Test("One announceable condition is enough")
    func mixedIncidentAnnounces() {
        let (policy, state0) = gate(); var state = state0
        let decision = policy.decide(
            incident: incident(conditions: [.cpuSaturation, .memoryPressure]),
            state: &state)
        #expect(decision.shouldSend)
    }

    /// Opting in is the whole reason the CPU default is defensible rather than
    /// simply quieter.
    @Test("A user who asks for CPU alerts gets them")
    func optingInWorks() {
        var settings = NotificationSettings(
            announcesIncidents: true, minimumSeverity: .moderate)
        settings.announcedConditions = [.cpuSaturation]
        let policy = NotificationGate(settings: settings)
        var state = NotificationGate.State()
        #expect(policy.decide(
            incident: incident(conditions: [.cpuSaturation]), state: &state).shouldSend)
    }

    /// Recording is unaffected — the incident still exists, is still stored, and is
    /// still visible. Only the interruption is withheld.
    @Test("Suppression here is about interrupting, never about recording")
    func recordingIsUnaffected() {
        let (policy, state0) = gate(); var state = state0
        let subject = incident(conditions: [.cpuSaturation])
        _ = policy.decide(incident: subject, state: &state)
        #expect(subject.conditions.contains(.cpuSaturation))
        #expect(subject.isOpen || subject.closedAt != nil)
    }

    /// Adding a condition must force a decision about this, rather than silently
    /// inheriting whichever default the enum happens to fall into.
    @Test("Every condition has an explicit answer")
    func everyConditionIsDecided() {
        let announcing = IncidentCondition.allCases.filter(\.announcesByDefault)
        #expect(Set(announcing) == [.memoryPressure, .lowStorage])
    }
}
