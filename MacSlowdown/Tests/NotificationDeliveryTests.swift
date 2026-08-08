import Foundation
import Testing
import UserNotifications

@testable import MacSlowdown
@testable import Metrics

/// A notification centre that records instead of notifying.
///
/// Exists because the real centre's authorisation belongs to the user and cannot
/// be set from a test. Without it, "never deliver what the gate suppressed" and
/// "never deliver without live authorisation" could only be checked by asking a
/// human for permission and generating a real incident — which is exactly how the
/// foreground-presentation bug went unnoticed until it was verified by hand.
@MainActor
final class FakeNotificationCentre: NotificationCentre {
    var status: UNAuthorizationStatus = .notDetermined
    /// What `requestAuthorization` will grant, and what the status becomes after.
    var grantsOnRequest = true
    var addThrows = false

    private(set) var added: [UNNotificationRequest] = []
    private(set) var statusReads = 0
    private(set) var requestCount = 0
    private(set) var delegate: UNUserNotificationCenterDelegate?

    func authorizationStatus() async -> UNAuthorizationStatus {
        statusReads += 1
        return status
    }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = grantsOnRequest ? .authorized : .denied
        return grantsOnRequest
    }

    func add(_ request: UNNotificationRequest) async throws {
        if addThrows { throw CocoaError(.fileNoSuchFile) }
        added.append(request)
    }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }
}

private func incident(
    severity: IncidentSeverity = .high,
    conditions: Set<IncidentCondition> = [.cpuSaturation],
    minutes: Double = 3
) -> Incident {
    let began = Date().addingTimeInterval(-minutes * 60)
    return Incident(
        id: UUID(), beganAt: began, triggeredAt: began.addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: Date(),
        conditions: conditions, severity: severity,
        peakCPUBusyFraction: 0.95, peakMemoryPressure: .normal)
}

@MainActor
@Suite("Notification delivery")
struct NotificationDeliveryTests {
    @Test("An approved decision is delivered when authorised")
    func deliversWhenApproved() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)

        let sent = await delivery.deliver(
            decision: .send(reason: "first time"), incident: incident(),
            leadingContributor: "bash")

        #expect(sent)
        #expect(centre.added.count == 1)
        #expect(delivery.deliveredCount == 1)
    }

    /// The property the whole design rests on: delivery takes the gate's decision
    /// and has no branch that re-evaluates policy. A suppressed decision must be
    /// undeliverable even when everything else would allow it.
    @Test("A suppressed decision is never delivered, even when fully authorised")
    func neverDeliversSuppressed() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)

        for reason in ["muted", "Focus is on", "already announced this incident",
                       "audio is playing", "you marked Xcode as expected"] {
            let sent = await delivery.deliver(
                decision: .suppress(reason: reason), incident: incident(),
                leadingContributor: "bash")
            #expect(!sent)
        }

        #expect(centre.added.isEmpty)
        #expect(delivery.deliveredCount == 0)
    }

    @Test("Nothing is delivered when the user has denied notifications")
    func deniedDeliversNothing() async {
        let centre = FakeNotificationCentre()
        centre.status = .denied
        let delivery = NotificationDelivery(centre: centre)

        let sent = await delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil)

        #expect(!sent)
        #expect(centre.added.isEmpty)
    }

    @Test("Nothing is delivered before the user has been asked")
    func notDeterminedDeliversNothing() async {
        let centre = FakeNotificationCentre()
        centre.status = .notDetermined
        let delivery = NotificationDelivery(centre: centre)

        #expect(await !delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil))
        #expect(centre.added.isEmpty)
    }

    /// Provisional authorisation delivers quietly. Treating it as denied would
    /// silently drop alerts the system was willing to show.
    @Test("Provisional authorisation still delivers")
    func provisionalDelivers() async {
        let centre = FakeNotificationCentre()
        centre.status = .provisional
        let delivery = NotificationDelivery(centre: centre)

        #expect(await delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil))
        #expect(centre.added.count == 1)
    }

    /// The FR-033 mistake in a different place: a permission revoked in System
    /// Settings must take effect immediately, not at the next launch.
    @Test("Authorisation is re-read on every delivery, never cached")
    func authorisationIsNeverCached() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)

        #expect(await delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil))

        // The user turns notifications off in System Settings.
        centre.status = .denied

        #expect(await !delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil))
        #expect(centre.added.count == 1)
        #expect(delivery.authorisation == .denied)
        #expect(centre.statusReads >= 2, "each delivery must ask the system again")
    }

    @Test("A centre that refuses the request reports failure rather than success")
    func addFailureIsReported() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        centre.addThrows = true
        let delivery = NotificationDelivery(centre: centre)

        #expect(await !delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil))
        #expect(delivery.deliveredCount == 0, "a failed add must not be counted as delivered")
    }
}

