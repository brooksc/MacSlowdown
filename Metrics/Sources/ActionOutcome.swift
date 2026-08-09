import Foundation

/// What happened when an action was requested (FR-017).
public enum ActionResult: Sendable, Equatable {
    case succeeded
    /// The action was offered but did not work. Reported rather than swallowed,
    /// because FR-017 requires results be reported rather than assumed.
    case failed(reason: String)
    /// The action was never available for this process.
    case withheld(reason: String)

    public var didRun: Bool { self == .succeeded }
}

/// What the machine did afterwards (FR-050).
///
/// The distinction this type exists to preserve: an action's API returning
/// success says the request was accepted, not that anything improved. FR-050
/// forbids treating one as the other.
public enum VerificationOutcome: String, Sendable, CaseIterable {
    case improved
    case unchanged
    case worsened
    /// The measurement needed to judge became unavailable.
    case unavailable
    /// Not enough signal to call it either way. An allowed answer, not a failure.
    case inconclusive

    public var label: String {
        switch self {
        case .improved: "Improved"
        case .unchanged: "No measurable change"
        case .worsened: "Got worse"
        case .unavailable: "Could not be measured"
        case .inconclusive: "Inconclusive"
        }
    }
}

/// A before/after comparison around a user-directed action (FR-050).
/// `Equatable` because an incident carries the verifications recorded during it,
/// and an incident has to stay comparable for the detector's event equality.
public struct ActionVerification: Sendable, Equatable {
    public let action: ProcessAction
    public let target: String
    public let requestedAt: Date
    public let result: ActionResult
    /// Busy fraction before the action, 0...1.
    public let before: Double?
    /// Busy fraction after the verification window.
    public let after: Double?
    public let window: Duration
    public let outcome: VerificationOutcome

    /// States what was observed without claiming the action caused it.
    ///
    /// This is the sentence FR-050 exists for: a user who acts wants to know
    /// whether things improved, and we can say whether they did — but not that we
    /// made them.
    public var summary: String {
        let seconds = Int(window.totalSeconds)
        switch outcome {
        case .unavailable:
            return "The measurements needed to check were not available afterwards."
        case .inconclusive:
            return "Not enough changed in \(seconds) seconds to say either way."
        case .improved, .unchanged, .worsened:
            guard let before, let after else { return outcome.label }
            let from = Int((before * 100).rounded())
            let to = Int((after * 100).rounded())
            let verb = outcome == .improved ? "fell"
                : outcome == .worsened ? "rose" : "stayed at about"
            return outcome == .unchanged
                ? "Total CPU \(verb) \(to)% over the \(seconds) seconds after you acted. "
                    + "We cannot tell whether your action made a difference."
                : "Total CPU \(verb) from \(from)% to \(to)% over the \(seconds) seconds "
                    + "after you acted. The two line up, but we cannot prove one caused "
                    + "the other."
        }
    }
}

public enum ActionVerifier {
    /// How much the busy fraction must move to count as a change rather than noise.
    public static let materialChange = 0.10

    /// Compares before and after, and refuses to overstate what that comparison
    /// means.
    public static func verify(
        action: ProcessAction,
        target: String,
        result: ActionResult,
        before: Double?,
        after: Double?,
        window: Duration,
        requestedAt: Date = Date()
    ) -> ActionVerification {
        let outcome: VerificationOutcome
        if !result.didRun {
            // Nothing ran, so there is nothing to attribute a change to.
            outcome = .inconclusive
        } else if let before, let after {
            let delta = after - before
            if abs(delta) < materialChange {
                outcome = .unchanged
            } else {
                outcome = delta < 0 ? .improved : .worsened
            }
        } else {
            outcome = .unavailable
        }

        return ActionVerification(
            action: action, target: target, requestedAt: requestedAt,
            result: result, before: before, after: after,
            window: window, outcome: outcome)
    }
}
