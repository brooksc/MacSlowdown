import Foundation

/// How long something lasted, in words, in one place (FR-060).
///
/// There were five implementations of this. Two of them —
/// `PopoverPresentation.elapsedPhrase` and `MenuBarPresentation.durationPhrase` —
/// were line-for-line the same algorithm differing only in whether they wrote "min"
/// or "minutes". The others were in `NotificationPolicy`, `LifecycleEvents` and
/// `StorageHistory`, each rounding slightly differently.
///
/// Nothing about that was *wrong*, which is what made it dangerous: one incident
/// could be six minutes old in the popover, six minutes in the banner and "6
/// minutes" in the report, and the moment anybody corrected one of the five the
/// others quietly disagreed. A duration is one fact about one episode.
///
/// Two registers are kept deliberately, because they are a real difference in
/// voice rather than a duplicated rule:
///   - `.compact` for figures read at a glance — a menu bar, a headline, a table.
///   - `.full` for prose, where "6 min" reads as an abbreviation in a sentence.
///
/// Both come from the same arithmetic, so they can differ in wording and never in
/// value.
public enum DurationPhrase {
    public enum Register: Sendable {
        /// "6 min", "1 hr 15 min".
        case compact
        /// "6 minutes", "1 hour 15 minutes".
        case full
    }

    /// Coarse on purpose. A second-resolution duration would imply a precision the
    /// sampling cadence does not have, and every caller here is describing an
    /// episode rather than timing one.
    public static func phrase(_ seconds: Double, _ register: Register = .compact) -> String {
        let seconds = max(0, seconds)
        guard seconds >= 60 else { return "less than a minute" }

        let totalMinutes = Int(seconds / 60)
        guard totalMinutes >= 60 else { return minutes(totalMinutes, register) }

        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        let hourPart = self.hours(hours, register)
        guard remainder > 0 else { return hourPart }
        return "\(hourPart) \(minutes(remainder, register))"
    }

    public static func phrase(_ duration: Duration, _ register: Register = .compact) -> String {
        phrase(duration.totalSeconds, register)
    }

    private static func minutes(_ count: Int, _ register: Register) -> String {
        switch register {
        case .compact: "\(count) min"
        case .full: "\(count) minute\(count == 1 ? "" : "s")"
        }
    }

    private static func hours(_ count: Int, _ register: Register) -> String {
        switch register {
        case .compact: "\(count) hr"
        case .full: "\(count) hour\(count == 1 ? "" : "s")"
        }
    }
}
