import AppKit

/// Window activation for a menu bar utility that also has a real main window.
///
/// `LSUIElement` launches the app with `.accessory` activation policy, which keeps
/// it out of the Dock and app switcher — correct for the menu bar surface. But an
/// accessory app cannot raise a window above other applications: `openWindow`
/// succeeds and the window is created at the right position, yet stays behind
/// whatever was in front, making it effectively unreachable.
///
/// Switching to `.regular` while the main window is open makes it activatable, and
/// switching back on close keeps the Dock clean the rest of the time.
@MainActor
enum ActivationPolicy {
    static func mainWindowOpened() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func mainWindowClosed() {
        // Hiding the menu bar item removes the only always-visible surface, so the
        // app must keep a Dock icon or it becomes unreachable while still running.
        let menuBarHidden = !UserDefaults.standard.bool(forKey: "showMenuBarItem")
            && UserDefaults.standard.object(forKey: "showMenuBarItem") != nil
        NSApp.setActivationPolicy(menuBarHidden ? .regular : .accessory)
    }

    static func menuBarItemVisibilityChanged(isVisible: Bool) {
        if !isVisible {
            NSApp.setActivationPolicy(.regular)
        }
    }
}

/// The one way AppKit code can open the SwiftUI main window.
///
/// `openWindow` exists only in the SwiftUI environment, and `AppDelegate` has no
/// environment. That gap is what stranded the app: with the menu bar item hidden a
/// launch can reach a Dock click having never created the `Window` scene, and
/// AppKit's default reopen behaviour can only restore a window that already
/// exists. So the App registers its `openWindow` here at launch and the delegate
/// calls through it.
///
/// Deliberately holds no `NSApp` call of its own — activation is the registered
/// action's business (and `MainWindowView.onAppear`'s), which keeps this reachable
/// from a test without putting a Dock icon on the developer's screen.
@MainActor
enum MainWindowOpener {
    /// Set once by `MacSlowdownApp`; nil before the first scene evaluation, and in
    /// tests that substitute their own.
    static var action: (() -> Void)?

    /// Returns false when no action has been registered, so a caller can tell
    /// "nothing happened" from "a window was asked for".
    @discardableResult
    static func open() -> Bool {
        guard let action else { return false }
        action()
        return true
    }
}
