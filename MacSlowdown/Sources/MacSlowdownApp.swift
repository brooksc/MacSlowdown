import ServiceManagement
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
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView(showMenuBarItem: $showMenuBarItem)
        }
    }
}

struct SettingsView: View {
    @Binding var showMenuBarItem: Bool
    @State private var loginItem = LoginItem()
    private var notifications: NotificationDelivery { MonitorStore.shared.notifications }

    var body: some View {
        Form {
            Section {
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

            Section {
                Toggle("Start at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .disabled(loginItem.state == .requiresApproval)

                Text(loginItem.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if loginItem.state == .requiresApproval {
                    Button("Open Login Items in System Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section {
                // Asking here rather than at launch: the prompt is a system dialog,
                // and a monitor that interrupts you before it has measured anything
                // has nothing to say yet. FR-014's alerts are useful only once there
                // is an incident to alert about.
                LabeledContent("Notifications") {
                    switch notifications.authorisation {
                    case .notDetermined:
                        Button("Allow notifications…") {
                            Task { await notifications.requestAuthorisation() }
                        }
                    case .denied:
                        Button("Open Notification Settings") {
                            if let url = URL(string:
                                "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    case .authorised, .provisional:
                        Text("Allowed").foregroundStyle(.secondary)
                    }
                }

                Text(notifications.authorisation.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 420)
        // Read the live system state whenever this appears, so a change made in
        // System Settings is reflected rather than whatever we last set (FR-033).
        .onAppear {
            loginItem.refresh()
            Task { await notifications.refreshAuthorisation() }
        }
    }
}

enum MainWindow {
    static let id = "main"
}
