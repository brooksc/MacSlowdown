import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// A fixed calendar so "Until 6:00 PM" is tested at chosen hours rather than at
/// whatever hour the suite happens to run.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 8, hour: hour, minute: minute))!
}

@MainActor
@Suite("Mute sheet options")
struct MuteAlertsChoiceTests {
    @Test("The bounded choices are offered, longest last")
    func boundedChoices() {
        let choices = MuteAlerts.choices(now: date(hour: 9), calendar: calendar)
        let ids = choices.map(\.id)
        #expect(ids.prefix(2) == ["30m", "1h"])
        #expect(choices.first { $0.id == "30m" }?.minutes == 30)
        #expect(choices.first { $0.id == "1h" }?.minutes == 60)
    }

    /// FR-015's sheet has to be able to say "stop asking me" without the user
    /// picking a number they will then have to re-pick.
    @Test("An indefinite option is always offered")
    func indefiniteIsAlwaysOffered() {
        for hour in 0..<24 {
            let choices = MuteAlerts.choices(now: date(hour: hour), calendar: calendar)
            let indefinite = choices.filter(\.isIndefinite)
            #expect(indefinite.count == 1, "at \(hour):00")
            #expect(indefinite.first?.title == "Until I turn it back on")
        }
    }

    @Test("Until end of day is offered in the morning and is the right length")
    func endOfDayInTheMorning() {
        let choices = MuteAlerts.choices(now: date(hour: 9), calendar: calendar)
        let endOfDay = choices.first { $0.id == "endOfDay" }
        #expect(endOfDay?.minutes == 9 * 60, "09:00 to 18:00 is nine hours")
    }

    /// A control that appears to do something and does nothing is worse than an
    /// absent one, and an option that quietly rolled over to tomorrow would mean
    /// something very different from what it says.
    @Test("Until end of day disappears once the hour has passed or is imminent")
    func endOfDayDisappears() {
        for (hour, minute) in [(18, 0), (18, 30), (23, 0), (17, 55)] {
            let choices = MuteAlerts.choices(
                now: date(hour: hour, minute: minute), calendar: calendar)
            #expect(!choices.contains { $0.id == "endOfDay" },
                    "must not be offered at \(hour):\(minute)")
        }
        #expect(MuteAlerts.minutesUntilEndOfDay(
            from: date(hour: 17, minute: 55), calendar: calendar) == nil)
    }

    @Test("Every choice has a distinct, non-empty title")
    func titlesAreDistinct() {
        let titles = MuteAlerts.choices(now: date(hour: 9), calendar: calendar).map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }
}

@MainActor
@Suite("Mute sheet, reading a mute back")
struct MuteAlertsSelectionTests {
    @Test("No mute selects nothing")
    func noMuteNoSelection() {
        let now = date(hour: 9)
        let choices = MuteAlerts.choices(now: now, calendar: calendar)
        #expect(MuteAlerts.selection(for: .notMuted, choices: choices, now: now) == nil)
    }

    @Test("A live mute matches the choice that produced it")
    func matchesTheChoice() {
        let now = date(hour: 9)
        let choices = MuteAlerts.choices(now: now, calendar: calendar)
        for choice in choices {
            let mute = MuteState(until: now.addingTimeInterval(Double(choice.minutes) * 60))
            #expect(MuteAlerts.selection(for: mute, choices: choices, now: now) == choice.id,
                    "\(choice.title) must read back as itself")
        }
    }

    @Test("An expired mute selects nothing")
    func expiredSelectsNothing() {
        let now = date(hour: 9)
        let choices = MuteAlerts.choices(now: now, calendar: calendar)
        let mute = MuteState(until: now.addingTimeInterval(-60))
        #expect(MuteAlerts.selection(for: mute, choices: choices, now: now) == nil)
    }

    /// The indefinite mute is a real date a century out, so nothing downstream has
    /// to handle an infinity — but it must never be read back as a bounded choice.
    @Test("The indefinite mute is recognised as indefinite, not as a long one")
    func indefiniteIsRecognised() {
        let now = date(hour: 9)
        let mute = MuteState(until: now.addingTimeInterval(
            Double(MuteAlerts.indefiniteMinutes) * 60))
        #expect(MuteAlerts.isIndefinite(mute, now: now))
        #expect(!MuteAlerts.isIndefinite(
            MuteState(until: now.addingTimeInterval(60 * 60)), now: now))
        #expect(!MuteAlerts.isIndefinite(.notMuted, now: now))
    }
}

@MainActor
@Suite("Mute never suppresses recording (FR-015)")
struct MutePromiseTests {
    /// The footer is the point of the sheet. A user who mutes and then finds no
    /// history would be right to feel misled.
    @Test("The sheet states that monitoring continues while muted")
    func footerPromisesHistory() {
        let footer = MuteAlerts.footer.lowercased()
        #expect(footer.contains("monitoring keeps running"))
        #expect(footer.contains("history"))
    }

    @Test("The status line repeats the promise, in both bounded and indefinite form")
    func statusRepeatsThePromise() {
        let now = date(hour: 9)
        let bounded = MuteAlerts.status(
            for: MuteState(until: now.addingTimeInterval(30 * 60)), now: now)
        #expect(bounded?.contains("30 minutes") == true)
        #expect(bounded?.contains("Monitoring is still running") == true)

        let indefinite = MuteAlerts.status(
            for: MuteState(until: now.addingTimeInterval(
                Double(MuteAlerts.indefiniteMinutes) * 60)), now: now)
        #expect(indefinite?.contains("until you turn them back on") == true)
        #expect(indefinite?.contains("Monitoring is still running") == true)
        #expect(indefinite?.contains("minute") == false,
                "an indefinite mute must not be described as a count of minutes")

        #expect(MuteAlerts.status(for: .notMuted, now: now) == nil)
    }

    /// The behavioural half of the promise: the gate withholds the interruption,
    /// and the detector — which knows nothing about muting — still produces the
    /// incident, so the history is intact when the mute expires.
    @Test("An incident raised while muted is still detected, and is not alerted")
    func mutedIncidentIsStillRecorded() throws {
        var detectorState = IncidentDetector.State()
        let detector = IncidentDetector(policy: .default)
        let start = date(hour: 9)
        let mute = MuteState(until: start.addingTimeInterval(60 * 60))

        var opened: Incident?
        var seconds = 0.0
        while opened == nil, seconds < 3600 {
            let event = detector.observe(
                SystemObservation(
                    at: start.addingTimeInterval(seconds),
                    cpuBusyFraction: 0.99, memoryPressure: .normal,
                    thermalState: .nominal, lowStorage: false),
                state: &detectorState)
            if case .opened(let incident) = event { opened = incident }
            seconds += 5
        }

        let incident = try #require(opened)

        var gateState = NotificationGate.State()
        // CPU is recorded rather than announced by default since FR-014
        // amendment 1, so it is opted in here: this test is about *muting*
        // withholding an interruption, and it would otherwise pass because the
        // condition never announces — which proves nothing about the mute.
        var settings = NotificationSettings(minimumSeverity: .moderate)
        settings.announcedConditions = [.cpuSaturation]
        let decision = NotificationGate(settings: settings)
            .decide(
                incident: incident, mute: mute,
                at: start.addingTimeInterval(seconds), state: &gateState)

        #expect(!decision.shouldSend, "the interruption is withheld")
        #expect(decision.reason.contains("muted"))
        // The incident exists regardless: detection ran to completion while muted.
        #expect(incident.conditions.contains(.cpuSaturation))
    }
}
