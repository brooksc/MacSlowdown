import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func identity(_ pid: pid_t) -> ProcessIdentity {
    ProcessIdentity(pid: pid, startTime: UInt64(pid) * 1000)
}

private func record(
    _ pid: pid_t, command: String, residentBytes: UInt64?, uid: uid_t = getuid()
) -> ProcessRecord {
    ProcessRecord(
        identity: identity(pid), command: command, uid: uid, ppid: 1,
        metrics: residentBytes.map {
            .measured(ProcessMetrics(cpuTicks: 0, residentBytes: $0))
        } ?? .notPermitted)
}

private func family(
    _ name: String, bundlePath: String?, members: [ProcessRecord]
) -> ProcessFamily {
    ProcessFamily(
        id: bundlePath ?? name, displayName: name, bundlePath: bundlePath,
        members: members.map {
            FamilyMember(
                record: $0,
                resolved: ResolvedIdentity(
                    executablePath: nil, appBundlePath: bundlePath,
                    bundleID: nil, teamID: nil),
                membership: .certain)
        })
}

@Suite("Self-cost and rate wording")
struct PresentationWordingTests {
    /// FR-030: the app reports its own cost in the same terms it reports anyone's
    /// — which means naming the statistic, as every other column on the screen does.
    @Test("Self-cost names the app, and says which statistic each figure is")
    func selfCostIsSpecific() {
        let text = Presentation.selfCost(cpuPercentOfOneCore: 2.34, residentBytes: 92 << 20)
        #expect(text.contains("MacSlowdown itself"))
        #expect(text.contains("2.3% of one core"))
        #expect(text.contains("resident"))
        // The app no longer grades its own cost on screen: the numeric budget is
        // deferred and the warning line is gone.
        #expect(!text.lowercased().contains("budget"))
    }

    @Test("A genuinely idle app reports zero, which is a measurement")
    func selfCostAtZero() {
        let text = Presentation.selfCost(cpuPercentOfOneCore: 0, residentBytes: 0)
        #expect(text.contains("0.0% of one core"))
    }

    /// A rate needs two samples. Until then there is no figure, and printing
    /// "0.0%" would be a measured-looking zero for a measurement not yet taken
    /// (FR-002) — the same rule the disk tile and the trailing mean follow.
    @Test("Before the first rate, the CPU figure is absent rather than zero")
    func selfCostBeforeAnyRate() {
        let text = Presentation.selfCost(cpuPercentOfOneCore: nil, residentBytes: 92 << 20)
        #expect(text.contains("not measured yet"))
        #expect(!text.contains("0.0%"))
        // Memory needs only one reading, so it is still reported.
        #expect(text.contains("MB"))
    }

    /// FR-009: disk is a rate over the measured interval, never a running total.
    /// The wording has to say so, because "127 MB" and "127 MB/s" describe very
    /// different machines.
    @Test("Disk throughput is stated per second, both directions")
    func diskThroughputIsARate() {
        let text = Presentation.diskThroughput(
            DiskRates(readBytesPerSecond: 1_000_000, writeBytesPerSecond: 2_000_000))
        #expect(text.contains("/s read"))
        #expect(text.contains("/s write"))
    }

    /// FR-002 draws a hard line between "measured, and it is zero" and "we could
    /// not measure this". An idle disk is the first, and must not read as the
    /// second. (The formatter renders zero as the word "Zero", not "0" — worth
    /// knowing, since it makes a substring check on "0" a false negative.)
    @Test("An idle disk reads as a measured zero, never as unavailable")
    func idleDiskIsZero() {
        let text = Presentation.diskThroughput(.zero)
        #expect(text.contains("/s read"))
        #expect(text.contains("/s write"))
        #expect(text.lowercased().contains("zero"))

        for absent in ["unavailable", "unknown", "not available", "—"] {
            #expect(!text.lowercased().contains(absent))
        }
    }

