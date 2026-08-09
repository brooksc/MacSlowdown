import AppKit
import Foundation
import Metrics

/// Pure presentation for the menu bar popover (design 1a).
///
/// Separated from the view for the same reason `Presentation` is separated from
/// the store: the popover's copy is a requirement, not decoration (FR-013,
/// FR-038), and the cases that matter — nothing measured yet, a volume that did
/// not report, a family we can only partly account for — are unreachable from a
/// test while they live inside a `body`.
///
/// Nothing here samples, and nothing here invents a figure. Every value either
/// comes from a measurement passed in or is marked unavailable.
enum PopoverPresentation {

    // MARK: - Verdict

    /// The plain-language headline. A sentence, not a severity word: the popover
    /// exists to answer "is my Mac all right?", and "Normal" answers a different
    /// question.
    struct Verdict: Equatable {
        let headline: String
        let symbolName: String
    }

    static func verdict(severity: Severity, incidentOpen: Bool) -> Verdict {
        // The live-incident popover is TASK-65.2. This branch exists only so the
        // healthy copy is never shown over an open incident; it does not attempt
        // the triage presentation that screen calls for.
        if incidentOpen {
            return Verdict(
                headline: "A slowdown is happening now",
                symbolName: "exclamationmark.triangle.fill")
        }
        switch severity {
        case .normal:
            return Verdict(
                headline: "Your Mac is running normally",
                symbolName: "checkmark.circle.fill")
        case .elevated:
            return Verdict(
                headline: "Your Mac is working hard",
                symbolName: "gauge.with.dots.needle.67percent")
        case .severe:
            return Verdict(
                headline: "Your Mac is heavily loaded",
                symbolName: "gauge.with.dots.needle.100percent")
        }
    }

    // MARK: - Proof that monitoring is running

    /// "No slowdowns in the last 24 hours. Watching since 8:02 AM."
    ///
    /// The second half is load-bearing. "No slowdowns" on its own is equally
    /// consistent with the app having silently stopped measuring, so the line has
    /// to state the window it is speaking about.
    ///
    /// The window is the observed one, never a claimed one: we only assert "the
    /// last 24 hours" once we have actually been watching that long. Before then
    /// the sentence names the start instead, because incidents are held in memory
    /// for this session only and a 24-hour claim would be unsupported (FR-038).
    static func monitoringLine(
        isRunning: Bool,
        watchingSince: Date?,
        now: Date,
        incidentCount: Int,
        timeText: (Date) -> String = Self.shortTime
    ) -> String {
        guard isRunning else {
            return "Monitoring is not running, so nothing is being observed."
        }
        let count = incidentPhrase(incidentCount)
        guard let watchingSince else {
            // We know we are running but not since when. Say only what is known.
            return "\(count) observed so far."
        }
        let elapsed = now.timeIntervalSince(watchingSince)
        if elapsed >= 24 * 60 * 60 {
            return "\(count) in the last 24 hours. Watching since \(timeText(watchingSince))."
        }
        return "\(count) since \(timeText(watchingSince)), when monitoring started."
    }

    static func incidentPhrase(_ count: Int) -> String {
        switch count {
        case ..<1: "No slowdowns"
        case 1: "1 slowdown"
        default: "\(count) slowdowns"
        }
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// When monitoring began.
    ///
    /// Taken from the process launch date because `AppDelegate` starts the sampler
    /// in `applicationDidFinishLaunching`, so the two are the same instant to
    /// within the launch itself. It is a measured value rather than an assumed one.
    /// A `monitoringStartedAt` on the store would be more direct; see the task
    /// notes for TASK-65.1.
    static var launchedAt: Date? { NSRunningApplication.current.launchDate }

    // MARK: - Headline figures

    /// One cell of the four-up strip.
    ///
    /// `isAvailable == false` means the measurement could not be taken. It is
    /// rendered as such and never as a zero, because "0 B/s" says the disk was
    /// idle and that is a different claim (FR-002).
    struct MetricTile: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
        let isAvailable: Bool
        /// Longer form, used for the accessibility label and the tooltip.
        let detail: String
        /// Fill for a capacity bar, as a fraction used. Nil where a bar would be
        /// meaningless.
        let barFraction: Double?
    }

    static func tiles(
        attribution: CPUAttribution?,
        memoryPressure: MemoryPressureLevel,
        diskRates: DiskRates?,
        storage: VolumeCapacity?
    ) -> [MetricTile] {
        [
            cpuTile(attribution),
            memoryTile(memoryPressure),
            diskTile(diskRates),
            storageTile(storage),
        ]
    }

    private static func cpuTile(_ attribution: CPUAttribution?) -> MetricTile {
        guard let attribution else {
            return MetricTile(
                id: "cpu", label: "CPU", value: "—", isAvailable: false,
                detail: "Taking the first reading. A rate needs two samples.",
                barFraction: nil)
        }
        let percent = attribution.totalBusyPercentOfOneCore
        return MetricTile(
            id: "cpu", label: "CPU",
            value: CPUPresentation.percentOfOneCore(percent),
            isAvailable: true,
            detail: "\(CPUPresentation.percentOfOneCore(percent)) of one core, "
                + CPUPresentation.machineRelative(percent),
            barFraction: nil)
    }

