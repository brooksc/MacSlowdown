import Darwin
import Foundation
import Testing

@testable import Metrics

/// Samples host CPU and the process table together, the way the app will.
private func attributionOverInterval(_ duration: Duration) async throws -> CPUAttribution {
    let sampler = ProcessSampler()
    let hostBefore = try #require(HostCPU.sample())
    let before = sampler.snapshot()
    try await Task.sleep(for: duration)
    let after = sampler.snapshot()
    let hostAfter = try #require(HostCPU.sample())

    return CPUAttributionCalculator.attribution(
        from: before, to: after, hostEarlier: hostBefore, hostLater: hostAfter)
}

@Suite("Host CPU")
struct HostCPUTests {
    @Test("Aggregate counters are readable and monotonic")
    func countersAreMonotonic() async throws {
        let first = try #require(HostCPU.sample())
        try await Task.sleep(for: .milliseconds(300))
        let second = try #require(HostCPU.sample())

        #expect(second.total > first.total)
        #expect(second.busy >= first.busy)
    }

    @Test("Busy fraction comes from the delta and stays within 0...1")
    func busyFractionIsBounded() async throws {
        let first = try #require(HostCPU.sample())
        try await Task.sleep(for: .milliseconds(300))
        let second = try #require(HostCPU.sample())

        let fraction = try #require(HostCPU.busyFraction(from: first, to: second))
        #expect(fraction >= 0)
        #expect(fraction <= 1)
    }

    @Test("A zero-length interval yields no rate rather than a bogus one")
    func zeroIntervalYieldsNil() throws {
        let sample = try #require(HostCPU.sample())
        #expect(HostCPU.busyFraction(from: sample, to: sample) == nil)
    }
}

@Suite("CPU attribution")
struct CPUAttributionTests {
    /// AC#1: the remainder is always present, and the parts always account for the
    /// whole. A contributor list that silently failed to sum would misrepresent
    /// the machine.
    @Test("Attributed plus unattributed equals the measured total")
    func partsSumToWhole() async throws {
        let attribution = try await attributionOverInterval(.seconds(1))
        let sum = attribution.attributedPercentOfOneCore + attribution.unattributedPercentOfOneCore

        #expect(abs(sum - attribution.totalBusyPercentOfOneCore) < 0.001,
                "parts \(sum) vs total \(attribution.totalBusyPercentOfOneCore)")
    }

    @Test("Unattributed is never negative, even when sampling skews")
    func unattributedNeverNegative() async throws {
        for _ in 0..<3 {
            let attribution = try await attributionOverInterval(.milliseconds(400))
            #expect(attribution.unattributedPercentOfOneCore >= 0)
            #expect(attribution.unattributedShare >= 0)
            #expect(attribution.unattributedShare <= 1)
        }
    }

    /// AC#3: figures carry their evidence class. The remainder is calculated, not
    /// measured, and must not be presented as though it were read from a counter.
    @Test("Total and attributed are measured; the remainder is calculated")
    func evidenceIsClassified() async throws {
        let attribution = try await attributionOverInterval(.milliseconds(500))
        let figures = attribution.figures

        #expect(figures.count == 3)
        let total = try #require(figures.first { $0.label == "Total CPU" })
        #expect(total.evidence == .measured)

        let attributed = try #require(figures.first { $0.label.contains("Attributed") })
        #expect(attributed.evidence == .measured)

        let remainder = try #require(figures.first { $0.label.contains("Unattributed") })
        #expect(remainder.evidence == .calculated)
    }

    /// AC#4: the bucket is not anonymous. Which protected processes were running is
    /// a measured fact even though their CPU is not obtainable.
    @Test("Protected processes are named, with start times")
    func protectedProcessesAreNamed() async throws {
        let attribution = try await attributionOverInterval(.milliseconds(500))

        #expect(!attribution.protectedProcesses.isEmpty,
                "expected some other-uid processes to be denied and therefore named")
        for process in attribution.protectedProcesses {
            #expect(!process.command.isEmpty)
            #expect(process.startedAt.timeIntervalSince1970 > 0)
        }

        // The machine always runs some of these; they are the canonical members of
        // the bucket and the reason it exists.
        let names = Set(attribution.protectedProcesses.map(\.command))
        let expected: Set<String> = ["launchd", "WindowServer", "mds_stores", "coreaudiod", "hidd"]
        #expect(!names.isDisjoint(with: expected),
                "none of \(expected) were present; got \(names.prefix(10))")
    }

    /// AC#2: the explanation states what was and was not measured, without claiming
    /// causation (FR-013) or implying the remainder is waste (FR-036).
    @Test("Explanation describes the limitation without overstating it")
    func explanationIsHonest() async throws {
        let attribution = try await attributionOverInterval(.milliseconds(500))
        let text = attribution.explanation

        #expect(!text.isEmpty)
        if attribution.unattributedPercentOfOneCore > 0 {
            #expect(text.contains("measured difference"),
                    "must say the remainder is measured arithmetic, not an estimate")
            #expect(text.lowercased().contains("not how much cpu"),
                    "must state that per-process usage is unavailable")
        }

        // Language discipline: no claim of cause, no implication of waste or fault.
        for forbidden in ["caused", "wasted", "leak", "optimi", "clean up", "fix"] {
            #expect(!text.lowercased().contains(forbidden),
                    "explanation contains overstated language: \(forbidden)")
        }
    }

    @Test("Contributors are ordered largest first")
    func contributorsAreSorted() async throws {
        let attribution = try await attributionOverInterval(.milliseconds(600))
        let percentages = attribution.contributors.map(\.percentOfOneCore)
        let sorted = percentages.sorted(by: >)
        #expect(percentages == sorted)
    }
}
