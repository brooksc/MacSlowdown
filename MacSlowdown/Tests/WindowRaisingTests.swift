import AppKit
import Testing

@testable import MacSlowdown

/// TASK-65.20. The first-run window was created, ordered in, correctly sized and
/// positioned, present in the accessibility tree — and invisible, because an
/// accessory application that has not been activated has its windows ordered in
/// behind the active application's.
///
/// What a test can hold is the two halves either side of the screen: that the rule
/// for finding a scene's window is right, and that none of this fires during a test
/// run. Whether the window is actually frontmost on a cold launch is a screen
/// observation, recorded as such on the task.
@MainActor
@Suite("Raising a window nobody clicked for")
struct WindowRaisingTests {
    /// A window ordered in but never made visible: safe to create in a test,
    /// because nothing is put on screen unless something orders it front — which
    /// is precisely the thing being asserted against.
    private func offScreenWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test("A test run is a suppressed run")
    func testsAreHostingTests() {
        #expect(AppDelegate.isHostingTests,
                "every screen-touching guard in the app hangs off this")
    }

    @Test("Raising does nothing under XCTest, so no test puts a window on screen")
    func raiseIsSuppressedUnderTests() {
        let window = offScreenWindow()
        let wasActive = NSApp.isActive
        #expect(!window.isVisible)

        WindowRaiser.raise(window)
        WindowRaiser.raiseWindow(sceneID: FirstRunWindow.id, title: FirstRunWindow.title)
        WindowRaiser.activateApp()

        #expect(!window.isVisible, "a test must not order a window in")
        #expect(!window.isKeyWindow)
        #expect(NSApp.isActive == wasActive, "a test must not steal activation")
    }

    /// The other half of the same property: opening the main window from the
    /// reopen seam raises it in the shipping app and does nothing here.
    @Test("Opening the main window under XCTest changes no activation state")
    func openIsSuppressedUnderTests() {
        let previous = MainWindowOpener.action
        defer { MainWindowOpener.action = previous }
        var opened = 0
        MainWindowOpener.action = { opened += 1 }

        let policy = NSApp.activationPolicy()
        let wasActive = NSApp.isActive
        #expect(MainWindowOpener.open())

        #expect(opened == 1, "TASK-11.1's route still runs the registered action")
        #expect(NSApp.activationPolicy() == policy)
        #expect(NSApp.isActive == wasActive)
    }

    /// The main window's policy switch is the one place a Dock icon is intended —
    /// and it must not happen during a test run either.
    @Test("The main window's activation policy switch is skipped under XCTest")
    func mainWindowPolicyIsSuppressedUnderTests() {
        let policy = NSApp.activationPolicy()
        ActivationPolicy.mainWindowOpened()
        #expect(NSApp.activationPolicy() == policy)
        ActivationPolicy.mainWindowClosed()
        #expect(NSApp.activationPolicy() == policy)
    }

    // MARK: - Finding the window

    @Test("A window is matched by its scene identifier")
    func matchesByIdentifier() {
        #expect(WindowRaiser.matches(
            identifier: FirstRunWindow.id, windowTitle: "", isTitled: true,
            sceneID: FirstRunWindow.id, sceneTitle: FirstRunWindow.title))
        // SwiftUI decorates the identifier in some releases; the id is still in it.
        #expect(WindowRaiser.matches(
            identifier: "SwiftUI.Window-1.0.0-\(MainWindow.id)", windowTitle: "",
            isTitled: true, sceneID: MainWindow.id, sceneTitle: MainWindow.title))
    }

    @Test("Failing that, a titled window is matched by its title")
    func matchesByTitle() {
        #expect(WindowRaiser.matches(
            identifier: nil, windowTitle: FirstRunWindow.title, isTitled: true,
            sceneID: FirstRunWindow.id, sceneTitle: FirstRunWindow.title))
    }

    /// The menu bar popover is a borderless panel with no identifier of ours.
    /// Dragging it to the front on a notification action would be a worse bug than
    /// the one being fixed.
    @Test("An untitled panel is never mistaken for the window")
    func borderlessPanelIsNotMatched() {
        #expect(!WindowRaiser.matches(
            identifier: nil, windowTitle: MainWindow.title, isTitled: false,
            sceneID: MainWindow.id, sceneTitle: MainWindow.title))
        #expect(!WindowRaiser.matches(
            identifier: nil, windowTitle: "", isTitled: false,
            sceneID: MainWindow.id, sceneTitle: MainWindow.title))
    }

    @Test("An unrelated window is not matched")
    func unrelatedWindowIsNotMatched() {
        #expect(!WindowRaiser.matches(
            identifier: "settings", windowTitle: "Settings", isTitled: true,
            sceneID: FirstRunWindow.id, sceneTitle: FirstRunWindow.title))
    }

    /// Two scenes, two ids, two titles — and neither may answer for the other.
    @Test("The two scenes do not collide")
    func scenesAreDistinct() {
        #expect(MainWindow.id != FirstRunWindow.id)
        #expect(MainWindow.title != FirstRunWindow.title)
        #expect(!WindowRaiser.matches(
            identifier: FirstRunWindow.id, windowTitle: FirstRunWindow.title,
            isTitled: true, sceneID: MainWindow.id, sceneTitle: MainWindow.title))
    }

    /// The live app: whichever windows exist during a test run, none of them is the
    /// first-run window, because the test host never presents it.
    @Test("The hosting app has no first-run window open")
    func hostAppHasNoFirstRunWindow() {
        #expect(WindowRaiser.window(
            sceneID: FirstRunWindow.id, title: FirstRunWindow.title) == nil)
    }
}