    private static func memoryTile(_ level: MemoryPressureLevel) -> MetricTile {
        // The word, not a percentage: memory pressure is not percent of RAM used,
        // and showing a number here would invite exactly that reading (FR-007).
        MetricTile(
            id: "memory", label: "Memory pressure", value: level.label,
            isAvailable: true, detail: level.explanation, barFraction: nil)
    }

    private static func diskTile(_ rates: DiskRates?) -> MetricTile {
        guard let rates else {
            return MetricTile(
                id: "disk", label: "Disk", value: "Unavailable", isAvailable: false,
                detail: "No block storage driver reported byte counters.",
                barFraction: nil)
        }
        let total = rates.readBytesPerSecond + rates.writeBytesPerSecond
        return MetricTile(
            id: "disk", label: "Disk",
            value: "\(bytes(total))/s", isAvailable: true,
            // Read and write are kept in the detail rather than lost in the sum,
            // and per-application disk stays absent because it is blocked (FR-009).
            detail: "Whole machine: \(Presentation.diskThroughput(rates)). "
                + "Disk activity cannot be measured per application.",
            barFraction: nil)
    }

    private static func storageTile(_ volume: VolumeCapacity?) -> MetricTile {
        guard let volume else {
            return MetricTile(
                id: "storage", label: "Storage free", value: "Unavailable",
                isAvailable: false,
                detail: "The startup volume did not report its capacity.",
                barFraction: nil)
        }
        let used = 1 - volume.availableFraction
        return MetricTile(
            id: "storage", label: "Storage free",
            value: bytes(Double(volume.availableBytes)), isAvailable: true,
            // Purgeable space is deliberately not added in: it is an estimate of
            // what macOS thinks it could reclaim, not space you have (FR-041).
            detail: "\(bytes(Double(volume.availableBytes))) available of "
                + "\(bytes(Double(volume.totalBytes))) on \(volume.name).",
            barFraction: used)
    }

    private static func bytes(_ value: Double) -> String {
        ByteCountFormatStyle().format(Int64(max(0, value)))
    }

    // MARK: - Contributors

    /// A row of "Using the most CPU now".
    ///
    /// Unattributed system activity is one of these rather than a footnote: it is
    /// routinely one of the largest entries, and demoting it would let the visible
    /// rows appear to account for the machine when they do not (FR-013, FR-038).
    struct ContributorRow: Identifiable, Equatable {
        enum Kind: Equatable {
            case application
            /// Processes owned by another uid, which we are not permitted to measure.
            case unattributed
            /// Measured, but not large enough to list individually.
            case other
        }

        let id: String
        let kind: Kind
        let name: String
        /// Processes in the family. 1 for a standalone process.
        let processCount: Int
        /// Some members of this family could not be measured, so its figure is a
        /// floor rather than a total.
        let isPartial: Bool
        let percentOfOneCore: Double
        let executablePath: String?
    }

    static func contributorRows(
        families: [MonitorStore.FamilyRow],
        attributedPercentOfOneCore: Double,
        unattributedPercentOfOneCore: Double,
        limit: Int = 3
    ) -> [ContributorRow] {
        // A family with no CPU has no place under "using the most CPU now", even
        // though it earns its row in the inventory on memory alone.
        let leading = families.filter { $0.percentOfOneCore > 0 }.prefix(limit)

        var rows = leading.map { row in
            ContributorRow(
                id: row.id,
                kind: .application,
                name: row.family.displayName,
                processCount: row.processCount,
                isPartial: row.family.notMeasurableCount > 0,
                percentOfOneCore: row.percentOfOneCore,
                executablePath: row.family.members.first?.resolved.executablePath)
        }

        rows.append(ContributorRow(
            id: "unattributed", kind: .unattributed,
            name: "Unattributed system activity",
            processCount: 0, isPartial: false,
            percentOfOneCore: unattributedPercentOfOneCore,
            executablePath: nil))

        rows.sort { $0.percentOfOneCore > $1.percentOfOneCore }

        // Everything measured but not shown individually. Without it the visible
        // rows would not sum to the total — the same failure the unattributed row
        // prevents, arriving by truncation instead of by permissions.
        let remainder = attributedPercentOfOneCore
            - leading.reduce(0) { $0 + $1.percentOfOneCore }
        if remainder > 0.5 {
            rows.append(ContributorRow(
                id: "other", kind: .other, name: "Other applications",
                processCount: 0, isPartial: false,
                percentOfOneCore: remainder, executablePath: nil))
        }

        return rows
    }

    /// The spoken form of a contributor row, so VoiceOver hears the qualifiers
    /// that sighted users read as "· 9 processes" and "(partial)" (FR-034).
    static func accessibilityLabel(for row: ContributorRow) -> String {
        var parts = [row.name]
        if row.processCount > 1 { parts.append("\(row.processCount) processes") }
        if row.isPartial { parts.append("partly measured") }
        parts.append("\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core")
        return parts.joined(separator: ", ")
    }

    /// Why a family's figure is marked partial.
    static let partialExplanation =
        "Some processes in this application are owned by another user account, "
        + "which App Store apps are not permitted to measure. This figure is at "
        + "least this much, and may be more."
}
