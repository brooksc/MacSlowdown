import Darwin
import Foundation
import Testing

@testable import Metrics

/// Spawns a process that saturates exactly one core.
private func spinner() -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    return process
}

/// `ps` reading of a pid's CPU, as a percentage of one core.
private func psCPU(_ pid: pid_t) -> Double? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "%cpu=", "-p", String(pid)]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Double(
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Tests that measure real CPU behaviour against a synthetic workload.
///
/// `.serialized` is load-bearing, not tidiness: these tests saturate cores, and
/// running two of them at once means neither spinner gets a full core, so both
/// read low and fail intermittently. Keeping every workload-sensitive test in one
/// serialized suite is what makes them deterministic.
@Suite("CPU measurement against a synthetic workload", .serialized)
struct CPUWorkloadTests {
    /// FR-004 acceptance criterion: a synthetic workload is represented accurately
    /// under the documented convention. This is the test that fails loudly if the
    /// mach-tick conversion is ever dropped — without it the reading is ~2.4%.
    @Test("A single-core workload reads as roughly 100% of one core", .timeLimit(.minutes(1)))
    func singleCoreWorkload() async throws {
        let spin = spinner()
        defer { spin.terminate() }
        try await Task.sleep(for: .milliseconds(500))

        let sampler = ProcessSampler()
        let first = sampler.snapshot()
        try await Task.sleep(for: .seconds(2))
        let second = sampler.snapshot()

        let pid = spin.processIdentifier
        let usage = CPUUsage.between(first, second)
        let measured = try #require(
            usage.first { $0.identity.pid == pid },
            "spinner pid \(pid) not found in usage"
        )

        // Agreement with `ps` is the primary assertion: it measures the same
        // reality we do, so it holds whatever else the machine is doing. An
        // absolute "must read ~100%" only holds when a core is actually free,
        // which made this test fail whenever an unrelated build was running.
        let reference = try #require(psCPU(pid), "ps gave no reading for pid \(pid)")
        #expect(abs(measured.percentOfOneCore - reference) < 25,
                "ours \(measured.percentOfOneCore)% vs ps \(reference)%")

        // Floor low enough to survive a saturated machine, high enough to catch
        // the landmine: dropping the mach-tick conversion reads ~2.4%.
        #expect(measured.percentOfOneCore > 20,
                "read \(measured.percentOfOneCore)% — a dropped timebase conversion reads ~2.4%")
        #expect(measured.percentOfOneCore < 130, "read \(measured.percentOfOneCore)%")
    }

    @Test("Two single-core workloads each read as roughly one core", .timeLimit(.minutes(1)))
    func dualCoreWorkload() async throws {
        let first = spinner(), second = spinner()
        defer { first.terminate(); second.terminate() }
        try await Task.sleep(for: .milliseconds(500))

        let sampler = ProcessSampler()
        let before = sampler.snapshot()
        try await Task.sleep(for: .seconds(2))
        let after = sampler.snapshot()

        let pids = [first.processIdentifier, second.processIdentifier]
        let measured = CPUUsage.between(before, after).filter { pids.contains($0.identity.pid) }

        #expect(measured.count == 2, "found \(measured.count) of 2 spinners")
        for entry in measured {
            // Same reasoning as the single-core case: agree with ps, and keep a
            // floor that catches a dropped timebase without assuming free cores.
            if let reference = psCPU(entry.identity.pid) {
                #expect(abs(entry.percentOfOneCore - reference) < 25,
                        "ours \(entry.percentOfOneCore)% vs ps \(reference)%")
            }
            #expect(entry.percentOfOneCore > 20, "read \(entry.percentOfOneCore)%")
            #expect(entry.percentOfOneCore < 130, "read \(entry.percentOfOneCore)%")
        }

        // Two processes each exceeding one core's worth is the case that makes a
        // machine-relative-only presentation misleading (FR-004). Under
        // contention each gets less, so assert the shape rather than a total the
        // scheduler may not grant.
        let combined = measured.reduce(0) { $0 + $1.percentOfOneCore }
        #expect(combined > 40, "combined \(combined)% of one core")
    }

    /// FR-032: the tool has to keep working during the problem it exists to
    /// diagnose. Saturates every core, then checks that sampling still completes,
    /// still produces usable attribution, and recovers afterwards.
    @Test("Sampling survives full CPU saturation and recovers", .timeLimit(.minutes(2)))
    func survivesSaturation() async throws {
        let cores = MachineTopology.logicalCoreCount
        // One spinner per core, plus two, so nothing is left idle for us.
        let load = (0..<(cores + 2)).map { _ in spinner() }
        defer { load.forEach { $0.terminate() } }
        try await Task.sleep(for: .seconds(1))

        let sampler = ProcessSampler()
        var durations: [Double] = []
        var attributions: [CPUAttribution] = []

        for _ in 0..<4 {
            let hostBefore = HostCPU.sample()
            let before = sampler.snapshot()
            try await Task.sleep(for: .milliseconds(700))
            let after = sampler.snapshot()
            let hostAfter = HostCPU.sample()
            durations.append(after.sweepDuration.totalSeconds)

            if let hostBefore, let hostAfter {
                attributions.append(CPUAttributionCalculator.attribution(
                    from: before, to: after, hostEarlier: hostBefore, hostLater: hostAfter))
            }
        }

        // AC#1: status updates continue under saturation.
        #expect(attributions.count == 4, "only \(attributions.count) of 4 samples completed")

        // AC#2: sweeps still complete, and degrade rather than failing. Even a
        // fully saturated machine must not push a sweep past a sane bound.
        let worst = durations.max() ?? 0
        #expect(worst < 1.0, "slowest sweep took \(worst * 1000)ms under saturation")

        // Readings stay coherent: the machine is genuinely busy and the parts still
        // account for the whole.
        for attribution in attributions {
            let sum = attribution.attributedPercentOfOneCore
                + attribution.unattributedPercentOfOneCore
            #expect(abs(sum - attribution.totalBusyPercentOfOneCore) < 0.001)
            #expect(attribution.totalBusyPercentOfOneCore > Double(cores) * 50,
                    "machine should be heavily loaded, got \(attribution.totalBusyPercentOfOneCore)%")
        }

        // AC#4: recovery after the load clears, with no restart or intervention.
        load.forEach { $0.terminate() }
        try await Task.sleep(for: .seconds(2))

        let hostBefore = try #require(HostCPU.sample())
        let before = sampler.snapshot()
        try await Task.sleep(for: .seconds(1))
        let after = sampler.snapshot()
        let hostAfter = try #require(HostCPU.sample())
        let recovered = CPUAttributionCalculator.attribution(
            from: before, to: after, hostEarlier: hostBefore, hostLater: hostAfter)

        #expect(!recovered.contributors.isEmpty, "sampling did not resume after load cleared")
        #expect(after.sweepDuration.totalSeconds < 0.1,
                "sweep did not return to normal: \(after.sweepDuration.totalSeconds * 1000)ms")
    }

    /// A real workload must land in the attributed column, not the unattributed
    /// remainder — and the parts must still account for the whole under load.
    @Test("A real workload raises the attributed share", .timeLimit(.minutes(2)))
    func workloadIsAttributed() async throws {
        func attribution(over duration: Duration) async throws -> CPUAttribution {
            let sampler = ProcessSampler()
            let hostBefore = try #require(HostCPU.sample())
            let before = sampler.snapshot()
            try await Task.sleep(for: duration)
            let after = sampler.snapshot()
            let hostAfter = try #require(HostCPU.sample())
            return CPUAttributionCalculator.attribution(
                from: before, to: after, hostEarlier: hostBefore, hostLater: hostAfter)
        }

        let spin = spinner()
        defer { spin.terminate() }
        try await Task.sleep(for: .milliseconds(300))
        let busy = try await attribution(over: .seconds(1))

        // Assert the property directly rather than via a before/after delta: other
        // test suites run in parallel, so an "idle" baseline drifts and makes a
        // delta comparison flaky without testing anything extra.
        let spinnerUsage = try #require(
            busy.contributors.first { $0.identity.pid == spin.processIdentifier },
            "the spinner must appear among attributed contributors, not in the remainder"
        )
        #expect(spinnerUsage.percentOfOneCore > 80,
                "spinner attributed only \(spinnerUsage.percentOfOneCore)% of one core")

        // Its usage is counted in the attributed total, so the remainder does not
        // absorb work we could actually measure.
        #expect(busy.attributedPercentOfOneCore >= spinnerUsage.percentOfOneCore)

        // The sum invariant must hold under load, not only when the machine is quiet.
        let sum = busy.attributedPercentOfOneCore + busy.unattributedPercentOfOneCore
        #expect(abs(sum - busy.totalBusyPercentOfOneCore) < 0.001)
    }
}
