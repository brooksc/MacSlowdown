import AppKit
import Metrics

/// Hand-offs to the tools that can see what we cannot (FR-017).
///
/// Every entry here opens something and does nothing else. There is no code path
/// in this file that could change how another process runs, which keeps FR-037's
/// "no dormant privileged paths" true by inspection rather than by promise — the
/// same standard `ActionPerformer` is held to.
///
/// The explanations are the point as much as the buttons are. "Open Console" on
/// its own invites the reading that we will then read the report; the sentence
/// beside it says plainly that we cannot and Console can.
struct SystemTool: Identifiable, Equatable {
    enum Target: Equatable {
        /// An application bundle, so its absence can be detected before we claim
        /// to have opened it.
        case application(path: String)
        /// A System Settings pane. There is no filesystem check for one of these,
        /// so `open` reports the outcome instead.
        case settings(url: String)
    }

    let id: String
    let title: String
    /// What this tool can do that we cannot. Shown with the button.
    let explanation: String
    let target: Target

    /// Whether the tool is on this Mac. A settings URL cannot be checked without
    /// opening it, so it is reported as available and the *result* of opening it
    /// is what the caller states (FR-017: never show an action as though it
    /// worked).
    var isPresent: Bool {
        switch target {
        case .application(let path): FileManager.default.fileExists(atPath: path)
        case .settings: true
        }
    }

    static let activityMonitor = SystemTool(
        id: "activityMonitor",
        title: "Open Activity Monitor",
        explanation: "It is part of macOS and asks with more privilege than we have, so it "
            + "can show per-process figures for system processes. If this is happening now, "
            + "sort by CPU there.",
        target: .application(path: "/System/Applications/Utilities/Activity Monitor.app"))

    static let console = SystemTool(
        id: "console",
        title: "Open Console",
        explanation: "macOS writes a report when an application quits unexpectedly. We "
            + "cannot read those reports — they live outside our container. Console can.",
        target: .application(path: "/System/Applications/Utilities/Console.app"))

    static let timeMachine = SystemTool(
        id: "timeMachine",
        title: "Check Time Machine",
        explanation: "Time Machine's own settings show when it last ran and how long it "
            + "took. We can only see that its process was running.",
        target: .settings(url: "x-apple.systempreferences:com.apple.settings.TimeMachine"))

    static let softwareUpdate = SystemTool(
        id: "softwareUpdate",
        title: "Check for a software update",
        explanation: "Software Update reports what it is downloading or installing. We can "
            + "only see whether its process was running.",
        target: .settings(
            url: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"))

    static let appUpdates = SystemTool(
        id: "appUpdates",
        title: "Check for an app update",
        explanation: "A repeated failure is often fixed in a later version. We have no way "
            + "to know whether this one is.",
        target: .settings(url: "macappstore://showUpdatesPage"))

    static let spotlight = SystemTool(
        id: "spotlight",
        title: "Check Spotlight indexing",
        explanation: "Spotlight's settings show what is indexed. We can only see that its "
            + "indexer process was running.",
        target: .settings(url: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"))

    /// Which tool a watched system process points at, so the offer follows the
    /// evidence rather than being a fixed menu. A process being *absent* still
    /// earns its tool: "Software Update was not running" is exactly the case where
    /// a user wants to go and look.
    static let byWatchedCommand: [String: SystemTool] = [
        "backupd": timeMachine,
        "mds_stores": spotlight,
        "mds": spotlight,
        "mdworker_shared": spotlight,
        "corespotlightd": spotlight,
        "softwareupdated": softwareUpdate,
        "suhelperd": softwareUpdate,
        "installd": softwareUpdate,
    ]
}

/// Opens a `SystemTool`, reporting what actually happened.
@MainActor
struct SystemToolOpener {
    func open(_ tool: SystemTool) -> ActionResult {
        switch tool.target {
        case .application(let path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                return .failed(reason: "\(tool.title.replacingOccurrences(of: "Open ", with: "")) "
                    + "was not found on this Mac.")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return .succeeded

        case .settings(let string):
            guard let url = URL(string: string) else {
                return .failed(reason: "That settings pane could not be addressed.")
            }
            return NSWorkspace.shared.open(url)
                ? .succeeded
                : .failed(reason: "macOS did not open that settings pane.")
        }
    }
}
