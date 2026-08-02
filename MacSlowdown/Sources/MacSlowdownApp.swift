import SwiftUI

@main
struct MacSlowdownApp: App {
    /// Scene wiring and dependency injection only — no business logic here.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var store: MonitorStore { .shared }

    /// FR-001 requires the status surface be hideable. When it is hidden the app
    /// switches to a regular activation policy so it keeps a Dock icon — otherwise
    /// hiding the only visible surface would strand a running app with no way back.
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarItem) {
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
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView(showMenuBarItem: $showMenuBarItem)
        }
    }
}

struct SettingsView: View {
    @Binding var showMenuBarItem: Bool

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $showMenuBarItem)
                .onChange(of: showMenuBarItem) { _, shown in
                    ActivationPolicy.menuBarItemVisibilityChanged(isVisible: shown)
                }
            Text(showMenuBarItem
                 ? "Monitoring continues whether or not the status item is shown."
                 : "MacSlowdown keeps a Dock icon while the menu bar item is hidden, "
                   + "so you can still reach this window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 380)
    }
}

enum MainWindow {
    static let id = "main"
}
