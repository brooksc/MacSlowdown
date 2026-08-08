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
    /// FR-030: the app reports its own cost in the same terms it reports anyone's.
    @Test("Self-cost names the app, its CPU and its memory")
    func selfCostIsSpecific() {
        let text = Presentation.selfCost(cpuPercentOfOneCore: 2.34, residentBytes: 92 << 20)
        #expect(text.contains("MacSlowdown itself"))
        #expect(text.contains("2.3% CPU"))
        #expect(text.contains("MB"))
    }

    @Test("An idle app still reports a figure rather than nothing")
    func selfCostAtZero() {
        let text = Presentation.selfCost(cpuPercentOfOneCore: 0, residentBytes: 0)
        #expect(text.contains("0.0% CPU"))
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
@Suite("Retention and share")
struct RetentionAndShareTests {
    @Test("Retention keeps the newest and drops the rest")
    func retentionBounds() {
        let incidents = (0..<25).map { index in
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
    @Test("Thresholds sit where the boundaries say they do")
    func thresholds() {
        #expect(Severity.forBusyShareOfMachine(0) == .normal)
        #expect(Severity.forBusyShareOfMachine(0.599) == .normal)
        #expect(Severity.forBusyShareOfMachine(0.6) == .elevated)
        #expect(Severity.forBusyShareOfMachine(0.849) == .elevated)
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
