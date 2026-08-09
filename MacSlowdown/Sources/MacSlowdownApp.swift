import SwiftUI

@main
struct MacSlowdownApp: App {
    /// Scene wiring and dependency injection only — no business logic here.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var store: MonitorStore { .shared }

    /// FR-001 requires the status surface be hideable. When it is hidden the app
    /// switches to a regular activation policy so it keeps a Dock icon, and
    /// `AppDelegate.applicationShouldHandleReopen` opens this window when that icon
    /// is clicked. Both halves are needed: the Dock icon alone was not a way back,
    /// because a `Window` scene that never opened has nothing for AppKit to restore.
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    /// Only a SwiftUI scope can hold this; the delegate reaches it via
    /// `MainWindowOpener`.
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Registered on scene evaluation, which happens whether or not the menu bar
        // item is inserted and whether or not a window is ever opened.
        let open = openWindow
        MainWindowOpener.action = { open(id: MainWindow.id) }
        // Same mechanism, same reason: only a SwiftUI scope can open a window, and
        // the decision to open the first-run one is made outside any view.
        FirstRunWindowOpener.action = { open(id: FirstRunWindow.id) }
        // The banner's buttons (design 1g). Wired here rather than inside
        // `NotificationDelivery` so that type does not have to know what a monitor
        // or a window is.
        store.notifications.onShowDetails = { MainWindowOpener.open() }
        store.notifications.onMute = { minutes in store.mute(forMinutes: minutes) }
        FirstRunWindowOpener.presentOnceAfterLaunch()
        return scenes
    }

    @SceneBuilder private var scenes: some Scene {
        MenuBarExtra(isInserted: .init(
            get: { showMenuBarItem && !AppDelegate.isHostingTests },
            set: { showMenuBarItem = $0 })) {
            MenuBarContentView(store: store)
        } label: {
            // The label changes shape with severity, not only colour (FR-034).
            //
            // Monitoring starts here rather than on a window: the menu bar item is
            // the only always-present surface, and FR-001's whole point is noticing
            // degradation without opening anything.
            Image(systemName: store.severity.symbolName)
                .accessibilityLabel("MacSlowdown: \(store.severity.label)")
        }
        .menuBarExtraStyle(.window)

        Window("MacSlowdown", id: MainWindow.id) {
            MainWindowView(store: store)
                // The mute sheet needs a window to sit in, and this is the only
                // one that is always available while the app has a menu bar.
                .muteAlertsSheet(store: store)
        }
        // TASK-75: without this the window adopts whatever height its content says
        // it would ideally like, which on the Apps & Processes screen was 3599 pt on
        // a 1107 pt display — and a window dragged back to a sensible size sprang
        // straight out again. `contentMinSize` keeps the content's *minimum*
        // honoured, so nothing is ever squeezed to illegibility, while leaving the
        // actual size to `defaultSize` and to the user.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Mute Alerts…") { MuteSheetPresenter.shared.present() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
            }
        }

        // First run (design 1g). A `Window` rather than a sheet: at first launch
        // there may be no window for a sheet to attach to — the app is a menu bar
        // utility and opens nothing by default.
        Window("Welcome to MacSlowdown", id: FirstRunWindow.id) {
            FirstRunView(state: .shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        Settings {
            SettingsView(showMenuBarItem: $showMenuBarItem)
        }
    }
}

enum MainWindow {
    /// Changed from `"main"` for TASK-75, and the rename is the point.
    ///
    /// AppKit autosaves the window's frame and the split view's subview frames under
    /// keys derived from this identifier, and every machine that ran the broken
    /// build has `NSWindow Frame main = 120 -2526 1300 3599` and a
    /// `NSSplitView Subview Frames main, SidebarNavigationSplitView` recording
    /// 9932 pt saved in its container. Those would be restored on the next launch
    /// and the window would reopen 3599 pt tall and mostly off the top of the
    /// screen, with the fix in place and apparently not working. A new identifier
    /// retires both entries at once. The cost is that a window position the user
    /// chose is forgotten once; the alternative is a window they cannot see.
    static let id = "main-v2"
}