@MainActor
@Suite("Notification content")
struct NotificationContentTests {
    @Test("The alert says what happened, for how long, and who contributed")
    func contentMatchesTheGateMessage() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)
        let subject = incident(minutes: 3)

        await delivery.deliver(
            decision: .send(reason: "high"), incident: subject, leadingContributor: "bash")

        let content = try? #require(centre.added.first?.content)
        let expected = NotificationGate.message(for: subject, leadingContributor: "bash")
        #expect(content?.title == expected.title)
        #expect(content?.body == expected.body)
        #expect(content?.body.contains("bash") == true)
    }

    /// FR-013: a contributor we could not identify is omitted, not guessed at.
    @Test("With no identifiable contributor the alert names none")
    func noContributorNamed() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)

        await delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil)

        let body = centre.added.first?.content.body ?? ""
        #expect(!body.contains("contributor"))
        #expect(body.contains("Severity"))
    }

    /// Repeat delivery for the same incident must replace the existing alert
    /// rather than stack a second one, so the identifier has to be the incident's.
    @Test("The request is identified by the incident, so it cannot stack")
    func identifierIsTheIncident() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)
        let subject = incident()

        await delivery.deliver(
            decision: .send(reason: "first"), incident: subject, leadingContributor: nil)
        await delivery.deliver(
            decision: .send(reason: "escalated"), incident: subject, leadingContributor: nil)

        #expect(centre.added.map(\.identifier) == [subject.id.uuidString, subject.id.uuidString])
    }

    @Test("Only a severe incident is time sensitive")
    func interruptionLevelMatchesSeverity() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)

        let severities: [IncidentSeverity] = [.moderate, .high, .severe]
        for severity in severities {
            await delivery.deliver(
                decision: .send(reason: "test"), incident: incident(severity: severity),
                leadingContributor: nil)
        }

        for (index, severity) in severities.enumerated() {
            let level = centre.added[index].content.interruptionLevel
            #expect(level == (severity == .severe ? .timeSensitive : .active))
        }
    }
}

@MainActor
@Suite("Authorisation state")
struct AuthorisationStateTests {
    @Test("Every system status maps to a state we can explain")
    func statusMapping() async {
        let cases: [(UNAuthorizationStatus, NotificationDelivery.Authorisation)] = [
            (.authorized, .authorised),
            (.provisional, .provisional),
            (.denied, .denied),
            (.notDetermined, .notDetermined),
        ]

        for (status, expected) in cases {
            let centre = FakeNotificationCentre()
            centre.status = status
            let delivery = NotificationDelivery(centre: centre)
            await delivery.refreshAuthorisation()
            #expect(delivery.authorisation == expected)
        }
    }

    @Test("Only authorised and provisional can deliver")
    func canDeliver() {
        #expect(NotificationDelivery.Authorisation.authorised.canDeliver)
        #expect(NotificationDelivery.Authorisation.provisional.canDeliver)
        #expect(!NotificationDelivery.Authorisation.denied.canDeliver)
        #expect(!NotificationDelivery.Authorisation.notDetermined.canDeliver)
    }

    @Test("Requesting authorisation reads the result back rather than assuming it")
    func requestReadsBack() async {
        let centre = FakeNotificationCentre()
        centre.grantsOnRequest = true
        let delivery = NotificationDelivery(centre: centre)

        await delivery.requestAuthorisation()
        #expect(delivery.authorisation == .authorised)
        #expect(centre.requestCount == 1)
        #expect(centre.statusReads >= 1, "the state must come from the system, not the request")
    }

    @Test("A refused request leaves the app reporting denied, not authorised")
    func refusedRequest() async {
        let centre = FakeNotificationCentre()
        centre.grantsOnRequest = false
        let delivery = NotificationDelivery(centre: centre)

        await delivery.requestAuthorisation()
        #expect(delivery.authorisation == .denied)
    }

    /// FR-002 and FR-014: a state that stops alerts arriving has to say so, and say
    /// that the evidence is still being kept.
    @Test("Denied explains where the incidents went")
    func deniedExplanation() {
        let text = NotificationDelivery.Authorisation.denied.explanation
        #expect(text.contains("System Settings"))
        #expect(text.lowercased().contains("still recorded"))
    }

    @Test("Every authorisation state has a non-empty explanation")
    func everyStateExplained() {
        let states: [NotificationDelivery.Authorisation] =
            [.notDetermined, .authorised, .provisional, .denied]
        for state in states {
            #expect(!state.explanation.isEmpty)
        }
        #expect(Set(states.map(\.explanation)).count == states.count,
                "states a user must act on differently cannot read identically")
    }

    /// Registering for foreground presentation is what makes an alert visible while
    /// a MacSlowdown window is in front. Delivery succeeding without it produced a
    /// notification nobody saw.
    @Test("Registering sets the delivery object as the centre's delegate")
    func registersDelegate() {
        let centre = FakeNotificationCentre()
        let delivery = NotificationDelivery(centre: centre)

        #expect(centre.delegate == nil)
        delivery.registerForForegroundPresentation()
        #expect(centre.delegate === delivery)
    }

    /// The bug this guards: macOS suppresses banners for the frontmost application
    /// unless the delegate asks for them, so a delivery that "succeeded" showed
    /// nothing while a MacSlowdown window was in front.
    @Test("An alert is presented as a banner even when MacSlowdown is frontmost")
    func presentsInForeground() {
        let options = NotificationDelivery.foregroundPresentationOptions
        #expect(options.contains(.banner))
        #expect(options.contains(.list), "it must also reach Notification Center")
    }
}
