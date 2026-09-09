import Foundation
import Observation

/// "Quiet for this work session" (FR-016 amendment 1, design 5f).
///
/// The gap it fills is between a mute, which the user has to choose a length for
/// and then remember, and a permanent rule, which they have to mean. Most of the
/// time someone silencing a notification is doing something heavy *now* — a build,
/// an export, a migration — and what they want is quiet until they stop, not quiet
/// for thirty minutes and not quiet forever.
///
/// **It is deliberately not persisted.** `startedAt` lives in this object and
/// nowhere else, so the session ends when the app's process does: at logout, at a
/// restart, at a quit. That is the entire expiry mechanism, and writing it to
/// `UserDefaults` would break it — a stored flag would survive the logout it is
/// defined as ending at, and the user would be silenced by something they were
/// promised they would not have to remember.
///
/// **Silent to set, silent to expire, visible while active** (design 5f). Nothing
/// is announced when it starts or ends, because both moments are ones the user
/// caused; but while it is running the Rules screen shows it with an "End now"
/// control, because a suppression nobody can see is indistinguishable from a
/// broken detector.
///
/// Like every other rule in this app it changes interruption only. Conditions are
/// still detected, still recorded, still on every live surface and in history.
@MainActor
@Observable
final class SessionQuiet {
    static let shared = SessionQuiet()

    /// When the session's quiet began, or nil when it is not running.
    private(set) var startedAt: Date?

    init(startedAt: Date? = nil) {
        self.startedAt = startedAt
    }

    var isActive: Bool { startedAt != nil }

    /// Starting a session that is already running does not restart its clock. The
    /// displayed "set at" time is the moment the user made the decision, and a
    /// second press of the same control did not make a second decision.
    func begin(at date: Date = Date()) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    func end() {
        startedAt = nil
    }

    // MARK: - What the interface says about it

    nonisolated static let title = "Quiet for this work session"

    /// The sentence under the option when it is being offered.
    nonisolated static let offerDetail = "Until you log out or restart. Nothing to remember."

    /// The sentence beside it while it is running. Names the moment it was set,
    /// because the only question a user has about an active suppression is whether
    /// it is the one they set or something they have forgotten about.
    func statusDetail(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let startedAt else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: startedAt)
        let day = calendar.isDate(startedAt, inSameDayAs: now) ? "" : " on "
            + startedAt.formatted(date: .abbreviated, time: .omitted)
        return "Set at \(time)\(day) · ends when you log out. "
            + "Slowdowns are still recorded while it runs."
    }
}
