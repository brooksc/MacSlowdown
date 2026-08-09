import Darwin
import Foundation
import Metrics

// Where does the FR-030 CPU go? The standalone harness reported 1.348% of one
// core against a 1.0% budget after naming was added, so this splits the sweep
// into its parts and separates first-sighting cost from steady state.

@main
struct CostProbe {
    static func time(_ label: String, _ body: () -> Void) -> Double {
        let start = ContinuousClock().now
        body()
        let ms = (ContinuousClock().now - start).totalSeconds * 1000
        print(String(format: "  \(label.padding(toLength: 46, withPad: " ", startingAt: 0)) %8.2f ms", ms))
        return ms
    }

    static func main() {
        let sampler = ProcessSampler()

        print("=== one-off: the first sighting of every process ===")
        let snapshot = sampler.snapshot()
        print("  processes: \(snapshot.records.count)")

        let cold = ProcessIdentityResolver()
        let coldGrouping = time("FamilyGrouper.group, cold cache (with naming)") {
            _ = FamilyGrouper.group(snapshot: snapshot, resolver: cold)
        }

        print("")
        print("=== steady state: everything already cached ===")
        var warmSweep = 0.0
        var warmGrouping = 0.0
        for _ in 0..<5 {
            let next = sampler.snapshot()
            warmSweep += time("ProcessSampler.snapshot()") { _ = sampler.snapshot() }
            warmGrouping += time("FamilyGrouper.group, warm cache") {
                _ = FamilyGrouper.group(snapshot: next, resolver: cold)
            }
        }
        print(String(format: "  mean sweep    %.2f ms", warmSweep / 5))
        print(String(format: "  mean grouping %.2f ms", warmGrouping / 5))

        print("")
        print("=== what does naming itself cost, per process, cold? ===")
        let fresh = ProcessIdentityResolver()
        let sample = Array(snapshot.records.values.prefix(200))
        let namingCost = time("identity + naming x200 (cold)") {
            for record in sample { _ = fresh.identity(for: record.identity) }
        }
        print(String(format: "  per process: %.3f ms", namingCost / Double(sample.count)))

        print("")
        print("=== the split ===")
        print(String(format: "  cold grouping is %.0fx a warm one", coldGrouping / (warmGrouping / 5)))
        print("  A cold cache happens once per process lifetime. Over a 90s run at")
        print("  ~2s cadence that one-off is amortised across ~45 sweeps, so it")
        print("  dominates a short measurement and vanishes in a long one.")
    }
}
