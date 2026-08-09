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
    private(set) var categories: Set<UNNotificationCategory> = []

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

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
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

        let suppressions: [(String, SuppressionCause)] = [
            ("muted", .muted),
            ("Focus is on", .focus),
            ("already announced this incident", .alreadyAnnounced),
            ("audio is playing", .audio),
            ("you marked Xcode as expected", .applicationPolicy(application: "Xcode")),
        ]
        for (reason, cause) in suppressions {
            let sent = await delivery.deliver(
                decision: .suppress(reason: reason, cause: cause), incident: incident(),
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
        let expected = NotificationDelivery.message(for: subject, leadingContributor: "bash")
        #expect(content?.title == expected.title)
        #expect(content?.body == expected.body)
        #expect(content?.body.contains("bash") == true)
        #expect(content?.title
            == NotificationGate.message(for: subject, leadingContributor: "bash").title,
            "the title is the gate's, shared with everything else that describes an incident")
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

/// Design 1g: the banner says what is *not* wrong as well as what is, and carries
/// two actions.
@MainActor
@Suite("The banner (design 1g)")
struct NotificationBannerTests {
    /// A notification naming only the failing resource invites the reader to
    /// assume the machine is failing generally, and they then act on a belief the
    /// app never measured.
    @Test("A CPU incident with normal memory says memory pressure stayed normal")
    func statesWhatIsNotWrong() {
        let subject = incident(conditions: [.cpuSaturation])
        let body = NotificationDelivery.message(
            for: subject, leadingContributor: "Xcode").body

        #expect(body.contains("Xcode"), "what is wrong")
        #expect(body.contains("Memory pressure stayed normal"), "and what is not")
    }

    /// The reassurance is a measurement, not politeness: it is withheld when the
    /// evidence does not support it.
    @Test("Memory is never called fine when memory was the problem")
    func noFalseReassurance() {
        let underPressure = Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(),
            recoveryStartedAt: nil, closedAt: Date(),
            conditions: [.cpuSaturation, .memoryPressure], severity: .high,
            peakCPUBusyFraction: 0.95, peakMemoryPressure: .critical)

        let body = NotificationDelivery.message(
            for: underPressure, leadingContributor: nil).body
        #expect(!body.contains("Memory pressure stayed normal"))
    }

    /// The condition never opened, but the peak reading did rise. Two pieces of
    /// evidence are required before the app tells someone their memory is fine.
    @Test("A memory peak above normal withholds the memory reassurance")
    func peakContradictsTheCondition() {
        let spiked = Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(),
            recoveryStartedAt: nil, closedAt: Date(),
            conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.95, peakMemoryPressure: .warning)

        let reassurance = NotificationDelivery.reassurance(for: spiked)
        #expect(reassurance?.contains("Memory") != true)
        #expect(reassurance == "The machine did not report thermal pressure.",
                "it falls through to something the incident does support")
    }

    @Test("An incident breaching everything we watch claims nothing is fine")
    func nothingToReassureAbout() {
        let everything = Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(),
            recoveryStartedAt: nil, closedAt: Date(),
            conditions: Set(IncidentCondition.allCases), severity: .severe,
            peakCPUBusyFraction: 1, peakMemoryPressure: .critical)

        #expect(NotificationDelivery.reassurance(for: everything) == nil)
        let body = NotificationDelivery.message(
            for: everything, leadingContributor: nil).body
        #expect(body == NotificationGate.message(
            for: everything, leadingContributor: nil).body)
    }

    @Test("Only one reassurance is offered, so the banner stays readable")
    func atMostOneClause() {
        let text = NotificationDelivery.reassurance(for: incident()) ?? ""
        #expect(text.filter { $0 == "." }.count == 1)
    }

    @Test("The banner carries a details action and a mute action")
    func bothActionsAreOffered() {
        let category = NotificationDelivery.incidentCategory
        let identifiers = category.actions.map(\.identifier)
        #expect(identifiers.contains(NotificationDelivery.Action.showDetails.rawValue))
        #expect(identifiers.contains(NotificationDelivery.Action.muteOneHour.rawValue))
        #expect(category.actions.map(\.title) == ["Show details", "Mute 1 hour"])
    }

    /// Actions registered with the system, or the buttons never appear no matter
    /// what the category says.
    @Test("Registering installs the category the alerts are sent under")
    func categoryIsRegistered() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)
        delivery.registerForForegroundPresentation()

        #expect(centre.categories.map(\.identifier)
            == [NotificationDelivery.Action.categoryIdentifier])

        await delivery.deliver(
            decision: .send(reason: "high"), incident: incident(), leadingContributor: nil)
        #expect(centre.added.first?.content.categoryIdentifier
            == NotificationDelivery.Action.categoryIdentifier)
    }

    @Test("Show details opens the app; Mute 1 hour mutes for exactly an hour")
    func actionsDoWhatTheySay() {
        let delivery = NotificationDelivery(centre: FakeNotificationCentre())
        var shown = 0
        var mutedFor: [Int] = []
        delivery.onShowDetails = { shown += 1 }
        delivery.onMute = { mutedFor.append($0) }

        delivery.perform(actionIdentifier: NotificationDelivery.Action.showDetails.rawValue)
        #expect(shown == 1)
        #expect(mutedFor.isEmpty)

        delivery.perform(actionIdentifier: NotificationDelivery.Action.muteOneHour.rawValue)
        #expect(mutedFor == [60])
        #expect(shown == 1, "muting must not also open a window")
    }

    @Test("Clicking the banner itself shows details")
    func defaultActionShowsDetails() {
        let delivery = NotificationDelivery(centre: FakeNotificationCentre())
        var shown = 0
        delivery.onShowDetails = { shown += 1 }

        delivery.perform(actionIdentifier: UNNotificationDefaultActionIdentifier)
        #expect(shown == 1)
    }

    /// Dismissing is not a request for anything.
    @Test("An unrecognised action does nothing")
    func unknownActionIsInert() {
        let delivery = NotificationDelivery(centre: FakeNotificationCentre())
        var touched = false
        delivery.onShowDetails = { touched = true }
        delivery.onMute = { _ in touched = true }

        delivery.perform(actionIdentifier: UNNotificationDismissActionIdentifier)
        #expect(!touched)
    }
}

