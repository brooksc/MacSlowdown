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
    // **The limits come before the features, deliberately** (design 6b, FR-063).
    //
    // The old screen opened "Two things before we start" and promised
    // notifications "only for slowdowns that last long enough to matter". That set
    // up every later screen to look like a failure to deliver: we cannot tell
    // anyone their Mac was slow, and about 40% of a busy Mac is invisible to us.
    // Both facts are certain to be met during a real incident, and meeting them
    // first as an admission is a different thing from meeting them later as an
    // excuse.
    static let title = "What this can and can't tell you"
    static let promise = "Worth 30 seconds now, so nothing later comes as a surprise."

    static let watchesTitle = "We watch four things and keep what we saw"
    static let watchesDetail =
        "CPU, memory pressure, the work queue and startup-disk space — sampled "
        + "every few seconds and kept for 30 days, so you can look at an hour "
        + "that has already passed."

    /// The sentence this whole revision exists for.
    static let cannotJudgeTitle = "We can't tell you your Mac was slow"
    static let cannotJudgeDetail =
        "We measure resources, not how it felt to use. A Mac flat out on a video "
        + "export and a Mac that's genuinely struggling look identical to us, so "
        + "we'll tell you what was measured and leave the verdict to you."

    /// Introduced here rather than discovered later: it is the only way we ever
    /// hear about a slowdown we could not see (FR-064).
    static let reportTitle = "When it feels slow, tell us — that's the useful bit"
    static let reportDetail =
        "There's a button in the menu bar for it. One click, no questions. It's "
        + "the only way we find out about the slowdowns we couldn't see, and it "
        + "keeps the readings from those minutes so there's something to compare "
        + "next time."

    // Names the two conditions that interrupt *and*, in the same breath, why CPU
    // does not — which is the sentence that prevents "why didn't you tell me"
    // later (FR-014 amendment 1).
    static let notificationsTitle = "Interrupt me about memory and disk space"
    static let notificationsDetail =
        "The two where there's something you could decide. Not CPU — that's "
        + "usually work you started, so it's recorded but doesn't interrupt."

    static let loginItemTitle = "Start watching at login"
    static let loginItemDetail = "Needed to catch anything you weren't watching for."

    static let unattributableTitle = "About 40% of a busy Mac is invisible to us"
    static let unattributable =
        "Backups, indexing and the window server run as another user, and macOS "
        + "doesn't report their share to any app from the App Store. We'll always "
        + "show you how much that is rather than quietly leaving it out."

    static let closing =
        "Everything stays on this Mac. No account, no server, nothing uploaded — "
        + "the only way anything leaves is if you export a report and send it "
        + "yourself. Both settings are changeable later."

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
