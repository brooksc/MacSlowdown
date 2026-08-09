import AppKit

/// Window activation for a menu bar utility that also has a real main window.
///
/// `LSUIElement` launches the app with `.accessory` activation policy, which keeps
/// it out of the Dock and app switcher — correct for the menu bar surface.
///
/// An accessory app **can** be activated and can own the key window; what it does
/// not get is activation for free. A window it orders in while it is not the
/// active application is ordered in *behind* the active application's windows, so
/// it is on screen and invisible. Raising it is `WindowRaiser`'s job, and needs no
/// policy change (TASK-65.20).
///
/// The main window is a different case and keeps its policy switch: it is a
/// full-size document-style window, so while it is open the app behaves like a
/// regular app — Dock icon, app switcher, ⌘-Tab. Switching back on close keeps the
/// Dock clean the rest of the time.
@MainActor
enum ActivationPolicy {
    static func mainWindowOpened() {
        guard !AppDelegate.isHostingTests else { return }
        NSApp.setActivationPolicy(.regular)
        WindowRaiser.activateApp()
    }

    static func mainWindowClosed() {
        guard !AppDelegate.isHostingTests else { return }
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
/// It raises the window it opened, because one caller — a notification action
/// button — reaches here without the app having been activated, and an accessory
/// app's unraised window is invisible (TASK-65.20). Every `NSApp` call it makes is
/// inside `WindowRaiser`, which does nothing under XCTest, so this stays reachable
/// from a test without putting a window or a Dock icon on the developer's screen.
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
        // Two of the three callers are user gestures that have already made the app
        // active — a Dock click, the popover button. The third is a notification
        // action button, which does not activate an accessory app, so the window
        // would open behind everything exactly as first run did (TASK-65.20).
        // Raising an already-frontmost window costs nothing, so this is
        // unconditional rather than a guess about which caller is which.
        //
        // Suppressed under XCTest inside `WindowRaiser`, which is what keeps the
        // reopen tests from putting a window on a developer's screen.
        WindowRaiser.raiseWindow(sceneID: MainWindow.id, title: MainWindow.title)
        return true
    }
}

extension MainWindow {
    /// The `Window` scene's title, as declared in `MacSlowdownApp`. Needed because
    /// matching a SwiftUI scene to its `NSWindow` by identifier alone is not
    /// guaranteed — see `WindowRaiser.matches`.
    static let title = "MacSlowdown"
}

/// Bringing forward a window that the user did not click for.
///
/// **The failure this exists for** (TASK-65.20, measured on screen): the first-run
/// window was created, ordered in, at the right size and position, present in the
/// accessibility tree — and drawn behind every other application. `openWindow`
/// orders a window in; it does not make an inactive application active, and an
/// inactive application's windows sit below the active one's. `AXRaise` fixed it
/// from outside, which is the signature of "ordered in but behind" rather than
/// "never ordered in".
///
/// So the fix is activation, not ordering, and specifically **forced** activation:
/// `NSApp.activate()` alone is subject to macOS's cooperative activation rules and
/// is declined for an app that was launched into the background and holds no
/// activation grant. That call was already there and did not work.
///
/// `orderFrontRegardless()` follows as the belt to the braces: it puts the window
/// in front of other applications' windows whether or not the activation request
/// was honoured, so the worst case is a visible window that is not key rather than
/// a window nobody sees.
///
/// No activation policy change, so **no Dock icon** appears for a window raised
/// this way — `.accessory` apps are documented as activatable, they simply have to
/// ask.
@MainActor
enum WindowRaiser {
    /// A test run must never bring a window to the front of a developer's screen —
    /// the same rule `AppDelegate` applies to launch work.
    private static var isSuppressed: Bool { AppDelegate.isHostingTests }

    static func activateApp() {
        guard !isSuppressed else { return }
        // Deprecated since macOS 14 in favour of `activate()`, and used anyway:
        // `activate()` is the call that was measured failing here. The deprecated
        // form is the only public API that says "come forward regardless", which is
        // the requirement for a screen the user has to read before anything starts.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Activates the app and puts `window` in front. Idempotent.
    static func raise(_ window: NSWindow) {
        guard !isSuppressed else { return }
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Finds a SwiftUI scene's `NSWindow` and raises it.
    ///
    /// Retried, because `openWindow` does not create the window synchronously: it
    /// schedules a scene update, so the window does not exist on the line after the
    /// call. Bounded, because "the window never appeared" has to end.
    static func raiseWindow(sceneID: String, title: String) {
        guard !isSuppressed else { return }
        Task { @MainActor in
            for attempt in 0..<20 {
                if let window = window(sceneID: sceneID, title: title) {
                    raise(window)
                    return
                }
                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    static func window(sceneID: String, title: String) -> NSWindow? {
        NSApp.windows.first {
            matches(
                identifier: $0.identifier?.rawValue,
                windowTitle: $0.title,
                isTitled: $0.styleMask.contains(.titled),
                sceneID: sceneID,
                sceneTitle: title)
        }
    }

    /// Whether an `NSWindow` is the one a `Window(_:id:)` scene produced.
    ///
    /// SwiftUI's mapping from scene id to `NSWindow.identifier` is not contractual,
    /// so the title is kept as a fallback — and the fallback is restricted to
    /// titled windows so that a borderless panel (the menu bar popover) can never
    /// be mistaken for the main window and yanked to the front.
    ///
    /// Pure, and separated from `NSWindow`, so the matching rule is testable
    /// without a window on screen.
    static func matches(
        identifier: String?,
        windowTitle: String,
        isTitled: Bool,
        sceneID: String,
        sceneTitle: String
    ) -> Bool {
        if let identifier, identifier == sceneID || identifier.contains(sceneID) {
            return true
        }
        return isTitled && !sceneTitle.isEmpty && windowTitle == sceneTitle
    }
}
