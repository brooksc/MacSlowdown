import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

private func busy(_ seconds: TimeInterval, _ fraction: Double = 0.95) -> SystemObservation {
    SystemObservation(at: at(seconds), cpuBusyFraction: fraction)
}
private func quiet(_ seconds: TimeInterval) -> SystemObservation {
    SystemObservation(at: at(seconds), cpuBusyFraction: 0.10)
}

/// Drives a detector through a sequence, returning every event it produced.
private func run(
    _ observations: [SystemObservation],
    policy: IncidentPolicy = .default
) -> [IncidentEvent] {
    let detector = IncidentDetector(policy: policy)
    var state = IncidentDetector.State()
    return observations.compactMap { detector.observe($0, state: &state) }
}

@Suite("Incident triggering")
struct IncidentTriggeringTests {
    /// FR-006: no alert for a transient spike shorter than the configured
    /// duration. This is the single most important false-positive guard.
    @Test("A spike shorter than the sustained duration never opens an incident")
    func transientSpikeIsIgnored() {
        // Saturated for 60s against a 180s requirement.
        let events = run((0...6).map { busy(Double($0) * 10) } + [quiet(70)])
        #expect(events.isEmpty, "a 60s spike opened an incident: \(events)")
    }

    @Test("Sustained saturation opens exactly one incident")
    func sustainedSaturationOpens() throws {
        let events = run(stride(from: 0.0, through: 200, by: 20).map { busy($0) })
        let opened = events.filter { if case .opened = $0 { true } else { false } }
        #expect(opened.count == 1, "expected one open, got \(events.count) events")

        guard case .opened(let incident) = try #require(opened.first) else { return }
        #expect(incident.conditions == [.cpuSaturation])
        #expect(incident.isOpen)
        // It began when the breach started, not when it triggered.
        #expect(incident.beganAt == at(0))
        #expect(incident.triggeredAt >= at(180))
    }

    /// FR-011: repeated samples do not create duplicate incidents.
    @Test("Continued saturation never opens a second incident")
    func noDuplicates() {
        let events = run(stride(from: 0.0, through: 600, by: 10).map { busy($0) })
        let opened = events.filter { if case .opened = $0 { true } else { false } }
        #expect(opened.count == 1, "opened \(opened.count) incidents for one continuous slowdown")
    }

    @Test("A breach that resets does not accumulate toward the duration")
    func brokenRunResets() {
        // 100s busy, a dip, then 100s busy: neither run reaches 180s.
        var observations = stride(from: 0.0, through: 100, by: 10).map { busy($0) }
        observations.append(quiet(110))
        observations += stride(from: 120.0, through: 220, by: 10).map { busy($0) }

        let opened = run(observations).filter { if case .opened = $0 { true } else { false } }
        #expect(opened.isEmpty, "a broken run should not accumulate")
    }
}

@Suite("Incident recovery and hysteresis")
struct IncidentRecoveryTests {
    /// FR-011: an incident closes only after recovery hysteresis.
    @Test("A brief dip does not close an open incident")
    func briefDipDoesNotClose() {
        var observations = stride(from: 0.0, through: 200, by: 20).map { busy($0) }
        observations.append(quiet(210))          // dip, 30s of recovery needed... 60s
        observations.append(quiet(230))
        observations += stride(from: 240.0, through: 300, by: 20).map { busy($0) }

        let closed = run(observations).filter { if case .closed = $0 { true } else { false } }
        #expect(closed.isEmpty, "a 30s dip closed the incident before hysteresis elapsed")
    }

    @Test("Sustained recovery closes the incident exactly once")
    func sustainedRecoveryCloses() throws {
        var observations = stride(from: 0.0, through: 200, by: 20).map { busy($0) }
        observations += stride(from: 210.0, through: 320, by: 20).map { quiet($0) }

        let events = run(observations)
        let closed = events.filter { if case .closed = $0 { true } else { false } }
        #expect(closed.count == 1, "expected one close, got \(closed.count)")

        guard case .closed(let incident) = try #require(closed.first) else { return }
        #expect(!incident.isOpen)
        #expect(incident.closedAt != nil)
        // Closed no earlier than the hysteresis period after recovery began.
        let recoveryStart = try #require(incident.recoveryStartedAt)
        let closedAt = try #require(incident.closedAt)
        #expect(closedAt.timeIntervalSince(recoveryStart) >= 60)
    }

    @Test("A relapse during recovery keeps the same incident open")
    func relapseKeepsSameIncident() {
        var observations = stride(from: 0.0, through: 200, by: 20).map { busy($0) }
        observations.append(quiet(220))
        observations.append(busy(240))            // relapse before 60s elapsed
        observations += stride(from: 260.0, through: 400, by: 20).map { quiet($0) }

        let events = run(observations)
        let opened = events.filter { if case .opened = $0 { true } else { false } }
        let closed = events.filter { if case .closed = $0 { true } else { false } }
        #expect(opened.count == 1)
        #expect(closed.count == 1, "the relapse should not have produced a second episode")
    }

