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
