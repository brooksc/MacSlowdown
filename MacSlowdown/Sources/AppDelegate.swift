import AppKit

/// App lifecycle: starts monitoring and settles the activation policy.
///
/// This lives in a delegate rather than a view's `.task` because neither is
/// guaranteed to render. With the menu bar item hidden there is no always-present
/// view, so a view-driven start meant monitoring never began — the app ran and
/// measured nothing.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when the app is running only to host a unit test bundle.
    ///
    /// App-layer tests have to be hosted by the app to link against it, which means
    /// the real app launches. Starting the sampler and putting a status item in the
    /// developer's menu bar on every test run is a side effect no test asked for,
    /// so both are skipped. This is the only test-aware branch in the app, and it
    /// gates nothing but launch side effects.
    static let isHostingTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isHostingTests else { return }
        let defaults = UserDefaults.standard
        // Absent preference means first launch, where the item is shown.
        let showMenuBarItem = defaults.object(forKey: "showMenuBarItem") as? Bool ?? true
        if !showMenuBarItem {
            // No menu bar item means the Dock icon is the only way back to the app,
            // and `applicationShouldHandleReopen` below is what makes it one.
            //
            // The window is deliberately not opened here: FR-001's objective is
            // noticing degradation *without* opening a full window, so a launch —
            // including a login-item launch — stays quiet.
            NSApp.setActivationPolicy(.regular)
        }
        // Presentation only — this asks for nothing and shows no prompt.
        MonitorStore.shared.notifications.registerForForegroundPresentation()
        MonitorStore.shared.start()
    }

    /// Clicking the Dock icon opens the main window.
    ///
    /// Returning `true` alone is not enough. It only permits AppKit's default
    /// reopen, which restores windows that already exist — and with the menu bar
    /// item hidden the SwiftUI `Window` scene may never have been created in this
    /// launch, leaving a running app with a Dock icon and nothing behind it. So the
    /// window is opened explicitly when there is none visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            MainWindowOpener.open()
        }
        return true
    }

    /// Monitoring is the product; closing the last window must not end it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