/// FR-015: muting suppresses the interruption and never the record.
@MainActor
@Suite("Alert outcomes")
struct AlertOutcomeTests {
    @Test("An incident that was announced is recorded as alerted")
    func alertedIsRecorded() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)
        let subject = incident()

        await delivery.deliver(
            decision: .send(reason: "new high incident"), incident: subject,
            leadingContributor: nil)

        #expect(delivery.outcome(for: subject.id) == .alerted)
    }

    /// The property criterion 3 rests on: the suppression is recorded against the
    /// incident, so the history can say the incident happened *and* that nothing
    /// interrupted the user — rather than the incident simply vanishing.
    @Test("An incident raised while muted is recorded as not alerted, with the reason")
    func mutedIsRecordedAsNotAlerted() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)
        let subject = incident()

        let sent = await delivery.deliver(
            decision: .suppress(reason: "alerts are muted for another 42 minutes",
                                cause: .muted),
            incident: subject, leadingContributor: "Xcode")

        #expect(!sent)
        #expect(centre.added.isEmpty, "nothing interrupted the user")
        #expect(delivery.outcome(for: subject.id)
            == .notAlerted(reason: "alerts are muted for another 42 minutes"))
        let note = delivery.outcome(for: subject.id)?.note ?? ""
        #expect(note.hasPrefix("Not alerted"))
        #expect(note.contains("still recorded"),
                "\"not alerted\" alone reads as \"not recorded\"")
    }

    @Test("A denial is recorded too, so the silence is explainable")
    func denialIsRecorded() async {
        let centre = FakeNotificationCentre()
        centre.status = .denied
        let delivery = NotificationDelivery(centre: centre)
        let subject = incident()

        await delivery.deliver(
            decision: .send(reason: "high"), incident: subject, leadingContributor: nil)

        #expect(delivery.outcome(for: subject.id)?.wasAlerted == false)
        #expect(delivery.outcome(for: subject.id)?.note.contains("turned off") == true)
    }

    /// FR-002: no record is not the same as "not alerted", and must not be shown
    /// as either.
    @Test("An incident no decision was made about has no outcome")
    func noDecisionIsNotAnOutcome() {
        let delivery = NotificationDelivery(centre: FakeNotificationCentre())
        #expect(delivery.outcome(for: UUID()) == nil)
    }

    @Test("The record is bounded, so a long-running monitor cannot grow it forever")
    func recordIsBounded() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)

        for _ in 0..<260 {
            await delivery.deliver(
                decision: .suppress(reason: "muted", cause: .muted), incident: incident(),
                leadingContributor: nil)
        }
        #expect(delivery.outcomes.count == 200)
    }

    /// An escalation re-decides an incident that already has an outcome; the
    /// latest decision is the one that stands, and it must not double-count.
    @Test("Re-deciding the same incident replaces its outcome rather than adding one")
    func redecidingReplaces() async {
        let centre = FakeNotificationCentre()
        centre.status = .authorized
        let delivery = NotificationDelivery(centre: centre)
        let subject = incident()

        await delivery.deliver(
            decision: .suppress(reason: "muted", cause: .muted), incident: subject,
            leadingContributor: nil)
        await delivery.deliver(
            decision: .send(reason: "severity rose to severe"), incident: subject,
            leadingContributor: nil)

        #expect(delivery.outcomes.count == 1)
        #expect(delivery.outcome(for: subject.id) == .alerted)
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
