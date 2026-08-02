import Darwin
import Foundation

/// Core counts, including the performance/efficiency split on Apple Silicon.
public struct CoreTopology: Sendable {
    public let logical: Int
    /// Performance cores, or nil on hardware without a split.
    public let performance: Int?
    /// Efficiency cores, or nil on hardware without a split.
    public let efficiency: Int?

    public var isAsymmetric: Bool { performance != nil && efficiency != nil }

    public static let current: CoreTopology = {
        func count(_ name: String) -> Int? {
            var value = 0
            var size = MemoryLayout<Int>.size
            guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
            return value
        }
        return CoreTopology(
            logical: count("hw.logicalcpu") ?? 1,
            // perflevel0 is the highest-performance level on Apple Silicon.
            performance: count("hw.perflevel0.logicalcpu"),
            efficiency: count("hw.perflevel1.logicalcpu")
        )
    }()
}

/// How CPU numbers are presented (FR-004).
///
/// **Decision: percentage of one core is the primary unit**, with the
/// machine-relative figure shown alongside as context rather than replacing it.
///
/// Why this way round:
///   - It matches the kernel counter we actually read and what `top`, `ps` and
///     Activity Monitor report, so a user cross-checking us finds the same number.
///   - It makes a runaway process legible: "412%" says four cores' worth, which a
///     machine-relative "41%" hides.
///   - The spec's own acceptance criterion is a synthetic two-core workload being
///     represented accurately, which core-relative does directly.
///
/// The known cost is that values above 100% confuse people who have not seen the
/// convention, which is exactly why FR-004 requires the convention be explained
/// wherever the numbers appear — hence `convention` below, not a comment.
///
/// **On performance/efficiency asymmetry:** we deliberately do not normalise for
/// it. `host_processor_info` reports per-core tick counters but nothing that maps
/// an index to a performance level, and mach tick accounting does not scale by
/// core capability. Weighting them would mean inventing a factor we cannot
/// measure, which FR-036 and FR-038 forbid. So "% of one core" is a share of
/// *capacity*, not of delivered performance, and the topology note says so on
/// asymmetric hardware rather than pretending the cores are interchangeable.
public enum CPUPresentation {
    public static func percentOfOneCore(_ value: Double) -> String {
        String(format: value >= 10 ? "%.0f%%" : "%.1f%%", value)
    }

    /// Machine-relative context, e.g. "about 1.5 of 8 cores".
    public static func machineRelative(
        _ percentOfOneCore: Double,
        topology: CoreTopology = .current
    ) -> String {
        let cores = percentOfOneCore / 100
        guard cores >= 0.1 else {
            return String(format: "%.1f%% of this Mac", percentOfOneCore / Double(topology.logical))
        }
        return String(format: "about %.1f of %d cores", cores, topology.logical)
    }

    /// The sentence that must accompany CPU figures wherever they appear.
    public static func convention(topology: CoreTopology = .current) -> String {
        "Percentages are of one core. 100% is one core fully busy; this Mac has \(topology.logical)."
    }

    /// Additional note for asymmetric hardware, stating the limitation plainly
    /// rather than implying the cores are equivalent.
    public static func topologyNote(topology: CoreTopology = .current) -> String? {
        guard topology.isAsymmetric,
              let performance = topology.performance,
              let efficiency = topology.efficiency
        else { return nil }
        return "This Mac has \(performance) performance and \(efficiency) efficiency cores. "
            + "A percentage is a share of one core's time, not of its speed, so the same "
            + "figure can mean different amounts of work on different cores."
    }
}
