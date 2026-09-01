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
    func setCategories(_ categories: Set<UNNotificationCategory>)
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

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
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

    /// What happened to an incident's alert (FR-014, FR-016).
    ///
    /// Recorded rather than discarded so the Incidents list can say why nothing
    /// interrupted the user. The distinction that matters for FR-015: an incident
    /// raised while alerts are muted is **not alerted**, and is still recorded —
    /// muting suppresses the interruption, never the observation.
    enum AlertOutcome: Equatable {
        case alerted
        case notAlerted(reason: String)

        var wasAlerted: Bool { self == .alerted }

        /// The sentence for the history. It always restates that the incident was
        /// kept, because "not alerted" on its own reads as "not recorded".
        var note: String {
            switch self {
            case .alerted: "You were alerted about this."
            case .notAlerted(let reason): "Not alerted — \(reason). It was still recorded."
            }
        }
    }

    /// The banner's buttons (design 1g).
    enum Action: String {
        case showDetails = "com.brooksc.MacSlowdown.showDetails"
        case muteOneHour = "com.brooksc.MacSlowdown.muteOneHour"

        static let categoryIdentifier = "com.brooksc.MacSlowdown.incident"
        /// The banner offers one duration; the full set lives in the mute sheet.
        static let muteMinutes = 60

        var title: String {
            switch self {
            case .showDetails: "Show details"
            case .muteOneHour: "Mute 1 hour"
            }
        }
    }

    private(set) var authorisation: Authorisation = .notDetermined
    private(set) var deliveredCount = 0

    /// What became of each incident's alert, newest last, bounded so a long-running
    /// monitor cannot grow this without limit.
    private(set) var outcomes: [UUID: AlertOutcome] = [:]
    private var outcomeOrder: [UUID] = []
    private static let retainedOutcomes = 200

    /// Set by the app so the banner's buttons do something. Closures rather than a
    /// direct reference to the store, because a notification action arriving is not
    /// a reason for this type to know what a monitor is.
    var onShowDetails: (() -> Void)?
    var onMute: ((Int) -> Void)?

    private let centre: any NotificationCentre

    init(centre: any NotificationCentre = SystemNotificationCentre()) {
        self.centre = centre
        super.init()
    }

    /// Registers for foreground presentation, and registers the banner's actions.
    ///
    /// Called once from the app delegate, where bundle identity is settled. Without
    /// this, an alert raised while a MacSlowdown window is frontmost goes silently
    /// to Notification Center — measured, not assumed: the first end-to-end test
    /// delivered correctly and showed nothing, because the window was in front.
    func registerForForegroundPresentation() {
        centre.setDelegate(self)
        centre.setCategories([Self.incidentCategory])
    }

    /// The two actions the design puts on the banner. Both are safe: one opens our
    /// own window, the other quietens us. Neither touches another process (FR-037).
    static var incidentCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: Action.categoryIdentifier,
            actions: [Action.showDetails, Action.muteOneHour].map {
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [],
            options: [])
    }

    /// What a tapped action means, separated from the delegate callback that
    /// receives it because `UNNotificationResponse` cannot be constructed, leaving
    /// the callback itself unreachable from a test. This is the part with the
    /// behaviour in it.
    func perform(actionIdentifier: String) {
        switch Action(rawValue: actionIdentifier) {
        case .showDetails:
            onShowDetails?()
        case .muteOneHour:
            onMute?(Action.muteMinutes)
        case nil:
            // `UNNotificationDefaultActionIdentifier` — the body itself was
            // clicked — and anything unrecognised both mean "show me".
            if actionIdentifier == UNNotificationDefaultActionIdentifier {
                onShowDetails?()
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        await MainActor.run { self.perform(actionIdentifier: identifier) }
    }

    /// What became of a given incident's alert, or nil when no decision has been
    /// recorded for it. Nil is not "alerted" and not "suppressed" — it is no
    /// record, and must not be presented as either (FR-002).
    func outcome(for incident: UUID) -> AlertOutcome? { outcomes[incident] }

    private func record(_ outcome: AlertOutcome, for incident: UUID) {
        if outcomes.updateValue(outcome, forKey: incident) == nil {
            outcomeOrder.append(incident)
        }
        while outcomeOrder.count > Self.retainedOutcomes {
            outcomes.removeValue(forKey: outcomeOrder.removeFirst())
        }
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
        guard decision.shouldSend else {
            record(.notAlerted(reason: decision.reason), for: incident.id)
            return false
        }
        await refreshAuthorisation()
        guard authorisation.canDeliver else {
            record(.notAlerted(reason: "notifications are turned off for MacSlowdown"),
                   for: incident.id)
            return false
        }

        let (title, body) = Self.message(
            for: incident, leadingContributor: leadingContributor)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Action.categoryIdentifier
        // Interruption stays gentle: the app is reporting, not demanding.
        content.interruptionLevel = incident.severity == .severe ? .timeSensitive : .active

        let request = UNNotificationRequest(
            identifier: incident.id.uuidString, content: content, trigger: nil)
        do {
            try await centre.add(request)
            deliveredCount += 1
            record(.alerted, for: incident.id)
            return true
        } catch {
            record(.notAlerted(reason: "the system did not accept the notification"),
                   for: incident.id)
            return false
        }
    }

    // MARK: - Wording

    /// The banner's text (design 1g).
    ///
    /// **The banner says only what is wrong.** It used to append a clause saying
    /// what is not — "Memory pressure stayed normal", "The machine did not report
    /// thermal pressure" — on the reasoning that naming only the failing resource
    /// invites the reader to assume the machine is failing generally.
    ///
    /// That reasoning is sound about a report and wrong about a banner. Seen in
    /// Notification Centre on 2026-08-31, four consecutive alerts each spent their
    /// last and most expensive sentence on a negative finding, and the product
    /// owner's judgement was that it is noise the reader pays for every time: the
    /// risk a notification actually runs is not being misunderstood, it is being
    /// switched off.
    ///
    /// Nothing is lost by dropping it, which is what makes this safe rather than
    /// merely shorter. The same clauses are already derived once in
    /// `IncidentSummary.ruledOut` and shown under "Ruled out" in the incident
    /// detail — a surface with room for them, reached by a reader who went looking.
    /// This is FR-060's rule applied in the direction it is usually read backwards:
    /// one fact, one home, and the summary is the home.
    static func message(
        for incident: Incident, leadingContributor: String?
    ) -> (title: String, body: String) {
        NotificationGate.message(for: incident, leadingContributor: leadingContributor)
    }
}
