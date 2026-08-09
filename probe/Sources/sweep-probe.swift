import Darwin
import Foundation

// Per-sweep cost in steady state, for the pieces the app runs every cycle.
// Sampling and grouping account for ~6 ms; the harness implies ~23 ms, so this
// looks for the rest.

func measure(_ name: String, _ totals: inout [String: Double], _ body: () -> Void) {
    let start = ContinuousClock().now
    body()
    totals[name, default: 0] += (ContinuousClock().now - start).totalSeconds * 1000
}

@main
struct SweepProbe {
    static func main() {
        let sampler = ProcessSampler()
        let resolver = ProcessIdentityResolver()
        let lifecycle = LifecycleTracker()
        let history = MetricsHistory()

        var previous = sampler.snapshot()
        _ = FamilyGrouper.group(snapshot: previous, resolver: resolver)
        var previousHost = HostCPU.sample()

        var totals: [String: Double] = [:]
        let rounds = 5

        for _ in 0..<rounds {
            Thread.sleep(forTimeInterval: 2)

            var snapshot = previous
            measure("sampler.snapshot", &totals) { snapshot = sampler.snapshot() }
            var host = previousHost
            measure("HostCPU.sample", &totals) { host = HostCPU.sample() }

            if let earlier = previousHost, let later = host {
                measure("attribution (with naming)", &totals) {
                    _ = CPUAttributionCalculator.attribution(
                        from: previous, to: snapshot, hostEarlier: earlier, hostLater: later,
                        naming: { resolver.identity(for: $0).friendlyName })
                }
            }
            measure("FamilyGrouper.group", &totals) {
                _ = FamilyGrouper.group(snapshot: snapshot, resolver: resolver)
            }
            measure("MemorySignals.pressure", &totals) { _ = MemorySignals.currentPressureLevel() }
            measure("ThermalState.current", &totals) { _ = ThermalState.current }
            measure("PowerSignals.current", &totals) { _ = PowerSignals.current() }
            measure("SwapSignals.counters", &totals) { _ = SwapSignals.pagingCounters() }
            measure("DiskSignals.counters", &totals) { _ = DiskSignals.counters() }
            measure("LifecycleTracker.events", &totals) {
                _ = lifecycle.events(from: previous, to: snapshot)
            }
            if let earlier = previousHost, let later = host {
                measure("history.record", &totals) {
                    history.record(CPUAttributionCalculator.attribution(
                        from: previous, to: snapshot,
                        hostEarlier: earlier, hostLater: later))
                }
            }
            measure("history.flushIfNeeded", &totals) { _ = try? history.flushIfNeeded() }
            measure("resolver.prune", &totals) { resolver.prune(keeping: Set(snapshot.records.keys)) }

            previous = snapshot
            previousHost = host
        }

        print("mean cost per sweep, steady state (\(rounds) sweeps)")
        var sum = 0.0
        for (name, total) in totals.sorted(by: { $0.value > $1.value }) {
            let mean = total / Double(rounds)
            sum += mean
            print(String(format: "  \(name.padding(toLength: 28, withPad: " ", startingAt: 0)) %7.2f ms", mean))
        }
        print(String(format: "  TOTAL                        %7.2f ms", sum))
        print(String(format: "  at a 2s cadence: %.3f%% of one core", sum / 2000 * 100))
    }
}
