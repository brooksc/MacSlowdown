import Foundation
import Testing

@testable import Metrics

private func verify(
    result: ActionResult = .succeeded,
    before: Double?,
    after: Double?,
    window: Duration = .seconds(30)
) -> ActionVerification {
    ActionVerifier.verify(
        action: .activate, target: "Xcode", result: result,
        before: before, after: after, window: window)
}

@Suite("Action results")
struct ActionResultTests {
    @Test("Only a successful run counts as having run")
    func onlySuccessRuns() {
        #expect(ActionResult.succeeded.didRun)
        #expect(!ActionResult.failed(reason: "x").didRun)
        #expect(!ActionResult.withheld(reason: "x").didRun)
    }

    /// FR-017: a failure is reported rather than swallowed.
    @Test("Failure and withholding both carry a reason")
    func failuresExplainThemselves() {
        guard case .failed(let failure) = ActionResult.failed(reason: "app not running") else {
            Issue.record("expected failure"); return
        }
        guard case .withheld(let withheld) = ActionResult.withheld(reason: "protected") else {
            Issue.record("expected withheld"); return
        }
        #expect(!failure.isEmpty)
        #expect(!withheld.isEmpty)
    }
}

@Suite("Outcome verification")
struct OutcomeVerificationTests {
    /// FR-050's central rule: a successful API return is not a performance
    /// improvement. Running successfully with no measurable change reports
    /// "no measurable change", not success.
    @Test("A successful action with no change reports no change, not success")
    func successIsNotImprovement() {
        let verification = verify(before: 0.90, after: 0.89)
        #expect(verification.result.didRun)
        #expect(verification.outcome == .unchanged,
                "the action ran, but nothing improved — those are different claims")
    }

    @Test("A real fall is reported as improvement")
    func fallIsImprovement() {
        #expect(verify(before: 0.95, after: 0.30).outcome == .improved)
    }

    @Test("A rise is reported as worse rather than hidden")
    func riseIsWorse() {
        #expect(verify(before: 0.40, after: 0.92).outcome == .worsened)
    }

    @Test("A change smaller than the noise floor is not a change")
    func noiseIsNotChange() {
        #expect(verify(before: 0.500, after: 0.560).outcome == .unchanged)
        #expect(verify(before: 0.500, after: 0.440).outcome == .unchanged)
    }

    /// FR-050: inconclusive outcomes are allowed.
    @Test("Missing measurements report unavailable, never a guess")
    func missingMeasurementsAreUnavailable() {
        #expect(verify(before: 0.9, after: nil).outcome == .unavailable)
        #expect(verify(before: nil, after: 0.3).outcome == .unavailable)
    }

    @Test("An action that never ran cannot have an outcome attributed to it")
    func actionThatDidNotRunIsInconclusive() {
        #expect(verify(result: .failed(reason: "x"), before: 0.9, after: 0.1).outcome
                == .inconclusive)
        #expect(verify(result: .withheld(reason: "protected"), before: 0.9, after: 0.1).outcome
                == .inconclusive)
    }

    @Test("Inconclusive is a first-class outcome, not an error")
    func inconclusiveIsAllowed() {
        #expect(VerificationOutcome.allCases.contains(.inconclusive))
        #expect(!VerificationOutcome.inconclusive.label.isEmpty)
    }
}

@Suite("Verification copy never claims causation")
struct VerificationCopyTests {
    /// FR-050 and FR-013: we can say things improved, never that we improved them.
    @Test("An improvement is described without claiming credit")
    func improvementDoesNotClaimCredit() {
        let text = verify(before: 0.95, after: 0.20).summary.lowercased()
        #expect(text.contains("fell"))
        #expect(text.contains("cannot prove one caused the other"))
        for forbidden in ["fixed", "resolved", "because you", "thanks to", "your action fixed",
                          "solved", "we fixed"] {
            #expect(!text.contains(forbidden), "summary claims credit: \(forbidden)")
        }
    }

    @Test("No change says plainly that we cannot tell")
    func noChangeIsHonest() {
        let text = verify(before: 0.90, after: 0.89).summary.lowercased()
        #expect(text.contains("cannot tell whether your action made a difference"))
    }

    @Test("Unavailable and inconclusive both explain themselves")
    func unmeasurableExplained() {
        #expect(verify(before: 0.9, after: nil).summary.lowercased().contains("not available"))
        #expect(verify(result: .failed(reason: "x"), before: 0.9, after: 0.5)
            .summary.lowercased().contains("not enough changed"))
    }

    @Test("Every outcome produces non-empty, non-blaming copy")
    func allOutcomesReadable() {
        let cases: [(ActionResult, Double?, Double?)] = [
            (.succeeded, 0.9, 0.2), (.succeeded, 0.5, 0.5), (.succeeded, 0.2, 0.9),
            (.succeeded, 0.9, nil), (.failed(reason: "x"), 0.9, 0.2),
        ]
        for (result, before, after) in cases {
            let summary = verify(result: result, before: before, after: after).summary
            #expect(!summary.isEmpty)
            for forbidden in ["error", "failed to", "sorry", "unfortunately"] {
                #expect(!summary.lowercased().contains(forbidden),
                        "copy is defensive: \(forbidden)")
            }
        }
    }
}
