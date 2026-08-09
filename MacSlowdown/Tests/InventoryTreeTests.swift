import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func record(
    _ pid: pid_t, command: String, residentBytes: UInt64?, uid: uid_t = getuid()
) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: UInt64(pid)),
        command: command, uid: uid, ppid: 1,
        metrics: residentBytes.map {
            .measured(ProcessMetrics(cpuTicks: 0, residentBytes: $0))
        } ?? .notPermitted)
}

private func family(
    _ name: String, bundlePath: String?, members: [ProcessRecord],
    membership: FamilyMembership = .certain
) -> ProcessFamily {
    ProcessFamily(
        id: bundlePath ?? name, displayName: name, bundlePath: bundlePath,
        members: members.map {
            FamilyMember(
                record: $0,
                resolved: ResolvedIdentity(
                    executablePath: (bundlePath ?? "/usr/bin") + "/Contents/MacOS/x",
                    appBundlePath: bundlePath, bundleID: nil, teamID: nil),
                membership: membership)
        })
}

private func inventory(
    _ families: [ProcessFamily],
    contributions: [ProcessIdentity: Double] = [:],
    unattributed: Double = 0
) -> [InventoryRow] {
    Presentation.inventory(families, contributions: contributions,
                           unattributedPercentOfOneCore: unattributed)
}

@MainActor
@Suite("Inventory tree")
struct InventoryTreeTests {
    @Test("A family becomes one row with its processes as children")
    func familyHasChildren() {
        let one = record(10, command: "helper", residentBytes: 100)
        let two = record(11, command: "helper", residentBytes: 200)
        let rows = inventory(
            [family("App", bundlePath: "/App.app", members: [one, two])],
            contributions: [one.identity: 12, two.identity: 30])

        #expect(rows.count == 1)
        #expect(rows[0].hasChildren)
        #expect(rows[0].children.count == 2)
        #expect(rows[0].processCount == 2)
    }

    /// The tree must not contradict the row above it. If the aggregate and the
    /// visible children disagree, one of them is lying (FR-055, FR-043).
    @Test("The family total equals the sum of the children shown")
    func totalEqualsChildren() {
        let one = record(10, command: "a", residentBytes: 100)
        let two = record(11, command: "b", residentBytes: 250)
        let rows = inventory(
            [family("App", bundlePath: "/App.app", members: [one, two])],
            contributions: [one.identity: 12, two.identity: 30])

        let parent = rows[0]
        #expect(parent.percentOfOneCore == parent.children.reduce(0) { $0 + $1.percentOfOneCore })
        #expect(parent.residentBytes == parent.children.reduce(UInt64(0)) { $0 + $1.residentBytes })
    }

    /// FR-002's line: "we were refused" is not "it is idle".
    @Test("A denied child is marked unavailable, not zero")
    func deniedChildIsUnavailable() {
        let measurable = record(10, command: "app", residentBytes: 500)
        let denied = record(11, command: "helper", residentBytes: nil, uid: 0)
        let rows = inventory(
            [family("App", bundlePath: "/App.app", members: [measurable, denied])],
            contributions: [measurable.identity: 20])

        let child = rows[0].children.first { $0.name.contains("helper") }
        #expect(child?.isMeasurable == false)
        #expect(child?.cpuSortKey == -1, "an unmeasurable row must not sort as a zero")
    }

    /// FR-003 keeps the individual records beneath the aggregate. A child that
    /// needs explaining says so in words, not through an icon.
    @Test("A child carries the reason it is grouped where it is")
    func childCarriesQualification() {
        let rows = inventory([family(
            "Warp", bundlePath: "/Warp.app",
            members: [record(10, command: "zsh", residentBytes: 10),
                      record(11, command: "zsh", residentBytes: 10)],
            membership: .byParent(reason: "started by Warp"))])

        #expect(rows[0].children.count == 2)
        #expect(rows[0].children.allSatisfy { $0.qualification == "started by Warp" })
    }

    /// Most applications are a single process. A disclosure triangle opening onto
    /// one row identical to the one above it is noise on the great majority of the
    /// table, so a one-process family is simply a row.
    @Test("A single-process family has no expansion")
    func singleProcessFamilyIsJustARow() {
        let rows = inventory([family(
            "Solo", bundlePath: "/Solo.app",
            members: [record(10, command: "solo", residentBytes: 10)])])

        #expect(rows[0].hasChildren == false)
        #expect(rows[0].processCount == 1)
    }

    /// With no expansion to put it in, a lone member's qualification has to appear
    /// on the row itself or it would be lost.
    @Test("A single-process family carries its member's qualification on the row")
    func singleProcessKeepsQualification() {
        let rows = inventory([family(
            "Warp", bundlePath: "/Warp.app",
            members: [record(10, command: "zsh", residentBytes: 10)],
            membership: .byParent(reason: "started by Warp"))])

        #expect(rows[0].hasChildren == false)
        #expect(rows[0].qualification == "started by Warp")
    }

    @Test("A certain member needs no explanation")
    func certainNeedsNoQualification() {
        let plain = record(10, command: "x", residentBytes: 10)
        let rows = inventory([family("App", bundlePath: "/App.app", members: [plain])])
        #expect(rows[0].children.first?.qualification == nil)
    }
}

@MainActor
@Suite("System processes group")
struct SystemGroupTests {
    private func withSystemProcesses(unattributed: Double = 134) -> [InventoryRow] {
        let ours = record(10, command: "app", residentBytes: 500)
        let system = [
            record(20, command: "WindowServer", residentBytes: nil, uid: 0),
            record(21, command: "mds_stores", residentBytes: nil, uid: 0),
        ]
        return inventory(
            [family("App", bundlePath: "/App.app", members: [ours]),
             family("WindowServer", bundlePath: nil, members: [system[0]]),
             family("mds_stores", bundlePath: nil, members: [system[1]])],
            contributions: [ours.identity: 20],
            unattributed: unattributed)
    }

