import Foundation
import Metrics
import Observation
import UserNotifications

/// The part of `UNUserNotificationCenter` this app uses.
///
/// A seam, for the same reason `ProcessSampler` has one: the real centre is a
/// process-wide singleton whose authorisation state belongs to the user and
/// cannot be set from a test. Without this, the rules that matter — never deliver
/// what the gate suppressed, never deliver without live authorisation — could
/// only be checked by asking a human to grant permission and generating a real
/// incident.
@MainActor
protocol NotificationCentre {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
}

/// The real notification centre.
///
/// `UNUserNotificationCenter.current()` is resolved per call, never stored. It
/// raises when the calling process has no usable bundle identity, and this type
/// is constructed while `MonitorStore` is being built during scene evaluation —
/// a raise there takes the whole interface down while leaving the process alive,
/// which is very hard to attribute.
@MainActor
struct SystemNotificationCentre: NotificationCentre {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
    }
}

/// Delivers notifications the policy gate has approved (FR-014).
///
/// Two rules this enforces, both easy to get wrong:
///   - **Authorisation state is read from the system, never remembered.** A user
///     can revoke notification permission in System Settings at any time; caching
///     what we last requested would leave the app claiming it can notify when it
///     cannot, which is the FR-033 mistake in a different place.
///   - **Nothing is delivered that the gate suppressed.** Delivery takes an
///     already-made decision rather than re-deciding, so there is no second code
///     path where a muted or Focus-suppressed alert could slip through.
@MainActor
@Observable
final class NotificationDelivery: NSObject, UNUserNotificationCenterDelegate {
    enum Authorisation: Equatable {
        case notDetermined
        case authorised
        case denied
        case provisional

        var canDeliver: Bool { self == .authorised || self == .provisional }

        /// Stated plainly so settings can explain why alerts are not arriving,
        /// rather than silently failing.
        var explanation: String {
            switch self {
            case .notDetermined:
                "MacSlowdown has not asked to send notifications yet."
            case .authorised:
                "Notifications are allowed."
            case .provisional:
                "Notifications are delivered quietly, without alerting you."
            case .denied:
                "Notifications are turned off for MacSlowdown in System Settings. "
                    + "Incidents are still recorded and waiting in the Incidents list."
            }
        }
    }

    private(set) var authorisation: Authorisation = .notDetermined
    private(set) var deliveredCount = 0

    private let centre: any NotificationCentre

    init(centre: any NotificationCentre = SystemNotificationCentre()) {
        self.centre = centre
        super.init()
    }

    /// Registers for foreground presentation.
    ///
    /// Called once from the app delegate, where bundle identity is settled. Without
    /// this, an alert raised while a MacSlowdown window is frontmost goes silently
    /// to Notification Center — measured, not assumed: the first end-to-end test
    /// delivered correctly and showed nothing, because the window was in front.
    func registerForForegroundPresentation() {
        centre.setDelegate(self)
    }

    /// Shows the alert even when MacSlowdown is the active application. The gate
    /// has already decided this is worth interrupting for; whether our own window
    /// happens to be in front is not a reason to withhold it.
    ///
    /// A named constant because `UNNotification` cannot be constructed, so the
    /// delegate method itself is unreachable from a test. This is the part that
    /// carries the meaning.
    nonisolated static let foregroundPresentationOptions: UNNotificationPresentationOptions =
        [.banner, .list]

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentationOptions
    }

    /// Reads live state. Called whenever settings appear, so a change made in
    /// System Settings is reflected rather than whatever we last requested.
    func refreshAuthorisation() async {
        authorisation = switch await centre.authorizationStatus() {
        case .authorized: .authorised
        case .provisional: .provisional
        case .denied: .denied
        default: .notDetermined
        }
    }

    /// Asks the user. Shows a system prompt, so only call it from an explicit
    /// user action — never at launch.
    func requestAuthorisation() async {
        _ = await centre.requestAuthorization()
        await refreshAuthorisation()
    }

    /// Delivers an approved decision.
    ///
    /// Takes the decision rather than the incident, so this cannot deliver
    /// something the gate declined: there is no branch here that evaluates policy.
    @discardableResult
    func deliver(
        decision: NotificationDecision,
        incident: Incident,
        leadingContributor: String?
    ) async -> Bool {
        guard decision.shouldSend else { return false }
        await refreshAuthorisation()
        guard authorisation.canDeliver else { return false }

        let (title, body) = NotificationGate.message(
            for: incident, leadingContributor: leadingContributor)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Interruption stays gentle: the app is reporting, not demanding.
        content.interruptionLevel = incident.severity == .severe ? .timeSensitive : .active

        let request = UNNotificationRequest(
            identifier: incident.id.uuidString, content: content, trigger: nil)
        do {
            try await centre.add(request)
            deliveredCount += 1
            return true
        } catch {
            return false
        }
    }
}
