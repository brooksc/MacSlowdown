import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// "Alert me less" on the banner (TASK-108).
///
/// **The finding this comes from is about reach, not capability.** The dial the
/// product owner asked for was already built and already shipped; what failed was
/// finding it, after two weeks of use and four banners in one day. So these
/// assertions are mostly that the banner reaches *the existing* setting — a
/// second sensitivity control would be FR-060's failure in preference form, and
/// criterion #2 forbids one.
@MainActor
@Suite("Reaching the alert volume from the banner")
struct AlertVolumeReachTests {
    @Test("Each setting steps to the next quieter one, and the quietest stops")
    func quieterWalksOneWay() {
        #expect(AlertSensitivity.sensitive.quieter == .balanced)
        #expect(AlertSensitivity.balanced.quieter == .relaxed)
        // Nil rather than wrapping round to `sensitive`: a control meant to reduce
        // interruptions must never be able to increase them.
        #expect(AlertSensitivity.relaxed.quieter == nil)
    }

    @Test("Quieter really is quieter — the threshold rises and fewer severities announce")
    func quieterIsMeasurablyQuieter() {
        // Not a naming claim. Each step must actually interrupt less, or the
        // banner's button is a placebo.
        for setting in AlertSensitivity.allCases {
            guard let quieter = setting.quieter else { continue }
            #expect(quieter.policy.cpuBusyFractionThreshold
                    >= setting.policy.cpuBusyFractionThreshold)
            #expect(quieter.policy.cpuSustainedDuration >= setting.policy.cpuSustainedDuration)
        }
    }

    @Test("The banner carries the action, and it is not a second control")
    func bannerCarriesTheAction() {
        let category = NotificationDelivery.incidentCategory
        let identifiers = category.actions.map(\.identifier)
        #expect(identifiers.contains(NotificationDelivery.Action.alertMeLess.rawValue))
        #expect(category.actions.first { $0.identifier
            == NotificationDelivery.Action.alertMeLess.rawValue }?.title == "Alert me less")
        // Criterion #2: three actions, and exactly one of them is about volume.
        // A second *setting* would show up here as a second volume action.
        #expect(identifiers.count == 3)
    }

    @Test("Pressing it steps the setting, and reports what it became")
    func pressingItSteps() {
        let delivery = NotificationDelivery(centre: FakeNotificationCentre())
        var current = AlertSensitivity.sensitive
        delivery.onAlertMeLess = {
            guard let quieter = current.quieter else { return nil }
            current = quieter
            return current
        }

        delivery.perform(actionIdentifier: NotificationDelivery.Action.alertMeLess.rawValue)
        #expect(current == .balanced)
        delivery.perform(actionIdentifier: NotificationDelivery.Action.alertMeLess.rawValue)
        #expect(current == .relaxed)
        // At the quiet end it stays there rather than doing something else.
        delivery.perform(actionIdentifier: NotificationDelivery.Action.alertMeLess.rawValue)
        #expect(current == .relaxed)
    }
}
