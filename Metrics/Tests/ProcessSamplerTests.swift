import Darwin
import Foundation
import Testing

@testable import Metrics

/// Spawns a process that saturates exactly one core, for CPU-accuracy checks.
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
    return Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

@Suite("Process enumeration")
struct ProcessEnumerationTests {
    @Test("sysctl returns a populated process table")
    func tableIsPopulated() {
        let table = ProcessSampler.processTable()
        #expect(table.count > 50, "got \(table.count) processes")
    }

    @Test("The running test process is present and measurable")
    func selfIsMeasurable() throws {
        let snapshot = ProcessSampler().snapshot()
        let record = try #require(
            snapshot.records.values.first { $0.identity.pid == getpid() },
            "own pid \(getpid()) missing from the snapshot"
        )
        #expect(record.isMeasurable)
        #expect((record.measurements?.residentBytes ?? 0) > 0)
    }

    @Test("Every process has an identity, name and parent even without metrics")
    func identityAlwaysPresent() {
        let snapshot = ProcessSampler().snapshot()
        for record in snapshot.records.values {
            #expect(record.identity.pid > 0)
            #expect(record.identity.startTime > 0, "pid \(record.identity.pid) has no start time")
            #expect(!record.command.isEmpty, "pid \(record.identity.pid) has no command name")
        }
    }

    /// FR-002: unavailable values are labeled, not omitted. Roughly a third of the
    /// process table is owned by other users and denied with EPERM; those processes
    /// must still appear, named, so their usage can be accounted for as
    /// unattributed rather than silently vanishing.
    @Test("Denied processes are present and labeled, not dropped")
    func deniedProcessesAreLabeled() {
        let snapshot = ProcessSampler().snapshot()
        let denied = snapshot.records.values.filter { $0.metrics == .notPermitted }

        #expect(!denied.isEmpty, "expected some other-uid processes to be denied")
        #expect(snapshot.notMeasurableCount >= denied.count)
        #expect(snapshot.measurableCount + snapshot.notMeasurableCount == snapshot.records.count)
        for record in denied {
            #expect(!record.command.isEmpty)
            #expect(record.measurements == nil)
        }
    }

    @Test("Identity pairs pid with start time, so a reused pid is a different process")
    func identityIncludesStartTime() {
        let a = ProcessIdentity(pid: 42, startTime: 1000)
        let b = ProcessIdentity(pid: 42, startTime: 2000)
        #expect(a != b)
        #expect(Set([a, b]).count == 2)
    }
}

@Suite("CPU rate calculation")
struct CPURateTests {
    /// FR-006/FR-009: a cumulative counter is never itself a rate. Comparing a
    /// snapshot with itself spans zero elapsed time and must yield nothing, not the
    /// process's lifetime total.
    @Test("A snapshot compared with itself yields no usage")
    func zeroIntervalYieldsNothing() {
        let snapshot = ProcessSampler().snapshot()
        #expect(CPUUsage.between(snapshot, snapshot).isEmpty)
    }

    @Test("Usage comes from the delta, not the cumulative total")
    func usesDeltaNotTotal() async throws {
        let sampler = ProcessSampler()
        let first = sampler.snapshot()
        try await Task.sleep(for: .milliseconds(500))
        let second = sampler.snapshot()

        let usage = CPUUsage.between(first, second)
        #expect(!usage.isEmpty)

        // Every process's lifetime CPU total is vastly larger than what it can
        // accrue in half a second, so any value near a cumulative total would be
        // absurd. Nothing may exceed the machine's total capacity either.
        let ceiling = Double(MachineTopology.logicalCoreCount) * 100
        for entry in usage {
            #expect(entry.percentOfOneCore >= 0)
            #expect(entry.percentOfOneCore <= ceiling,
                    "\(entry.command) reported \(entry.percentOfOneCore)% of one core")
        }
    }

    /// FR-004 acceptance criterion: a synthetic workload is represented accurately
    /// under the documented convention. This is the test that fails loudly if the
    /// mach-tick conversion is ever dropped — without it the reading is ~42x low.
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
        let measured = try #require(
            CPUUsage.between(first, second).first { $0.identity.pid == pid },
            "spinner pid \(pid) not found in usage"
        )

        #expect(measured.percentOfOneCore > 80,
                "read \(measured.percentOfOneCore)% — a dropped timebase conversion reads ~2.4%")
        #expect(measured.percentOfOneCore < 130, "read \(measured.percentOfOneCore)%")

        if let ps = psCPU(pid) {
            #expect(abs(measured.percentOfOneCore - ps) < 25,
                    "ours \(measured.percentOfOneCore)% vs ps \(ps)%")
        }
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

        let usage = CPUUsage.between(before, after)
        let pids = [first.processIdentifier, second.processIdentifier]
        let measured = usage.filter { pids.contains($0.identity.pid) }

        #expect(measured.count == 2, "found \(measured.count) of 2 spinners")
        for entry in measured {
            #expect(entry.percentOfOneCore > 80, "read \(entry.percentOfOneCore)%")
            #expect(entry.percentOfOneCore < 130, "read \(entry.percentOfOneCore)%")
        }

        // Combined they occupy about two cores — the case that makes a
        // machine-relative-only presentation misleading (FR-004).
        let combined = measured.reduce(0) { $0 + $1.percentOfOneCore }
        #expect(combined > 160, "combined \(combined)% of one core")
    }
}

@Suite("Sweep overhead")
struct SweepOverheadTests {
    /// FR-030: idle CPU median at or below 1% of one core. At a 2s cadence that is
    /// a 20ms budget per sweep. Uses the median, matching how the requirement is
    /// stated, so one scheduling hiccup on a busy CI machine does not fail the run.
    @Test("Median sweep stays within the 2s-cadence budget")
    func sweepWithinBudget() {
        let sampler = ProcessSampler()
        var durations: [Double] = []
        for _ in 0..<9 {
            durations.append(sampler.snapshot().sweepDuration.totalSeconds)
        }
        durations.sort()
        let median = durations[durations.count / 2]
        let budget = 0.02  // 1% of one core at a 2s cadence

        #expect(median < budget,
                "median sweep \(median * 1000)ms exceeds \(budget * 1000)ms budget")
    }

    @Test("Snapshot records its own sweep duration")
    func recordsDuration() {
        let snapshot = ProcessSampler().snapshot()
        #expect(snapshot.sweepDuration.totalSeconds > 0)
    }
}
