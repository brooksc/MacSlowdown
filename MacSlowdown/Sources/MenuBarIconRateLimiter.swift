import Foundation
import Observation

/// Holds the icon to at most one state change every `minimumInterval`.
///
/// The reason is not aesthetic. The sampling loop runs at 1 s during an
/// investigation (FR-031) and a machine sitting exactly on a threshold will cross
/// it back and forth on consecutive samples; without this the icon would flicker
/// between two colours in the menu bar for as long as the condition lasted, which
/// is both useless and, in a strip the user is reading for something else,
/// actively unpleasant. The design states the rule as "one change per 2 s".
///
/// A deferred change is never dropped. `decide` returns how long to wait, and the
/// model re-asks when the wait is over, so the last state the machine was actually
/// in always arrives — late by at most `minimumInterval`, never lost.
enum MenuBarIconRateLimiter {
    enum Decision: Equatable {
        /// The desired state is already on screen.
        case unchanged
        /// Apply it now.
        case apply
        /// Too soon. Ask again after this long.
        case hold(remaining: Duration)
    }

    static func decide(
        displayed: MenuBarIconPresentation,
        desired: MenuBarIconPresentation,
        lastChangeAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        minimumInterval: Duration = MenuBarIcon.minimumInterval
    ) -> Decision {
        // The *state* is what is rate-limited, not the whole presentation. The
        // spoken label carries a live duration ("11 minutes") and the badge follows
        // the incident; holding those back would make the icon quietly wrong for up
        // to two seconds in order to prevent a flicker that a label cannot cause.
        guard displayed.state != desired.state else {
            return displayed == desired ? .unchanged : .apply
        }
        guard let lastChangeAt else { return .apply }
        let elapsed = now - lastChangeAt
        guard elapsed < minimumInterval else { return .apply }
        return .hold(remaining: minimumInterval - elapsed)
    }
}

/// Owns what is currently on screen and when it last changed.
///
/// Separate from the view because a view is recreated on every observation and
/// cannot remember when it last changed anything — which is precisely the fact a
/// rate limiter is made of.
@MainActor
@Observable
final class MenuBarIconModel {
    private(set) var displayed: MenuBarIconPresentation = .normal
    /// When the *state* last changed. Nil until the first change, so the very first
    /// transition after launch is never held back.
    private(set) var lastStateChangeAt: ContinuousClock.Instant?

    private let minimumInterval: Duration
    private var pending: Task<Void, Never>?

    init(minimumInterval: Duration = MenuBarIcon.minimumInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Offers a new presentation. Returns whether it was shown immediately.
    ///
    /// When it was not, a task is scheduled to offer it again once the interval has
    /// run. The task re-reads nothing: it re-offers the same value, and the caller's
    /// next update supersedes it, so the newest desired state always wins.
    @discardableResult
    func update(to desired: MenuBarIconPresentation,
                now: ContinuousClock.Instant = ContinuousClock.now) -> Bool {
        switch MenuBarIconRateLimiter.decide(
            displayed: displayed, desired: desired,
            lastChangeAt: lastStateChangeAt, now: now,
            minimumInterval: minimumInterval) {
        case .unchanged:
            return true
        case .apply:
            pending?.cancel()
            pending = nil
            if displayed.state != desired.state { lastStateChangeAt = now }
            displayed = desired
            return true
        case .hold(let remaining):
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: remaining)
                guard !Task.isCancelled else { return }
                self?.update(to: desired)
            }
            return false
        }
    }
}