    /// Measured: every process of another uid is denied and every process of ours
    /// is readable, with no exceptions. So this group is exactly the set we cannot
    /// measure — previously they were filtered out for having no usage, which hid
    /// a quarter of the process table.
    @Test("Processes we cannot measure are collected rather than dropped")
    func systemProcessesAreCollected() {
        let rows = withSystemProcesses()
        let system = rows.first { $0.kind == .systemProcesses }
        #expect(system != nil)
        #expect(system?.processCount == 2)
        #expect(system?.children.map(\.name).sorted() == ["WindowServer", "mds_stores"])
    }

    /// FR-055 and FR-036: the total is the measured remainder. It must never be
    /// divided among the members, because it also contains kernel time and
    /// processes that came and went between samples.
    @Test("The group's total is the unattributed remainder, and no member gets a share")
    func totalIsTheRemainderAndMembersGetNothing() {
        let system = withSystemProcesses(unattributed: 134)
            .first { $0.kind == .systemProcesses }

        #expect(system?.percentOfOneCore == 134)
        let children = system?.children ?? []
        #expect(children.allSatisfy { !$0.isMeasurable },
                "naming a process is not measuring it")
        #expect(children.allSatisfy { $0.percentOfOneCore == 0 })
    }

    @Test("With nothing unmeasurable there is no system group at all")
    func noGroupWhenNothingDenied() {
        let ours = record(10, command: "app", residentBytes: 500)
        let rows = inventory([family("App", bundlePath: "/App.app", members: [ours])],
                             contributions: [ours.identity: 20])
        #expect(rows.allSatisfy { $0.kind != .systemProcesses })
    }

    @Test("An application with no usage at all is still dropped, as before")
    func idleApplicationsStillDropped() {
        let idle = record(10, command: "idle", residentBytes: 0)
        let rows = inventory([family("Idle", bundlePath: "/Idle.app", members: [idle])])
        #expect(rows.isEmpty)
    }
}

@MainActor
@Suite("Inventory sorting")
struct InventorySortingTests {
    private func tree() -> [InventoryRow] {
        let small = record(10, command: "small", residentBytes: 100)
        let big = record(20, command: "big", residentBytes: 900)
        let mid = record(21, command: "mid", residentBytes: 500)
        return inventory(
            [family("Zebra", bundlePath: "/Z.app", members: [small]),
             family("apple", bundlePath: "/A.app", members: [big, mid])],
            contributions: [small.identity: 5, big.identity: 60, mid.identity: 10])
    }

    @Test("Families sort by CPU, busiest first, by default")
    func defaultOrder() {
        let sorted = Presentation.sortedInventory(tree(), by: Presentation.defaultInventorySort)
        #expect(sorted.map(\.name) == ["apple", "Zebra"])
    }

    /// Sorting a flattened list would scatter children away from their parents.
    /// Children are sorted within their own family, never against other families'.
    @Test("Children are sorted inside their family, not across the whole table")
    func childrenSortWithinFamily() {
        let sorted = Presentation.sortedInventory(tree(), by: Presentation.defaultInventorySort)
        let apple = sorted.first { $0.name == "apple" }
        #expect(apple?.children.map(\.percentOfOneCore) == [60, 10])
    }

    @Test("Sorting reorders and never changes the set of rows or children")
    func sortingIsOrderOnly() {
        let original = tree()
        let identifiers = Set(original.flatMap { [$0.id] + $0.children.map(\.id) })

        for order in [Presentation.defaultInventorySort,
                      [KeyPathComparator(\InventoryRow.name)],
                      [KeyPathComparator(\InventoryRow.memorySortKey, order: .reverse)]] {
            let sorted = Presentation.sortedInventory(original, by: order)
            #expect(Set(sorted.flatMap { [$0.id] + $0.children.map(\.id) }) == identifiers)
        }
    }

    /// Rows reorder on every sample. Identity has to be stable or an expansion
    /// would follow a position rather than an application.
    @Test("Row identity is stable across a re-sort")
    func identityIsStable() {
        let ascending = Presentation.sortedInventory(
            tree(), by: [KeyPathComparator(\InventoryRow.cpuSortKey)])
        let descending = Presentation.sortedInventory(
            tree(), by: Presentation.defaultInventorySort)
        #expect(Set(ascending.map(\.id)) == Set(descending.map(\.id)))
        #expect(ascending.map(\.id) != descending.map(\.id), "the order really did change")
    }

    @Test("An unmeasurable row sorts to a defined position rather than among zeroes")
    func unmeasurableSortsLast() {
        let ours = record(10, command: "app", residentBytes: 500)
        let idleButMeasurable = record(11, command: "quiet", residentBytes: 10)
        let denied = record(20, command: "WindowServer", residentBytes: nil, uid: 0)
        let rows = inventory(
            [family("Busy", bundlePath: "/B.app", members: [ours]),
             family("Quiet", bundlePath: "/Q.app", members: [idleButMeasurable]),
             family("WindowServer", bundlePath: nil, members: [denied])],
            contributions: [ours.identity: 20], unattributed: 5)

        let system = rows.first { $0.kind == .systemProcesses }
        let child = system?.children.first
        #expect(child?.cpuSortKey == -1)
        #expect(rows.first { $0.name == "Quiet" }?.cpuSortKey == 0,
                "a measured zero is a zero; only the unmeasurable go negative")
    }
}
