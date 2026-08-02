import Darwin
import Foundation
import Testing

@testable import Metrics

@Suite("Process enumeration")
struct ProcessEnumerationTests {
    @Test("sysctl returns a populated process table")
    func tableIsPopulated() throws {
        let table = try ProcessSampler.systemProcessTable().get()
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
