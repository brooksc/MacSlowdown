import Darwin
import Foundation
import Testing

@testable import Metrics

/// FR-030 verification. `.serialized` because these measure real CPU cost and
/// would be distorted by other measurement tests running alongside.
///
/// Reference conditions, recorded so the numbers can be interpreted later:
/// Apple M2 (4 performance + 4 efficiency cores, 8 logical), macOS 26/27,
/// Debug build, running under the test host alongside the rest of the suite —
/// i.e. a busier machine than a shipped app on an idle desktop, which makes this
/// a conservative check rather than a flattering one.
@Suite("FR-030 overhead budget", .serialized)
struct OverheadHarnessTests {
    @Test("A sustained monitoring run stays inside every FR-030 budget",
          .timeLimit(.minutes(2)))
    func sustainedRunWithinBudgets() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macslowdown-overhead-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let history = MetricsHistory(persistence: .acrossRestarts(url: url))
        let measurement = await OverheadHarness.measure(
            duration: .seconds(20), cadence: .seconds(2), history: history)

        // Surfaced on failure so a regression reports what it actually cost.
        let report = measurement.summary

        #expect(measurement.sweeps >= 5, "only \(measurement.sweeps) sweeps completed")
        #expect(measurement.withinCPUBudget, "CPU over budget.\n\(report)")
        #expect(measurement.withinMemoryBudget, "memory over budget.\n\(report)")
        #expect(measurement.withinDiskBudget, "disk over budget.\n\(report)")
    }

    /// AC#3: the sampling loop must not leak. A steadily growing resident size
    /// would eventually breach the budget however low it starts.
    @Test("Sustained sampling does not grow memory without bound", .timeLimit(.minutes(2)))
    func memoryDoesNotGrowUnbounded() async throws {
        let history = MetricsHistory(persistence: .memoryOnly)
        let measurement = await OverheadHarness.measure(
            duration: .seconds(20), cadence: .seconds(1), history: history)

        // History is a fixed-capacity ring and the identity cache is pruned each
        // sweep, so growth over a short run should be small. A few MB of allocator
        // noise is expected; tens of MB would indicate an unbounded structure.
        let growthMB = Double(measurement.residentGrowthBytes) / 1_048_576
        #expect(growthMB < 25, "resident grew \(growthMB) MB over the run.\n\(measurement.summary)")
    }

    /// AC#1: the budget lives in one place, so code and tests cannot drift apart.
    @Test("Budget constants match the values FR-030 states")
    func budgetMatchesRequirement() {
        #expect(FR030Budget.cpuPercentOfOneCore == 1.0)
        #expect(FR030Budget.residentBytes == 100 * 1_048_576)
        #expect(FR030Budget.bytesPerHour == 10 * 1_048_576)
    }

    @Test("Memory-only history projects zero disk traffic")
    func memoryOnlyWritesNothing() async {
        let history = MetricsHistory(persistence: .memoryOnly)
        let measurement = await OverheadHarness.measure(
            duration: .seconds(4), cadence: .seconds(1), history: history)
        #expect(measurement.bytesWrittenPerHour == 0)
        #expect(measurement.withinDiskBudget)
    }

    @Test("The harness reads its own resident size")
    func readsOwnResidentSize() {
        #expect(OverheadHarness.selfResidentBytes() > 0)
    }
}
