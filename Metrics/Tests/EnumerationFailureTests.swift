import Darwin
import Foundation
import Testing

@testable import Metrics

/// Follows decision-1. Apple withdrew `sysctl KERN_PROC_ALL` on iOS 9 with the
/// rationale that apps "are not permitted to see what other apps are running",
/// so denial on a future macOS is a real scenario rather than an invented one.
/// These tests assert the app degrades honestly rather than reading as
/// "nothing is running".
@Suite("Enumeration failure degrades honestly")
struct EnumerationFailureTests {
    private static func denied() -> ProcessSampler {
        ProcessSampler(enumerator: { .failure(ProcessSampler.EnumerationFailure(errno: EPERM)) })
    }

    /// AC#1: the distinction exists at all. An empty table and a refused call
    /// mean opposite things.
    @Test("A refused call is distinguishable from an empty table")
    func refusalIsDistinguishable() {
        let denied = Self.denied().snapshot()
        #expect(denied.enumeration == .failed(errno: EPERM))
        #expect(denied.records.isEmpty)

        let empty = ProcessSampler(enumerator: { .success([]) }).snapshot()
        #expect(empty.enumeration == .succeeded)
        #expect(empty.records.isEmpty)

        // Same record count, opposite meaning — which is the whole point.
        #expect(denied.enumeration != empty.enumeration)
    }

    @Test("The live system currently enumerates successfully")
    func liveSystemSucceeds() {
        #expect(ProcessSampler().snapshot().enumeration == .succeeded)
    }

    /// AC#2: there is an explanation to show, and it says what is unavailable
    /// without speculating about why.
    @Test("Failure carries an explanation; success carries none")
    func explanationOnlyOnFailure() throws {
        #expect(EnumerationOutcome.succeeded.explanation == nil)

        let explanation = try #require(EnumerationOutcome.failed(errno: EPERM).explanation)
        #expect(explanation.lowercased().contains("not reporting"))
        #expect(explanation.lowercased().contains("cannot be listed")
                || explanation.lowercased().contains("cannot be"))

        // AC#3: it must say what still works, so the app does not read as broken.
        #expect(explanation.contains("Total CPU"))
        #expect(explanation.lowercased().contains("unaffected"))

        // No speculation about cause, and no blame.
        for forbidden in ["denied", "blocked", "apple", "sandbox", "error", "failed"] {
            #expect(!explanation.lowercased().contains(forbidden),
                    "explanation speculates or alarms with: \(forbidden)")
        }
    }

    /// AC#3: aggregate measurement is independent of enumeration, so the app
    /// remains a working monitor when the process table is refused.
    @Test("Aggregate CPU still works when enumeration is refused")
    func aggregateSurvivesRefusal() async throws {
        let sampler = Self.denied()
        let hostBefore = try #require(HostCPU.sample())
        let before = sampler.snapshot()
        try await Task.sleep(for: .milliseconds(400))
        let after = sampler.snapshot()
        let hostAfter = try #require(HostCPU.sample())

        let attribution = CPUAttributionCalculator.attribution(
            from: before, to: after, hostEarlier: hostBefore, hostLater: hostAfter)

        // The machine is doing something, and we can still measure how much.
        #expect(attribution.totalBusyPercentOfOneCore > 0)

        // With nothing attributable, everything lands in the remainder — which is
        // the honest answer, and the totals still account for the whole.
        #expect(attribution.contributors.isEmpty)
        #expect(attribution.attributedPercentOfOneCore == 0)
        #expect(abs(attribution.unattributedPercentOfOneCore
                    - attribution.totalBusyPercentOfOneCore) < 0.001)
    }

    /// AC#4: the inventory has nothing to show, and that must not be mistaken for
    /// an idle machine.
    @Test("Grouping a refused snapshot yields no families to display")
    func groupingYieldsNothingToShow() {
        let snapshot = Self.denied().snapshot()
        let families = FamilyGrouper.group(snapshot: snapshot, resolver: ProcessIdentityResolver())
        #expect(families.isEmpty)
        // The caller must therefore consult `enumeration` rather than inferring
        // meaning from the empty result.
        #expect(snapshot.enumeration.didFail)
    }

    @Test("A lost resize race is reported as failure, not as an empty machine")
    func resizeRaceIsAFailure() {
        // systemProcessTable retries on ENOMEM and reports failure if every
        // attempt loses the race, rather than returning an empty list.
        let outcome = ProcessSampler.systemProcessTable(attempts: 0)
        switch outcome {
        case .success(let entries):
            Issue.record("expected failure with no attempts, got \(entries.count) entries")
        case .failure(let failure):
            #expect(failure.errno == ENOMEM)
        }
    }
}