    /// FR-036: never imply memory can be freed, and never describe swapping as a
    /// fault the user should fix.
    @Test("Swap wording describes what macOS is doing, and claims nothing else")
    func swapWording() {
        let swapping = Presentation.swapActivity(PagingRates(
            pageInsPerSecond: 0, pageOutsPerSecond: 0,
            swapInsPerSecond: 5, swapOutsPerSecond: 0,
            compressionsPerSecond: 0, decompressionsPerSecond: 0))
        #expect(swapping == "macOS is moving memory to and from disk")

        #expect(Presentation.swapActivity(.zero) == "No swapping")

        for text in [swapping, Presentation.swapActivity(.zero)] {
            let lowered = text.lowercased()
            #expect(!lowered.contains("free"))
            #expect(!lowered.contains("waste"))
            #expect(!lowered.contains("low memory"))
        }
    }

    /// Page-ins alone are ordinary demand paging, not swapping. Calling them
    /// swapping would report a problem the machine does not have.
    @Test("Paging without swapping is not reported as swapping")
    func pagingIsNotSwapping() {
        let paging = PagingRates(
            pageInsPerSecond: 900, pageOutsPerSecond: 800,
            swapInsPerSecond: 0, swapOutsPerSecond: 0,
            compressionsPerSecond: 100, decompressionsPerSecond: 100)
        #expect(Presentation.swapActivity(paging) == "No swapping")
    }
}

@Suite("Family ranking")
struct FamilyRankingTests {
    @Test("Families are ordered by CPU, largest first")
    func orderedByCPU() {
        let small = record(10, command: "small", residentBytes: 1 << 20)
        let large = record(20, command: "large", residentBytes: 1 << 20)
        let rows = Presentation.rankedFamilies(
            [family("Small", bundlePath: "/A.app", members: [small]),
             family("Large", bundlePath: "/B.app", members: [large])],
            contributions: [small.identity: 4, large.identity: 96])

        #expect(rows.map(\.family.displayName) == ["Large", "Small"])
        #expect(rows.first?.percentOfOneCore == 96)
    }

    @Test("A family's usage is the sum of its members")
    func usageSums() {
        let one = record(10, command: "helper", residentBytes: 100)
        let two = record(11, command: "helper", residentBytes: 250)
        let rows = Presentation.rankedFamilies(
            [family("App", bundlePath: "/App.app", members: [one, two])],
            contributions: [one.identity: 12, two.identity: 30])

        #expect(rows.count == 1)
        #expect(rows[0].percentOfOneCore == 42)
        #expect(rows[0].residentBytes == 350)
    }

    /// The sandbox denies other-uid processes, so a family can be visible by name
    /// with no measurements. That must not be counted as zero usage silently —
    /// here it means the family contributes only what we could actually measure.
    @Test("Members we may not measure contribute nothing rather than a fabricated zero")
    func unmeasurableMembersContributeNothing() {
        let measurable = record(10, command: "app", residentBytes: 500)
        let denied = record(11, command: "helper", residentBytes: nil, uid: 0)
        let rows = Presentation.rankedFamilies(
            [family("App", bundlePath: "/App.app", members: [measurable, denied])],
            contributions: [measurable.identity: 20])

        #expect(rows[0].residentBytes == 500)
        #expect(rows[0].percentOfOneCore == 20)
        #expect(rows[0].family.notMeasurableCount == 1,
                "the denied member must stay visible, not be dropped")
    }

    @Test("A family with no measurable usage at all is not listed")
    func emptyFamiliesDropped() {
        let denied = record(11, command: "daemon", residentBytes: nil, uid: 0)
        let rows = Presentation.rankedFamilies(
            [family("Daemon", bundlePath: nil, members: [denied])], contributions: [:])
        #expect(rows.isEmpty)
    }

    @Test("A family with memory but no CPU is still listed")
    func memoryOnlyFamilyKept() {
        let idle = record(12, command: "idle", residentBytes: 4 << 20)
        let rows = Presentation.rankedFamilies(
            [family("Idle", bundlePath: "/Idle.app", members: [idle])], contributions: [:])
        #expect(rows.count == 1)
        #expect(rows[0].percentOfOneCore == 0)
    }

    /// PIDs are reused. A contribution keyed on a stale identity must not be
    /// credited to whatever process now holds that PID.
    @Test("Contributions are matched on identity, not on PID alone")
    func identityNotPID() {
        let current = record(10, command: "current", residentBytes: 100)
        let stalePID = ProcessIdentity(pid: 10, startTime: 999_999)
        let rows = Presentation.rankedFamilies(
            [family("App", bundlePath: "/App.app", members: [current])],
            contributions: [stalePID: 500])

        #expect(rows[0].percentOfOneCore == 0,
                "a dead process's CPU must not be credited to its PID's successor")
    }

    @Test("No families produces no rows rather than a placeholder")
    func emptyInput() {
        #expect(Presentation.rankedFamilies([], contributions: [:]).isEmpty)
    }
}

