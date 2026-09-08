import Foundation
import Testing

@testable import Metrics

/// TASK-69, part 2: what happens to a condition that is already present when the
/// user changes the threshold it is judged against.
///
/// Both failures these cover delay the *same* incident the user tightened settings
/// to catch sooner, and both are silent — the interface would show a slowdown
/// arriving three minutes late with nothing to say why.

private func reading(_ offset: TimeInterval, _ fraction: Double, from start: Date)
    -> IncidentDetector.RetainedCPUReading {
    IncidentDetector.RetainedCPUReading(
        at: start.addingTimeInterval(offset), busyFraction: fraction)
}

/// A 15-minute retained series at a 2 s cadence, all at one busy fraction, ending
/// at `now`. This is the shape `MetricsHistory` actually accumulates.
private func series(endingAt now: Date, busy: Double, seconds: Int = 900)
    -> [IncidentDetector.RetainedCPUReading] {
    stride(from: -seconds, through: 0, by: 2).map {
        IncidentDetector.RetainedCPUReading(
            at: now.addingTimeInterval(Double($0)), busyFraction: busy)
    }
}

@Suite("Changing a threshold while a condition is already breaching")
struct ThresholdChangeTests {

    // MARK: - 1. The accumulated clock is kept

    /// The first failure mode: resetting `breachStart` on a policy change restarts
    /// the sustained-duration clock on a condition that had already been running
    /// for most of it.
    @Test("A policy change does not restart the sustained-duration clock")
    func keepsTheAccumulatedClock() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let start = Date()

