import Foundation
import Metrics

/// What sits beside the glyph in the menu bar (design 2d, "Optional readout").
///
/// Off by default and it stays that way: the menu bar is the user's, a number
/// there is permanent visual noise, and the design marks icon-only as the default
/// for everyone but power users.
enum MenuBarReadout: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case cpuPercentage
    case sparkline

    static let `default` = MenuBarReadout.iconOnly

    /// The key the preference is stored under. Named here so the view, the
    /// settings control and any test agree on one string.
    static let storageKey = "menuBarReadout"

    var id: String { rawValue }

    /// The design's own wording for the three options.
    var label: String {
        switch self {
        case .iconOnly: "Icon only"
        case .cpuPercentage: "Icon and CPU percentage"
        case .sparkline: "Icon and 60-second trend"
        }
    }

    /// Reads a stored preference, falling back to the default for an absent or
    /// unrecognised value — a preference file edited by hand must not leave the
    /// menu bar in an undefined state.
    static func stored(in defaults: UserDefaults) -> MenuBarReadout {
        guard let raw = defaults.string(forKey: storageKey),
              let readout = MenuBarReadout(rawValue: raw) else { return .default }
        return readout
    }
}

extension MenuBarIcon {
    /// The CPU figure beside the icon, or nil when there is no measurement.
    ///
    /// Nil rather than `"0%"`. Before the first pair of samples there is no rate to
    /// report — a rate needs two readings — and printing zero would present "we
    /// have not measured" as "the machine is idle", which is the fabrication FR-002
    /// forbids. The view renders nil as an em dash with a label that says so.
    ///
    /// Machine-relative, matching every other percentage the app shows at machine
    /// scope (FR-004): 100% is every core busy, not one core busy.
    static func cpuReadout(busyShareOfMachine: Double?) -> String? {
        guard let share = busyShareOfMachine, share.isFinite, share >= 0 else { return nil }
        return "\(Int((share * 100).rounded()))%"
    }

    /// What the CPU readout says to VoiceOver, including when it says nothing.
    static func cpuReadoutAccessibilityLabel(busyShareOfMachine: Double?) -> String {
        guard let text = cpuReadout(busyShareOfMachine: busyShareOfMachine) else {
            return "CPU not measured yet"
        }
        return "CPU \(text) of this machine"
    }

    /// The 60-second sparkline series.
    ///
    /// Drawn from `MonitorStore.retainedSamples` — the series FR-005 actually keeps
    /// — and never from a second series the menu bar accumulated for itself. Two
    /// curves over the same minute that disagreed would be a fabrication in
    /// whichever one was wrong, with no way to tell which.
    static func sparklinePoints(
        retained: [HistorySample],
        now: Date = Date(),
        window: Duration = MenuBarIcon.sparklineWindow
    ) -> [SparklinePoint] {
        let cutoff = now.addingTimeInterval(-window.totalSeconds)
        return SparklinePresentation.totalBusySeries(retained.filter { $0.timestamp >= cutoff })
    }

    /// Whether there is enough retained history for the menu bar curve to mean
    /// anything. When there is not, the view draws nothing at all rather than a
    /// flat line: a flat line in a 40 pt strip reads as "the machine was quiet",
    /// and the truth is "we have not been watching long enough".
    static func canDrawSparkline(_ points: [SparklinePoint]) -> Bool {
        SparklinePresentation.readiness(points) == .ready
    }
}
