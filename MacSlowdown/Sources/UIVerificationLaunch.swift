import AppKit
import Foundation

/// A launch-argument seam for looking at the app's windows, used for on-screen
/// verification in a VM.
///
/// **Why this exists.** This is an `LSUIElement` app: launching it opens nothing.
/// Its windows are reachable only through the menu bar item, and driving that from
/// a script needs Accessibility permission, which nobody can grant in an unattended
/// virtual machine. So the surfaces that most need looking at — the ones a SwiftUI
/// preview cannot reach, because they are about the *running* application and its
/// real window frame — were the hardest to put in front of a camera.
///
/// This lets a launch tell the app to open a window and start on a chosen section:
///
/// ```
/// MacSlowdown.app/Contents/MacOS/MacSlowdown -ui-open main -ui-section "Apps & Processes"
/// ```
///
/// **It is inert outside a Debug build.** Every accessor is compiled to `nil` when
/// `DEBUG` is not defined, so the shipping build cannot be driven this way, and
/// FR-037's rule against unreachable capability in the shipping build is not
/// strained: there is nothing left to reach.
///
/// It deliberately does *not* fabricate state. It opens a real window on the real
/// store, reading the real machine — it changes which window is showing, and
/// nothing about what the window says.
enum UIVerificationLaunch {
    /// Which window to open at launch: `main` or `first-run`. Nil in release, and
    /// nil when the argument is absent.
    static var requestedWindow: String? { value(for: "-ui-open") }

    /// The sidebar section the main window should start on, by its display name
    /// ("Now", "Apps & Processes", "Incidents", "Storage", "Overview").
    static var requestedSection: String? { value(for: "-ui-section") }

    private static func value(for flag: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
        #else
        // The shipping build ignores these entirely.
        _ = flag
        return nil
        #endif
    }

    /// Opens whatever the launch asked for. Called once, as the scene is built.
    ///
    /// Deferred to the next run-loop turn because the openers are registered during
    /// scene evaluation, and calling one while that is still in progress asks
    /// SwiftUI to open a window out of a scene it has not finished describing.
    static func presentIfRequested() {
        guard let requestedWindow else { return }
        DispatchQueue.main.async {
            switch requestedWindow {
            case "main":
                _ = MainWindowOpener.open()
                // An LSUIElement app is not frontmost on launch, so the window
                // would open behind whatever is there and screenshot as nothing.
                NSApplication.shared.activate(ignoringOtherApps: true)
            case "first-run":
                // No `presentIfNeeded` here: that consults whether first run is
                // already done, and the point is to look at the window regardless.
                FirstRunWindowOpener.action?()
                NSApplication.shared.activate(ignoringOtherApps: true)
            default:
                break
            }
        }
    }
}
