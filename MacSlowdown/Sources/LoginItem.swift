import Foundation
import Observation
import ServiceManagement

/// Start-at-login control (FR-033).
///
/// Two rules from the requirement shape this:
///   - **No silent registration.** Nothing here runs at launch; registration only
///     happens when the user asks for it.
///   - **Reported state is the system's, not ours.** `SMAppService.status` is read
///     back after every change and whenever the UI appears, so if the user
///     disables the item in System Settings the app reflects that rather than
///     showing what it last set.
@MainActor
@Observable
final class LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        /// The user disabled it in System Settings; macOS requires them to
        /// re-enable it there, so the app must explain rather than silently fail.
        case requiresApproval
        case unavailable(String)
    }

    private(set) var state: State = .disabled

    init() { refresh() }

    /// Reads the live status. Never registers anything.
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .notRegistered: state = .disabled
        case .requiresApproval: state = .requiresApproval
        case .notFound: state = .unavailable("The app could not be found by the system.")
        @unknown default: state = .unavailable("Unrecognised status.")
        }
    }

    var isEnabled: Bool { state == .enabled }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            state = .unavailable(error.localizedDescription)
            return
        }
        refresh()
    }

    var explanation: String {
        switch state {
        case .enabled:
            "MacSlowdown will start when you log in, so it can catch slowdowns you did not see coming."
        case .disabled:
            "MacSlowdown only runs when you open it, so it will not record slowdowns that happen before then."
        case .requiresApproval:
            "Login items for MacSlowdown are turned off in System Settings. "
                + "Open System Settings › General › Login Items to allow it."
        case .unavailable(let reason):
            "Start at login is unavailable: \(reason)"
        }
    }
}
