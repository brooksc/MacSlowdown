import AppKit
import Metrics
import SwiftUI

/// First run (design 1g, bottom panel).
///
/// It is an introduction, not a second Settings screen: exactly the two
/// permissions the app cannot grant itself, and nothing that already has a home
/// in `SettingsView`.
///
/// Both permissions are asked for **in context**. The notification prompt is a
/// system dialog, and a bare one at launch — before the app has measured anything
/// — asks the user to decide about alerts for events they have not been told
/// about. Here the sentence explaining what will be sent is on screen when the
/// dialog appears.
struct FirstRunView: View {
    let state: FirstRunState
    @Environment(\.dismiss) private var dismiss

    @State private var loginItem = LoginItem()
    @Bindable private var alerts = AlertSettings.shared
    private var notifications: NotificationDelivery { MonitorStore.shared.notifications }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.primary)
                    .padding(.top, 12)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(FirstRunCopy.title)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(FirstRunCopy.promise)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    notificationsRow
                    loginItemRow
                }

                Text(FirstRunCopy.unattributable)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(FirstRunCopy.closing)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(FirstRunCopy.startButton) {
                    state.complete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
        .frame(width: 460)
        .frame(minHeight: 560)
        // Live system state, read on appearance rather than remembered (FR-033).
        .task {
            loginItem.refresh()
            await notifications.refreshAuthorisation()
        }
    }

    // MARK: - Rows

    /// The toggle governs whether MacSlowdown announces anything. Saying yes is
    /// also what triggers the system prompt, the first time — so the permission is
    /// requested by an explicit user action, never at launch.
    private var notificationsRow: some View {
        card(symbol: "bell") {
            Toggle(isOn: Binding(
                get: { alerts.announceIncidents && notifications.authorisation != .denied },
                set: { wanted in
                    alerts.announceIncidents = wanted
                    guard wanted, notifications.authorisation == .notDetermined else { return }
                    Task { await notifications.requestAuthorisation() }
                }
            )) {
                Text(FirstRunCopy.notificationsTitle)
                // The system's answer, once there is one, rather than ours. A
                // denial has to read as a denial here, or the screen claims a
                // permission it does not hold.
                Text(notifications.authorisation == .notDetermined
                     ? FirstRunCopy.notificationsDetail
                     : notifications.authorisation.explanation)
            }
            .disabled(notifications.authorisation == .denied)
        }
    }

    /// Start at login is genuinely unavailable for a copy running outside an
    /// Applications folder — `SMAppService` has nothing to register. The real
    /// state is surfaced rather than a toggle that would appear to work and
    /// silently do nothing (FR-017's rule, and TASK-64's).
    private var loginItemRow: some View {
        card(symbol: "clock") {
            Toggle(isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            )) {
                Text(FirstRunCopy.loginItemTitle)
                Text(loginItem.isAdjustable && !loginItem.isEnabled
                     ? FirstRunCopy.loginItemDetail
                     : loginItem.explanation)
            }
            .disabled(!loginItem.isAdjustable)
        }
    }

    private func card<Content: View>(
        symbol: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}

enum FirstRunWindow {
    static let id = "first-run"
}

/// How the first-run window is raised, mirroring `MainWindowOpener`: a SwiftUI
/// scope is the only thing that can open a window, and the decision to open one
/// is made outside any view.
@MainActor
enum FirstRunWindowOpener {
    static var action: (() -> Void)?

    /// Presents the window once, and only when it is owed. Returns whether it was
    /// opened, so "nothing happened" is distinguishable from "a window was asked
    /// for" — the same reason `MainWindowOpener.open` reports.
    @discardableResult
    static func presentIfNeeded(state: FirstRunState = .shared) -> Bool {
        guard state.shouldPresent, let action else { return false }
        action()
        // MacSlowdown is `LSUIElement`, so a window it opens is not guaranteed to
        // come forward on its own. This is the one moment where being unmissable
        // is correct: the screen exists to be read before monitoring starts.
        //
        // **Not verified on screen** — see the task notes. Whether an accessory
        // application can raise this window without also taking a Dock icon needs
        // someone to look.
        //
        // Skipped under XCTest, for the same reason the rest of the launch work is:
        // a test run must not bring anything to the front of a developer's screen.
        if !AppDelegate.isHostingTests { NSApp.activate() }
        return true
    }

    private static var hasAttempted = false

    /// Called from scene evaluation, which is why the open is deferred: opening a
    /// window while the scene graph is being built is not allowed, and scene
    /// bodies are evaluated more than once, so the attempt is made exactly once.
    ///
    /// Skipped under XCTest for the same reason `AppDelegate` skips its launch
    /// work — a test run must not put a window on the developer's screen.
    static func presentOnceAfterLaunch(state: FirstRunState = .shared) {
        guard !hasAttempted, !AppDelegate.isHostingTests else { return }
        hasAttempted = true
        Task { @MainActor in presentIfNeeded(state: state) }
    }
}