@MainActor
@Suite("Column sorting")
struct SortingTests {
    private func rows() -> [MonitorStore.FamilyRow] {
        Presentation.rankedFamilies(
            [family("Zebra", bundlePath: "/Z.app",
                    members: [record(10, command: "z", residentBytes: 100)]),
             family("apple", bundlePath: "/A.app",
                    members: [record(20, command: "a", residentBytes: 900),
                              record(21, command: "a2", residentBytes: 100)]),
             family("Middle", bundlePath: "/M.app",
                    members: [record(30, command: "m", residentBytes: 500)])],
            contributions: [identity(10): 5, identity(20): 50, identity(30): 20])
    }

    /// FR-027's default: busiest first, which is what the table already showed
    /// before headers became interactive. Opening on a different order would
    /// change the surface's meaning.
    @Test("The default order is CPU, busiest first")
    func defaultIsCPUDescending() {
        let sorted = Presentation.sorted(rows(), by: Presentation.defaultSortOrder)
        #expect(sorted.map(\.percentOfOneCore) == [50, 20, 5])
    }

    @Test("Every column sorts in both directions")
    func everyColumnSorts() {
        let byName = Presentation.sorted(
            rows(), by: [KeyPathComparator(\MonitorStore.FamilyRow.family.displayName)])
        #expect(byName.map(\.family.displayName) == ["apple", "Middle", "Zebra"],
                "name order should be case-insensitive, not ASCII")

        let byMemory = Presentation.sorted(
            rows(), by: [KeyPathComparator(\MonitorStore.FamilyRow.residentBytes,
                                           order: .reverse)])
        #expect(byMemory.map(\.residentBytes) == [1000, 500, 100])

        let byCount = Presentation.sorted(
            rows(), by: [KeyPathComparator(\MonitorStore.FamilyRow.processCount,
                                           order: .reverse)])
        #expect(byCount.first?.processCount == 2)

        let ascending = Presentation.sorted(
            rows(), by: [KeyPathComparator(\MonitorStore.FamilyRow.percentOfOneCore)])
        #expect(ascending.map(\.percentOfOneCore) == [5, 20, 50])
    }

    /// The invariant that makes sorting safe: it reorders and nothing else. A sort
    /// that dropped a row would hide an application as a side effect of tidying.
    @Test("Sorting changes only the order, never the set of rows")
    func sortingIsOrderOnly() {
        let unsorted = rows()
        let identifiers = Set(unsorted.map(\.id))

        for order in [Presentation.defaultSortOrder,
                      [KeyPathComparator(\MonitorStore.FamilyRow.family.displayName)],
                      [KeyPathComparator(\MonitorStore.FamilyRow.residentBytes)],
                      [KeyPathComparator(\MonitorStore.FamilyRow.processCount)]] {
            let sorted = Presentation.sorted(unsorted, by: order)
            #expect(sorted.count == unsorted.count)
            #expect(Set(sorted.map(\.id)) == identifiers)
        }
    }

    /// Most processes sit at 0%, so ties are the common case. Without a stable
    /// tiebreak the table would reshuffle every sample and look busier than the
    /// machine is.
    @Test("Equal values are broken by name, so the order does not shuffle")
    func tiesAreStable() {
        let tied = Presentation.rankedFamilies(
            [family("Charlie", bundlePath: "/C.app",
                    members: [record(1, command: "c", residentBytes: 10)]),
             family("alpha", bundlePath: "/A.app",
                    members: [record(2, command: "a", residentBytes: 10)]),
             family("Bravo", bundlePath: "/B.app",
                    members: [record(3, command: "b", residentBytes: 10)])],
            contributions: [:])

        let order = [KeyPathComparator(\MonitorStore.FamilyRow.percentOfOneCore,
                                       order: .reverse)]
        let first = Presentation.sorted(tied, by: order).map(\.family.displayName)
        let again = Presentation.sorted(tied.reversed(), by: order).map(\.family.displayName)

        #expect(first == ["alpha", "Bravo", "Charlie"])
        #expect(first == again, "the same rows must sort the same way whatever order they arrive in")
    }

    @Test("An empty sort order leaves the rows as they were")
    func emptyOrderIsIdentity() {
        let unsorted = rows()
        #expect(Presentation.sorted(unsorted, by: []).map(\.id) == unsorted.map(\.id))
    }

    @Test("Sorting an empty table produces an empty table rather than failing")
    func emptyTable() {
        #expect(Presentation.sorted([], by: Presentation.defaultSortOrder).isEmpty)
    }
}