        // 170 s of breaching at 0.90, ten seconds short of the 180 s default.
        #expect(detector.observe(
            SystemObservation(at: start, cpuBusyFraction: 0.90), state: &state) == nil)
        #expect(detector.observe(
            SystemObservation(at: start.addingTimeInterval(170), cpuBusyFraction: 0.90),
            state: &state) == nil)

        // The user now *loosens* the duration slightly. Nothing about the condition
        // changed, so the ten seconds still owed must be ten seconds, not 200.
        var loosened = IncidentPolicy.default
        loosened.cpuSustainedDuration = .seconds(200)
        detector.adopt(loosened, state: &state)

        #expect(detector.observe(
            SystemObservation(at: start.addingTimeInterval(190), cpuBusyFraction: 0.90),
            state: &state) == nil)
        guard case .opened(let incident)? = detector.observe(
            SystemObservation(at: start.addingTimeInterval(200), cpuBusyFraction: 0.90),
            state: &state)
        else {
            Issue.record("the accumulated breach was discarded by the policy change")
            return
        }
        #expect(incident.beganAt == start)
        #expect(!incident.beganAtEstablishedFromRetainedHistory)
    }

    @Test("Adopting the same policy changes nothing at all")
    func adoptingTheSamePolicyIsANoOp() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let now = Date()
        _ = detector.observe(SystemObservation(at: now, cpuBusyFraction: 0.90), state: &state)

        #expect(detector.adopt(.default, state: &state,
                               retainedCPU: series(endingAt: now, busy: 0.90)) == false)
        #expect(state.breachStart[.cpuSaturation] == now)
        #expect(state.breachStartFromRetainedHistory.isEmpty)
    }

    // MARK: - 2. Tightening onto a condition that was already there

    /// The failure keeping `breachStart` does not fix. At 0.80 nothing is breaching
    /// the 0.85 default, so `breachStart` is nil. Tightening to 0.75 without looking
    /// back starts the clock from the next observation and delays the incident by
    /// the full three minutes, for a condition that was present the whole time.
    @Test("Tightening onto a present condition opens the incident now, not in three minutes")
    func tighteningUsesRetainedReadings() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let now = Date()

        // Fifteen minutes of 80% capacity: under the default line, so the detector
        // has never recorded a breach start.
        #expect(detector.observe(
            SystemObservation(at: now, cpuBusyFraction: 0.80), state: &state) == nil)
        #expect(state.breachStart[.cpuSaturation] == nil)

        var tightened = IncidentPolicy.default
        tightened.cpuBusyFractionThreshold = 0.75
        #expect(detector.adopt(tightened, state: &state,
                               retainedCPU: series(endingAt: now, busy: 0.80)))

        // The very next observation opens an incident, because the duration was
        // already served by readings that actually happened.
        guard case .opened(let incident)? = detector.observe(
            SystemObservation(at: now.addingTimeInterval(2), cpuBusyFraction: 0.80),
            state: &state)
        else {
            Issue.record("tightening the threshold postponed the incident")
            return
        }
        #expect(incident.beganAt == now.addingTimeInterval(-900))
        #expect(incident.beganAtEstablishedFromRetainedHistory)
    }

    /// The deliberate consequence, stated as a test so it is a decision rather than
    /// a discovery: the incident is dated *before* the settings change. That is what
    /// the readings show, and `startProvenance` is what the interface has to say so.
    @Test("The incident is dated before the settings change, and says why")
    func theIncidentIsDatedBeforeTheChange() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let now = Date()
        var tightened = IncidentPolicy.default
        tightened.cpuBusyFractionThreshold = 0.75
        detector.adopt(tightened, state: &state,
                       retainedCPU: series(endingAt: now, busy: 0.80))

        guard case .opened(let incident)? = detector.observe(
            SystemObservation(at: now, cpuBusyFraction: 0.80), state: &state) else {
            Issue.record("no incident opened")
            return
        }
        #expect(incident.beganAt < now)
        guard let provenance = incident.startProvenance else {
            Issue.record("an incident dated before the change explains nothing")
            return
        }
        #expect(provenance.evidence == .measured)
        #expect(provenance.isWellFormed)
        #expect(provenance.text.contains("already kept"))

        // An ordinary incident carries no such note; the explanation is reserved for
        // the case that needs it.
        let plain = IncidentDetector()
        var plainState = IncidentDetector.State()
        _ = plain.observe(SystemObservation(at: now, cpuBusyFraction: 0.95),
                          state: &plainState)
        guard case .opened(let ordinary)? = plain.observe(
            SystemObservation(at: now.addingTimeInterval(200), cpuBusyFraction: 0.95),
            state: &plainState) else {
            Issue.record("no ordinary incident opened")
            return
        }
        #expect(ordinary.startProvenance == nil)
    }

    // MARK: - 3. Never further back than the readings support

    @Test("Nothing is claimed for a stretch that was never measured")
    func gapsAreNotCountedAsContinuity() {
        let now = Date()
        // Busy for the last minute; busy an hour ago; nothing in between. The app
        // was asleep, or not running. The gap is not evidence.
        let readings = [reading(-3600, 0.90, from: now), reading(-3598, 0.90, from: now)]
            + series(endingAt: now, busy: 0.90, seconds: 60)
        let derived = IncidentDetector.earliestRetainedBreachStart(
            in: readings, threshold: 0.85, maximumSampleGap: .seconds(30))
        #expect(derived == now.addingTimeInterval(-60))
    }

    @Test("A series that never reaches the new threshold yields no start")
    func belowTheNewThresholdClaimsNothing() {
        let now = Date()
        #expect(IncidentDetector.earliestRetainedBreachStart(
            in: series(endingAt: now, busy: 0.50), threshold: 0.75,
            maximumSampleGap: .seconds(30)) == nil)
        #expect(IncidentDetector.earliestRetainedBreachStart(
            in: [], threshold: 0.75, maximumSampleGap: .seconds(30)) == nil)
    }

    /// A machine that recovered and then got busy again is dated from the recovery,
    /// not from the earlier trouble.
    @Test("The run is contiguous — an earlier, separate breach is not joined to it")
    func onlyTheContiguousRunCounts() {
        let now = Date()
        var readings = series(endingAt: now.addingTimeInterval(-100), busy: 0.90, seconds: 200)
        readings.append(reading(-98, 0.10, from: now))  // recovered
        readings += stride(from: -96, through: 0, by: 2).map { reading($0, 0.90, from: now) }

        #expect(IncidentDetector.earliestRetainedBreachStart(
            in: readings, threshold: 0.85, maximumSampleGap: .seconds(30))
            == now.addingTimeInterval(-96))
    }

    /// Loosening must not move the start *forward*: the accumulated clock is kept
    /// whichever way the threshold moved, and `adopt` only ever moves a start back.
    @Test("An existing, earlier breach start is never replaced by a later one")
    func anEarlierStartWins() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let now = Date()
        // Breaching since ten minutes ago.
        _ = detector.observe(
            SystemObservation(at: now.addingTimeInterval(-600), cpuBusyFraction: 0.95),
            state: &state)

        // Retained readings only reach back a minute at this level.
        var readings = series(endingAt: now, busy: 0.95, seconds: 60)
        readings.insert(reading(-62, 0.10, from: now), at: 0)

        var tightened = IncidentPolicy.default
        tightened.cpuBusyFractionThreshold = 0.90
        #expect(detector.adopt(tightened, state: &state, retainedCPU: readings) == false)
        #expect(state.breachStart[.cpuSaturation] == now.addingTimeInterval(-600))
    }

    /// The re-dated start is a claim about *now*. If the condition is not actually
    /// present at the next observation, it has to be dropped rather than left
    /// standing as an incident waiting to open.
    @Test("A re-dated start is discarded the moment a live reading disagrees")
    func aLiveReadingClearsARedatedStart() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let now = Date()
        var tightened = IncidentPolicy.default
        tightened.cpuBusyFractionThreshold = 0.75
        detector.adopt(tightened, state: &state,
                       retainedCPU: series(endingAt: now, busy: 0.80))
        #expect(state.breachStart[.cpuSaturation] != nil)

        #expect(detector.observe(
            SystemObservation(at: now.addingTimeInterval(2), cpuBusyFraction: 0.20),
            state: &state) == nil)
        #expect(state.breachStart[.cpuSaturation] == nil)
        #expect(state.breachStartFromRetainedHistory.isEmpty)
    }

    /// CPU only, and deliberately. Memory pressure and thermal state are not in the
    /// retained series, so there is nothing to look back over — and inventing one
    /// would be the fabricated measurement FR-002 forbids.
    @Test("Only CPU is re-decided; memory pressure starts from the change")
    func memoryPressureIsNotRedated() {
        var detector = IncidentDetector()
        var state = IncidentDetector.State()
        let now = Date()

        var tightened = IncidentPolicy.default
        tightened.memoryPressureSustainedDuration = .seconds(45)
        detector.adopt(tightened, state: &state, retainedCPU: series(endingAt: now, busy: 0.99))

        #expect(state.breachStart[.memoryPressure] == nil)
        // Memory pressure serves its duration from the first observation after the
        // change, which is the honest answer with no history to consult.
        #expect(detector.observe(
            SystemObservation(at: now, cpuBusyFraction: 0.1, memoryPressure: .warning),
            state: &state) == nil)
        guard case .opened(let incident)? = detector.observe(
            SystemObservation(at: now.addingTimeInterval(45), cpuBusyFraction: 0.1,
                              memoryPressure: .warning),
            state: &state) else {
            Issue.record("memory pressure never opened an incident")
            return
        }
        #expect(incident.beganAt == now)
        #expect(!incident.beganAtEstablishedFromRetainedHistory)
    }
}

