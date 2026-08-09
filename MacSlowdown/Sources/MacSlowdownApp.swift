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
    static let id = "main"
}
