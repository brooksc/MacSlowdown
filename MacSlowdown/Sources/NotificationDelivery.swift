import Foundation
import Metrics
import Observation
import UserNotifications

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
final class NotificationDelivery {
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

    /// Resolved on first use, never at init.
    ///
    /// `UNUserNotificationCenter.current()` raises when the calling process has no
    /// usable bundle identity, and this object is constructed while `MonitorStore`
    /// is being built during scene evaluation — a raise there takes the whole
    /// interface down while leaving the process alive, which is very hard to
    /// diagnose. Nothing should need the notification centre until something is
    /// actually being delivered or displayed.
    private var center: UNUserNotificationCenter { .current() }

    /// Reads live state. Called whenever settings appear, so a change made in
    /// System Settings is reflected rather than whatever we last requested.
    func refreshAuthorisation() async {
        let settings = await center.notificationSettings()
        authorisation = switch settings.authorizationStatus {
        case .authorized: .authorised
        case .provisional: .provisional
        case .denied: .denied
        default: .notDetermined
        }
    }

    /// Asks the user. Shows a system prompt, so only call it from an explicit
    /// user action — never at launch.
    func requestAuthorisation() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
            try await center.add(request)
            deliveredCount += 1
            return true
        } catch {
            return false
        }
    }
}