@MainActor
@Suite("Retention and share")
struct RetentionAndShareTests {
    @Test("Retention keeps the newest and drops the rest")
    func retentionBounds() {
        // Five past the bound, whatever the bound currently is. Hard-coding 25 made
        // this test silently stop bounding anything when TASK-72 raised the limit.
        let incidents = (0..<(MonitorStore.retainedIncidents + 5)).map { index in
            Incident(
                id: UUID(), beganAt: Date(timeIntervalSince1970: Double(1000 - index)),
                triggeredAt: Date(), recoveryStartedAt: nil, closedAt: Date(),
                conditions: [.cpuSaturation], severity: .high,
                peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
        }
        let kept = Presentation.retained(incidents, limit: MonitorStore.retainedIncidents)

        #expect(kept.count == MonitorStore.retainedIncidents)
        #expect(kept.first?.id == incidents.first?.id, "newest first must survive")
    }

    @Test("Fewer incidents than the limit are all kept, unchanged")
    func underLimitUntouched() {
        let incidents = [Incident(
            id: UUID(), beganAt: Date(), triggeredAt: Date(), recoveryStartedAt: nil,
            closedAt: Date(), conditions: [.cpuSaturation], severity: .moderate,
            peakCPUBusyFraction: 0.5, peakMemoryPressure: .normal)]
        #expect(Presentation.retained(incidents, limit: 20).count == 1)
    }

    /// FR-004: a percentage of one core means nothing without the core count.
    /// 800% is a saturated 8-core machine and a quarter of a 32-core one.
    @Test("Busy share divides by the core count")
    func shareIsCoreRelative() {
        #expect(Presentation.busyShareOfMachine(percentOfOneCore: 800, logicalCores: 8) == 1.0)
        #expect(Presentation.busyShareOfMachine(percentOfOneCore: 800, logicalCores: 32) == 0.25)
        #expect(Presentation.busyShareOfMachine(percentOfOneCore: 0, logicalCores: 8) == 0)
    }

    /// A machine reporting no cores is a failed read, not an infinitely busy one.
    @Test("An unreadable core count yields zero rather than a division by zero")
    func zeroCoresIsSafe() {
        #expect(Presentation.busyShareOfMachine(percentOfOneCore: 800, logicalCores: 0) == 0)
    }
}

@Suite("Severity and freshness")
struct SeverityTests {
    /// The severe boundary **is** the user's configured breach threshold, and the
    /// elevated band sits below it (TASK-96 finding 18). It used to be a fixed
    /// 0.6/0.85 pair, so choosing Sensitive or Relaxed in Settings changed what
    /// opened an incident and changed nothing about the word on the screen.
    @Test("Severe begins exactly where the detector would call it a breach")
    func severeMatchesTheThreshold() {
        for threshold in [0.75, 0.85, 0.92] {
            #expect(Severity.forBusyShareOfMachine(threshold, breachingAt: threshold) == .severe)
            #expect(Severity.forBusyShareOfMachine(threshold - 0.001,
                                                  breachingAt: threshold) == .elevated)
            #expect(Severity.forBusyShareOfMachine(1.5, breachingAt: threshold) == .severe)
            #expect(Severity.forBusyShareOfMachine(0, breachingAt: threshold) == .normal)
        }
    }

    /// A state that only appeared once the threshold was crossed could not warn
    /// that one was approaching, which is the whole purpose of the elevated band.
    @Test("The elevated band sits below the threshold and moves with it")
    func elevatedBandFollowsTheThreshold() {
        let sensitive = 0.75
        let relaxed = 0.92
        let boundary = { (t: Double) in t * Severity.elevatedFractionOfThreshold }

        #expect(Severity.forBusyShareOfMachine(boundary(sensitive),
                                               breachingAt: sensitive) == .elevated)
        #expect(Severity.forBusyShareOfMachine(boundary(sensitive) - 0.001,
                                               breachingAt: sensitive) == .normal)
        // The same reading is judged differently under a relaxed threshold, which
        // is the point of the setting.
        #expect(Severity.forBusyShareOfMachine(0.8, breachingAt: sensitive) == .severe)
        #expect(Severity.forBusyShareOfMachine(0.8, breachingAt: relaxed) == .elevated)
    }

    @Test("The default reproduces the previous fixed lines closely enough")
    func defaultIsUnchangedInSpirit() {
        #expect(Severity.forBusyShareOfMachine(0) == .normal)
        #expect(Severity.forBusyShareOfMachine(0.5) == .normal)
        #expect(Severity.forBusyShareOfMachine(0.7) == .elevated)
        #expect(Severity.forBusyShareOfMachine(0.85) == .severe)
        #expect(Severity.forBusyShareOfMachine(1.5) == .severe)
    }

    /// FR-034: severity is never conveyed by colour alone. Every case must carry a
    /// distinct word and a distinct symbol, so VoiceOver and a monochrome display
    /// both still distinguish them.
    @Test("Every severity has its own word and its own symbol")
    func distinguishableWithoutColour() {
        let labels = Set(Severity.allCases.map(\.label))
        let symbols = Set(Severity.allCases.map(\.symbolName))
        #expect(labels.count == Severity.allCases.count)
        #expect(symbols.count == Severity.allCases.count)
        #expect(!labels.contains(""))
    }

    @Test("Severity orders from normal to severe")
    func ordering() {
        #expect(Severity.normal < Severity.elevated)
        #expect(Severity.elevated < Severity.severe)
    }

    /// FR-002: a late reading is shown as late, never presented as current.
    @Test("Freshness distinguishes a current reading from a stale one")
    func freshness() {
        #expect(!Freshness.current.isStale)
        #expect(Freshness.stale(age: .seconds(12)).isStale)
        #expect(Freshness.stale(age: .seconds(12)) != Freshness.stale(age: .seconds(13)),
                "the age is part of the state, so it can be shown")
    }
}

/// TASK-96 finding 21. `ActionPerformer` returned `.succeeded` for two actions
/// that hand off to macOS and never look back — an outcome claimed from a call
/// returning, which is the rule FR-050 and FR-017 exist for and which that file's
/// own header claims to honour.
@Suite("A hand-off is reported as a hand-off")
struct ActionHandOffTests {
    @Test("Handing off is not the same as having run")
    func handOffIsNotSuccess() {
        let outcome = ActionResult.handedOff(request: "Asked Finder to show it.")
        #expect(!outcome.didRun)
        #expect(outcome != .succeeded)
    }

    @Test("Its wording asks rather than asserts")
    func wordingIsARequest() {
        let outcome = ActionResult.handedOff(request: "Asked macOS to open it.")
        if case .handedOff(let request) = outcome {
            #expect(request.hasPrefix("Asked"))
            #expect(!request.contains("done"))
        } else {
            Issue.record("expected a hand-off")
        }
    }
}
