import Foundation
import Metrics

/// The mute chooser (design 1g, FR-015).
///
/// Kept out of the view for the reason every presentation type in this app is:
/// the claim the sheet exists to make — that muting suppresses the interruption
/// and never the recording — is a claim about behaviour, and a claim about
/// behaviour should be checkable without putting anything on screen.
enum MuteAlerts {
    /// The sentence under the options. It is the point of the sheet rather than a
    /// caption: a user who mutes and later finds no history would be right to feel
    /// misled, so the promise is made at the moment the choice is made.
    static let footer =
        "Monitoring keeps running while muted, so you'll still have the history afterwards."

    /// The header, matching the design's "MUTE ALERTS FOR".
    static let title = "Mute alerts for"

    /// "Until I turn it back on", expressed in the only vocabulary the store
    /// offers — `MonitorStore.mute(forMinutes:)`. A hundred years is indefinite in
    /// every sense that matters here and is still a real date, so nothing
    /// downstream has to special-case an infinity.
    static let indefiniteMinutes = 100 * 365 * 24 * 60

    /// Beyond this, a remaining mute reads as indefinite rather than as a count of
    /// minutes. Far above the longest bounded choice and far below the indefinite
    /// one, so it can misclassify neither.
    static let indefiniteThreshold: TimeInterval = 60 * 60 * 24 * 30

    /// The hour "Until 6:00 PM" refers to — the end of an ordinary working day.
    static let endOfDayHour = 18

    /// Below this many minutes the end-of-day option is not offered. Muting
    /// "until 6:00 PM" at 5:58 is a control that appears to do something and does
    /// nothing, and an option that rolled over to tomorrow would mean something
    /// very different from what it says.
    static let minimumEndOfDayMinutes = 10

    struct Choice: Identifiable, Equatable, Hashable {
        let id: String
        let title: String
        /// How long the mute lasts, counted from the `now` the choices were built
        /// with.
        let minutes: Int

        var isIndefinite: Bool { minutes == MuteAlerts.indefiniteMinutes }
    }

    /// The options the sheet offers, in the design's order.
    ///
    /// Takes `now` rather than reading the clock so the end-of-day option — the
    /// only one that depends on the time of day — can be tested at every hour
    /// rather than at whatever hour the suite happens to run.
    static func choices(now: Date, calendar: Calendar = .current) -> [Choice] {
        var choices: [Choice] = [
            Choice(id: "30m", title: "30 minutes", minutes: 30),
            Choice(id: "1h", title: "1 hour", minutes: 60),
        ]

        if let minutes = minutesUntilEndOfDay(from: now, calendar: calendar) {
            choices.append(Choice(
                id: "endOfDay",
                title: "Until \(endOfDayLabel(now: now, calendar: calendar))",
                minutes: minutes))
        }

        choices.append(Choice(
            id: "indefinite",
            title: "Until I turn it back on",
            minutes: indefiniteMinutes))
        return choices
    }

    /// Minutes from `now` until today's end-of-day hour, or nil when that moment
    /// has passed or is too close to be worth offering.
    static func minutesUntilEndOfDay(from now: Date, calendar: Calendar = .current) -> Int? {
        guard let endOfDay = calendar.date(
            bySettingHour: endOfDayHour, minute: 0, second: 0, of: now) else { return nil }
        let minutes = Int((endOfDay.timeIntervalSince(now) / 60).rounded())
        guard minutes >= minimumEndOfDayMinutes else { return nil }
        return minutes
    }

    /// The end-of-day hour written the way this user's system writes times, so the
    /// option reads "6:00 PM" or "18:00" as their locale dictates.
    static func endOfDayLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = calendar.date(
            bySettingHour: endOfDayHour, minute: 0, second: 0, of: now) else {
            return "\(endOfDayHour):00"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Reading a mute back

    /// Which offered choice the current mute corresponds to, if any.
    ///
    /// Matched on when the mute expires rather than remembered, because the mute
    /// is stored as an expiry and nothing records which button produced it. A
    /// minute of tolerance absorbs the time between building the choices and the
    /// user picking one.
    static func selection(
        for mute: MuteState, choices: [Choice], now: Date, tolerance: TimeInterval = 60
    ) -> Choice.ID? {
        guard let until = mute.until, until > now else { return nil }
        if isIndefinite(mute, now: now) {
            return choices.first(where: \.isIndefinite)?.id
        }
        return choices
            .filter { !$0.isIndefinite }
            .first { choice in
                let expected = now.addingTimeInterval(Double(choice.minutes) * 60)
                return abs(expected.timeIntervalSince(until)) <= tolerance
            }?.id
    }

    static func isIndefinite(_ mute: MuteState, now: Date) -> Bool {
        guard let until = mute.until else { return false }
        return until.timeIntervalSince(now) > indefiniteThreshold
    }

    /// One sentence describing the live mute, or nil when alerts are not muted.
    ///
    /// Always restates that monitoring continues. The status line is the place a
    /// user checks after the sheet has gone, so the promise has to survive there
    /// too.
    static func status(for mute: MuteState, now: Date) -> String? {
        guard mute.isMuted(at: now) else { return nil }
        if isIndefinite(mute, now: now) {
            return "Alerts are muted until you turn them back on. Monitoring is still running."
        }
        guard let remaining = mute.remaining(at: now) else { return nil }
        let minutes = max(1, Int((remaining.totalSeconds / 60).rounded()))
        return "Alerts muted for another \(minutes) minute\(minutes == 1 ? "" : "s"). "
            + "Monitoring is still running."
    }
}
