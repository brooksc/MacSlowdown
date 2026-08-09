import Foundation
import Metrics

// Standalone FR-030 measurement.
//
// Run outside the test bundle deliberately: OverheadHarness measures the whole
// process, so inside a parallel test run it also counts other suites' work. This
// is the authoritative figure.

@main
struct OverheadRunner {
    static func main() async {
        let seconds = CommandLine.arguments.count > 1
            ? Double(CommandLine.arguments[1]) ?? 60 : 60
        print("measuring for \(seconds)s at the app's normal cadence…")

        let history = MetricsHistory()
        let measurement = await OverheadHarness.measure(
            duration: .seconds(seconds), history: history)

        print("")
        print(measurement.summary)
        print("")
        print("within all budgets: \(measurement.withinAllBudgets)")

        exit(measurement.withinAllBudgets ? 0 : 1)
    }
}
