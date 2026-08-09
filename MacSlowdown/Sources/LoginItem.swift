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
        /// `notFound`, from a copy that is not in an Applications folder. This is
        /// the expected result for a build run out of `.build` or a derived-data
        /// directory — the system has nothing to register — and it is not a fault
        /// in the app. Told apart from a genuine `notFound` so a developer is not
        /// looking at the same sentence a broken install would show (TASK-64).
        case unavailableFromThisLocation(directory: String)
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
        case .notFound:
            if let directory = Self.unregisterableLocation() {
                state = .unavailableFromThisLocation(directory: directory)
            } else {
                state = .unavailable("The app could not be found by the system.")
            }
        @unknown default: state = .unavailable("Unrecognised status.")
        }
    }

    /// The folder this copy runs from, when that folder is one macOS will not
    /// register a login item out of. Nil when the app *is* installed properly, in
    /// which case a `notFound` is a real failure and must read like one.
    static func unregisterableLocation(
        bundleURL: URL = Bundle.main.bundleURL,
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> String? {
        let directory = bundleURL.deletingLastPathComponent()
        let installed = ["/Applications", home.appendingPathComponent("Applications").path]
        if installed.contains(where: { directory.path == $0 || directory.path.hasPrefix($0 + "/") }) {
            return nil
        }
        return directory.path
    }

    var isEnabled: Bool { state == .enabled }

    /// Whether the toggle can do anything at all. A control the system will refuse
    /// should not look operable (FR-017's rule, applied to our own settings).
    var isAdjustable: Bool { Self.isAdjustable(state) }

    static func isAdjustable(_ state: State) -> Bool {
        switch state {
        case .enabled, .disabled: true
        case .requiresApproval, .unavailableFromThisLocation, .unavailable: false
        }
    }

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

    var explanation: String { Self.explanation(for: state) }

    /// Static so every state's wording can be checked, including the two the app
    /// cannot reach on demand: `requiresApproval` needs the user to have disabled
    /// the item in System Settings, and `unavailable` needs a build the system does
    /// not know about.
    static func explanation(for state: State) -> String {
        switch state {
        case .enabled:
            "MacSlowdown will start when you log in, so it can catch slowdowns you did not see coming."
        case .disabled:
            "MacSlowdown only runs when you open it, so it will not record slowdowns that happen before then."
        case .requiresApproval:
            "Login items for MacSlowdown are turned off in System Settings. "
                + "Open System Settings › General › Login Items to allow it."
        case .unavailableFromThisLocation(let directory):
            "Start at login needs MacSlowdown to be in your Applications folder. "
                + "This copy is running from \(directory), and macOS will not register "
                + "a login item from there. Nothing is wrong with the app — move it to "
                + "Applications and open it again."
        case .unavailable(let reason):
            "Start at login is unavailable: \(reason)"
        }
    }
}
