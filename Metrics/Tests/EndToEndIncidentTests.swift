import Darwin
import Foundation
import Testing

@testable import Metrics

private func spinner() -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    return process
}

/// Drives the real sampling path through a real CPU load and asserts the whole
/// chain behaves: sample, attribute, detect, summarize, adapt cadence.
///
/// `.serialized` because it saturates cores. Durations are compressed via a
/// custom policy so the test runs in seconds rather than minutes — the logic
/// under test is duration-relative, so a 6s sustained requirement exercises the
/// same code paths as the shipping 180s one.
@Suite("End-to-end incident detection", .serialized)
struct EndToEndIncidentTests {
    private var fastPolicy: IncidentPolicy {
        IncidentPolicy(
            cpuBusyFractionThreshold: 0.50,
            cpuSustainedDuration: .seconds(6),
            recoveryDuration: .seconds(4),
            mergeWindow: .seconds(3))
    }

    /// The goal's core condition: a controlled slowdown produces ONE coherent
    /// incident, not a burst of duplicates, and it closes only after hysteresis.
    @Test("A real slowdown produces one incident that closes after recovery",
          .timeLimit(.minutes(3)))
    func realSlowdownProducesOneIncident() async throws {
        let cores = MachineTopology.logicalCoreCount
        let sampler = ProcessSampler()
        let detector = IncidentDetector(policy: fastPolicy)
        var state = IncidentDetector.State()

        var events: [IncidentEvent] = []
        var previous = sampler.snapshot()
        var previousHost = try #require(HostCPU.sample())
        var lastAttribution: CPUAttribution?

        // Saturate every core so the busy fraction genuinely crosses 50%.
        var load = (0..<cores).map { _ in spinner() }
        defer { load.forEach { $0.terminate() } }

        func sample(seconds: Double) async throws {
            try await Task.sleep(for: .seconds(seconds))
            let snapshot = sampler.snapshot()
            let host = try #require(HostCPU.sample())
            let attribution = CPUAttributionCalculator.attribution(
                from: previous, to: snapshot, hostEarlier: previousHost, hostLater: host)
            lastAttribution = attribution

            let observation = SystemObservation(
                at: Date(),
                cpuBusyFraction: attribution.totalBusyPercentOfOneCore
                    / (Double(cores) * 100))
            if let event = detector.observe(observation, state: &state) {
                events.append(event)
            }
            previous = snapshot
            previousHost = host
        }

        // ~14s under load: past the 6s sustained requirement, with many samples.
        for _ in 0..<14 { try await sample(seconds: 1) }

        let opened = events.filter { if case .opened = $0 { true } else { false } }
        #expect(opened.count == 1,
                "expected exactly one incident from one slowdown, got \(opened.count)")
        #expect(state.current != nil, "the incident should still be open under load")

        // Clear the load and confirm it does NOT close immediately.
        load.forEach { $0.terminate() }
        load = []
        try await sample(seconds: 2)
        let closedTooEarly = events.filter { if case .closed = $0 { true } else { false } }
        #expect(closedTooEarly.isEmpty, "closed before the recovery period elapsed")

        // Let recovery hold past the hysteresis window.
        for _ in 0..<5 { try await sample(seconds: 1) }

        let closed = events.filter { if case .closed = $0 { true } else { false } }
        #expect(closed.count == 1, "expected exactly one close, got \(closed.count)")

        guard case .closed(let incident) = try #require(closed.first) else { return }
        #expect(!incident.isOpen)
        #expect(incident.conditions.contains(.cpuSaturation))
        #expect(incident.peakCPUBusyFraction >= 0.5)

        // The goal's reporting condition: the summary separates evidence classes
        // and labels every causal phrase.
        let summary = IncidentSummarizer.summarize(
            incident: incident, attribution: lastAttribution)
        #expect(summary.isWellFormed)
        #expect(!summary.measured.isEmpty, "no measured facts in the report")
        for hypothesis in summary.hypotheses {
            #expect(hypothesis.confidence != nil, "an unlabelled causal claim")
        }
    }

    /// The goal's cadence condition: resolution rises during an incident and
    /// falls back afterwards, without losing samples.
    @Test("Cadence rises under load and falls back after recovery",
          .timeLimit(.minutes(2)))
    func cadenceAdaptsToRealLoad() async throws {
        let cores = MachineTopology.logicalCoreCount
        let controller = CadenceController(
            normalInterval: .seconds(2),
            investigationInterval: .seconds(1),
            investigationLinger: .seconds(3))
        var cadenceState = CadenceController.State()
        let sampler = ProcessSampler()

        var previous = sampler.snapshot()
        var previousHost = try #require(HostCPU.sample())
        var modes: [SamplingMode] = []
        var offered = 0

        func observe(underLoad: Bool) async throws {
            try await Task.sleep(for: .milliseconds(800))
            let snapshot = sampler.snapshot()
            let host = try #require(HostCPU.sample())
            let attribution = CPUAttributionCalculator.attribution(
                from: previous, to: snapshot, hostEarlier: previousHost, hostLater: host)
            let breaching = attribution.totalBusyPercentOfOneCore
                / (Double(cores) * 100) >= 0.5
            let cadence = controller.cadence(
                at: Date(), incidentOpen: false,
                conditionBreaching: breaching, state: &cadenceState)
            modes.append(cadence.mode)
            offered += 1
            previous = snapshot
            previousHost = host
            _ = underLoad
        }

        for _ in 0..<3 { try await observe(underLoad: false) }

        var load = (0..<cores).map { _ in spinner() }
        for _ in 0..<4 { try await observe(underLoad: true) }
        load.forEach { $0.terminate() }
        load = []

        for _ in 0..<8 { try await observe(underLoad: false) }

        #expect(modes.contains(.investigation), "cadence never rose under real load")
        #expect(modes.last == .normal, "cadence never fell back after recovery")
        #expect(cadenceState.samplesTaken == offered,
                "\(offered - cadenceState.samplesTaken) samples lost across transitions")
    }
}