    /// FR-011: related signals within the merge window become one episode.
    @Test("A new breach inside the merge window rejoins the previous incident")
    func mergeWindowRejoins() {
        var observations = stride(from: 0.0, through: 200, by: 20).map { busy($0) }
        observations += stride(from: 210.0, through: 290, by: 20).map { quiet($0) }  // closes
        // New sustained breach starting soon after the close.
        observations += stride(from: 300.0, through: 500, by: 20).map { busy($0) }

        let events = run(observations)
        let opened = events.filter { if case .opened = $0 { true } else { false } }
        #expect(opened.count == 1,
                "a breach inside the merge window should rejoin, not open a second incident")
    }

    @Test("A breach well outside the merge window opens a new incident")
    func outsideMergeWindowOpensNew() {
        var observations = stride(from: 0.0, through: 200, by: 20).map { busy($0) }
        observations += stride(from: 210.0, through: 400, by: 20).map { quiet($0) }
        observations += stride(from: 1000.0, through: 1200, by: 20).map { busy($0) }

        let opened = run(observations).filter { if case .opened = $0 { true } else { false } }
        #expect(opened.count == 2)
    }
}

@Suite("Incident conditions and severity")
struct IncidentSeverityTests {
    @Test("Memory pressure alone can open an incident")
    func memoryPressureOpens() throws {
        let observations = stride(from: 0.0, through: 120, by: 15).map {
            SystemObservation(at: at($0), cpuBusyFraction: 0.2, memoryPressure: .warning)
        }
        let opened = run(observations).filter { if case .opened = $0 { true } else { false } }
        #expect(opened.count == 1)
        guard case .opened(let incident) = try #require(opened.first) else { return }
        #expect(incident.conditions == [.memoryPressure])
    }

    @Test("Severity rises with concurrent conditions and never silently falls")
    func severityEscalates() throws {
        var state = IncidentDetector.State()
        let detector = IncidentDetector()

        // Open on CPU alone.
        for seconds in stride(from: 0.0, through: 200, by: 20) {
            _ = detector.observe(busy(seconds), state: &state)
        }
        let initial = try #require(state.current).severity

        // Add critical memory pressure.
        _ = detector.observe(SystemObservation(
            at: at(220), cpuBusyFraction: 0.96, memoryPressure: .critical), state: &state)
        let escalated = try #require(state.current).severity
        #expect(escalated >= initial)
        #expect(escalated == .severe)

        // A calmer sample must not silently downgrade a recorded peak.
        _ = detector.observe(SystemObservation(
            at: at(240), cpuBusyFraction: 0.86, memoryPressure: .normal), state: &state)
        #expect(try #require(state.current).severity == .severe)
        #expect(try #require(state.current).peakMemoryPressure == .critical)
    }

    @Test("Peak CPU is retained rather than replaced by the latest sample")
    func peakRetained() throws {
        var state = IncidentDetector.State()
        let detector = IncidentDetector()
        for seconds in stride(from: 0.0, through: 200, by: 20) {
            _ = detector.observe(busy(seconds, 0.99), state: &state)
        }
        _ = detector.observe(busy(220, 0.86), state: &state)
        #expect(try #require(state.current).peakCPUBusyFraction >= 0.99)
    }
}

@Suite("Incident policy is configurable")
struct IncidentPolicyTests {
    /// FR-006 and FR-011 require thresholds and durations be configurable, so the
    /// defaults are a starting point rather than a decision baked into logic.
    @Test("A shorter configured duration triggers sooner")
    func shorterDurationTriggersSooner() {
        let impatient = IncidentPolicy(cpuSustainedDuration: .seconds(30))
        let observations = stride(from: 0.0, through: 40, by: 10).map { busy($0) }

        #expect(run(observations, policy: impatient).contains {
            if case .opened = $0 { true } else { false }
        })
        // The same sequence under the default 180s policy opens nothing.
        #expect(run(observations).isEmpty)
    }

    @Test("A higher configured threshold ignores a lesser load")
    func higherThresholdIgnoresLesserLoad() {
        let strict = IncidentPolicy(cpuBusyFractionThreshold: 0.98)
        let observations = stride(from: 0.0, through: 300, by: 20).map { busy($0, 0.90) }
        #expect(run(observations, policy: strict).isEmpty)
        #expect(!run(observations).isEmpty, "the default policy should have opened one")
    }

    @Test("Defaults are the documented values")
    func defaultsAreDocumented() {
        let policy = IncidentPolicy.default
        #expect(policy.cpuBusyFractionThreshold == 0.85)
        #expect(policy.cpuSustainedDuration == .seconds(180))
        #expect(policy.recoveryDuration == .seconds(60))
        #expect(policy.mergeWindow == .seconds(120))
    }
}