@Suite("Turning alerts off means no alerts")
struct AnnouncementSwitchTests {
    private func incident(_ severity: IncidentSeverity) -> Incident {
        Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(), recoveryStartedAt: nil,
            // Memory pressure announces by default (FR-014 amendment 1); what
            // this suite is about is the severity floor and the on/off switch.
            closedAt: nil, conditions: [.memoryPressure], severity: severity,
            peakCPUBusyFraction: 0.99, peakMemoryPressure: .normal)
    }

    /// Raising the floor to `.severe` was the old stand-in for "off", and it still
    /// announced severe incidents to a user who had asked for silence.
    @Test("Nothing is announced at any severity when the switch is off")
    func offMeansOff() {
        let gate = NotificationGate(settings: NotificationSettings(announcesIncidents: false))
        var state = NotificationGate.State()
        for severity in [IncidentSeverity.moderate, .high, .severe] {
            let decision = gate.decide(incident: incident(severity), state: &state)
            #expect(!decision.shouldSend)
            #expect(decision.reason.contains("asked not to be told"))
        }
    }

    @Test("On is the default, and still respects the severity floor")
    func onIsTheDefault() {
        #expect(NotificationSettings.default.announcesIncidents)
        let gate = NotificationGate(settings: NotificationSettings(minimumSeverity: .high))
        var state = NotificationGate.State()
        #expect(!gate.decide(incident: incident(.moderate), state: &state).shouldSend)
        #expect(gate.decide(incident: incident(.severe), state: &state).shouldSend)
    }
}
