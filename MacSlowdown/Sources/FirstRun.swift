import Foundation
import Observation

/// The words of the first-run screen (design 1g, bottom panel).
///
/// They live here rather than inline in the view because two of them are
/// requirements rather than decoration, and a requirement that only exists inside
/// a `Text` cannot be checked:
///
///   - **The local-only guarantee** (A-05, FR-029). The screen where the user is
///     asked for two permissions is the screen where the promise has to be made.
///   - **The unattributable paragraph** (FR-013, FR-038). Roughly 40% of busy CPU
///     on a real machine belongs to other-uid processes we are not allowed to
///     measure — `probe/FINDINGS.md` puts it exactly: measurability is decided by
///     uid. Saying so here, before the user has ever seen a gap in a contributor
///     list, turns a disappointment into an expectation the app set honestly.
///     Discovering it later, unannounced, reads as a bug in our arithmetic.
enum FirstRunCopy {
    static let title = "Two things before we start"
    static let promise = "Everything MacSlowdown records stays on this Mac."

    static let notificationsTitle = "Send notifications"
    static let notificationsDetail = "Only for slowdowns that last long enough to matter."

    static let loginItemTitle = "Start watching at login"
    static let loginItemDetail = "Needed to catch slowdowns you didn't see coming."

    static let unattributable =
        "Some system activity — backups, indexing, the window server — can't be "
        + "broken down by App Store apps. We'll always show you how much of the "
        + "load that is, and what was running."

    static let closing =
        "You can change both later in Settings. Nothing is uploaded anywhere — "
        + "there's no account and no server."

    static let startButton = "Start watching"
}

/// Whether the first-run screen is owed, and the record that it is not owed again.
///
/// `UserDefaults` is injected for one specific reason: the first-run path is by
/// definition the path a developer's own container has already left, so without a
/// seam the only machine that could exercise it would be one that had never run
/// the app. Tests hand in a throwaway suite and get a genuine first launch.
@MainActor
@Observable
final class FirstRunState {
    static let shared = FirstRunState()

    static let defaultsKey = "firstRun.completed"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var hasCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent means never run, which is the whole point of the screen. Read as
        // `object(forKey:)` rather than `bool(forKey:)` so "missing" and
        // "explicitly false" stay distinguishable if this ever grows a third state.
        hasCompleted = defaults.object(forKey: Self.defaultsKey) as? Bool ?? false
    }

    var shouldPresent: Bool { !hasCompleted }

    /// Recorded when the user presses "Start watching". Nothing else sets it: a
    /// window closed without a decision is a screen still owed, because the two
    /// permissions it introduces have not been introduced.
    func complete() {
        hasCompleted = true
        defaults.set(true, forKey: Self.defaultsKey)
    }
}
