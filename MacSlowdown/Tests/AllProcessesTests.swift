import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func record(
    _ pid: pid_t, command: String, residentBytes: UInt64?, uid: uid_t = getuid(),
    ppid: pid_t = 1, startTime: UInt64? = nil
) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: startTime ?? UInt64(pid) * 1_000_000),
        command: command, uid: uid, ppid: ppid,
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
                    executablePath: (bundlePath ?? "/usr/libexec") + "/" + $0.command,
                    appBundlePath: bundlePath, bundleID: nil, teamID: nil),
                membership: .certain)
        })
}

/// A table with a busy app, an idle-but-measurable process, and two protected
/// system processes. The protected pair are the point: they are almost certainly
/// the busiest things on the machine, and we cannot read a single number from them.
private func machine() -> [ProcessFamily] {
    [
        family("launchd", bundlePath: nil,
               members: [record(1, command: "launchd", residentBytes: nil, uid: 0,
                                startTime: 1)]),
        family("Xcode", bundlePath: "/Applications/Xcode.app",
               members: [record(4471, command: "swift-frontend", residentBytes: 2_100_000_000),
                         record(4472, command: "Xcode", residentBytes: 900_000_000)]),
        family("quiet", bundlePath: nil,
               members: [record(900, command: "quiet", residentBytes: 1_000)]),
        family("WindowServer", bundlePath: nil,
               members: [record(178, command: "WindowServer", residentBytes: nil, uid: 0)]),
        family("backupd", bundlePath: nil,
               members: [record(512, command: "backupd", residentBytes: nil, uid: 0)]),
    ]
}

private func rows() -> [AllProcessesRow] {
    AllProcesses.rows(machine(), contributions: [
        ProcessIdentity(pid: 4471, startTime: 4_471_000_000): 188,
        ProcessIdentity(pid: 4472, startTime: 4_472_000_000): 12,
        ProcessIdentity(pid: 900, startTime: 900_000_000): 0,
    ])
}

/// Every ordering the table offers, in both directions. The sort rule has to hold
/// under all of them, not just the one the view happens to open in.
private let everySortOrder: [[KeyPathComparator<AllProcessesRow>]] = [
    [KeyPathComparator(\AllProcessesRow.cpuSortKey, order: .reverse)],
    [KeyPathComparator(\AllProcessesRow.cpuSortKey, order: .forward)],
    [KeyPathComparator(\AllProcessesRow.memorySortKey, order: .reverse)],
    [KeyPathComparator(\AllProcessesRow.memorySortKey, order: .forward)],
    [KeyPathComparator(\AllProcessesRow.name, order: .forward)],
    [KeyPathComparator(\AllProcessesRow.name, order: .reverse)],
    [KeyPathComparator(\AllProcessesRow.pidSortKey, order: .forward)],
    [KeyPathComparator(\AllProcessesRow.pidSortKey, order: .reverse)],
    [KeyPathComparator(\AllProcessesRow.startedSortKey, order: .forward)],
    [KeyPathComparator(\AllProcessesRow.startedSortKey, order: .reverse)],
]

@MainActor
@Suite("All processes: the flat peer view")
struct AllProcessesRowTests {
    @Test("Every process appears, whether or not it belongs to an application")
    func everyProcessAppears() {
        #expect(rows().count == 6)
        #expect(Set(rows().map(\.pid)) == [1, 4471, 4472, 900, 178, 512])
    }

    @Test("A process in a bundle names its owning application; a daemon does not")
    func owningApplication() {
        let all = rows()
        #expect(all.first { $0.pid == 4471 }?.owningApplication == "Xcode")
        #expect(all.first { $0.pid == 512 }?.owningApplication == nil)
    }

    /// FR-002: name, PID, parent and start time are readable for every process,
    /// including the ones we may not measure.
    @Test("An unmeasurable process still carries name, PID, parent and start time")
    func unmeasurableIsStillIdentified() {
        let backupd = rows().first { $0.pid == 512 }
        #expect(backupd?.name == "backupd")
        #expect(backupd?.parentPID == 1)
        #expect(backupd?.startedAt == Date(timeIntervalSince1970: 512))
        #expect(backupd?.isMeasurable == false)
    }

    @Test("CPU and memory read 'Not measurable', never a number and never a blank")
    func unmeasurableReadsAsSuch() {
        let backupd = rows().first { $0.pid == 512 }
        #expect(backupd?.cpuText == "Not measurable")
        #expect(backupd?.memoryText == "Not measurable")
    }

    @Test("A measurable process shows its actual figures")
    func measurableShowsFigures() {
        let frontend = rows().first { $0.pid == 4471 }
        #expect(frontend?.cpuText != "Not measurable")
        #expect(frontend?.cpuText.contains("188") == true)
        #expect(frontend?.memoryText.contains("Not") == false)
    }

    /// The distinction the whole screen rests on: a measured zero is a zero, and
    /// only a refusal goes negative.
    @Test("A measured zero is zero; only a refusal sorts negative")
    func measuredZeroIsNotARefusal() {
        let all = rows()
        #expect(all.first { $0.pid == 900 }?.cpuSortKey == 0)
        #expect(all.first { $0.pid == 512 }?.cpuSortKey == -1)
        #expect(all.first { $0.pid == 512 }?.memorySortKey == -1)
    }

    @Test("Lineage is named where it can be, and never guessed from a recycled PID")
    func parentLineage() {
        let child = record(700, command: "child", residentBytes: 10, ppid: 600,
                           startTime: 1_000_000)
        // The process now holding PID 600 started *after* its supposed child, so it
        // cannot be the parent — the number was reused.
        let impostor = record(600, command: "impostor", residentBytes: 10,
                              startTime: 9_000_000)
        let built = AllProcesses.rows(
            [family("t", bundlePath: nil, members: [child, impostor])], contributions: [:])
        #expect(built.first { $0.pid == 700 }?.parentCommand == nil)

        let real = record(600, command: "launchd", residentBytes: 10, startTime: 1)
        let ok = AllProcesses.rows(
            [family("t", bundlePath: nil, members: [child, real])], contributions: [:])
        #expect(ok.first { $0.pid == 700 }?.parentCommand == "launchd")
    }

    @Test("An unmeasurable row says what it is and why it has no numbers")
    func unmeasurableSubtitle() {
        let backupd = rows().first { $0.pid == 512 }
        #expect(backupd?.subtitle == "Time Machine · parent launchd · protected")
    }

    @Test("A measurable daemon is described without being called protected")
    func measurableDaemonSubtitle() {
        let worker = record(4390, command: "mdworker_shared", residentBytes: 96_000_000)
        let built = AllProcesses.rows(
            [family("mdworker_shared", bundlePath: nil, members: [worker])], contributions: [:])
        #expect(built[0].subtitle == "Spotlight worker · user level")
    }
}

@MainActor
@Suite("All processes: the sort rule")
struct AllProcessesSortTests {
    /// **The rule this screen exists for.** Sorting a refusal as 0% would put the
    /// busiest processes on the machine at the bottom of a CPU-sorted list.
    @Test("Unmeasurable processes sort to the end under every sort order")
    func unmeasurableAlwaysLast() {
        for order in everySortOrder {
            let listing = AllProcesses.listing(rows(), by: order)
            #expect(listing.measurable.allSatisfy { $0.isMeasurable })
            #expect(listing.unmeasurable.allSatisfy { !$0.isMeasurable })
            #expect(listing.measurable.count == 3)
            #expect(listing.unmeasurable.count == 3)
        }
    }

    /// Ascending CPU is where a sort key alone would fail: -1 would sort the
    /// refusals to the *top*, directly above the genuinely idle processes.
    @Test("Sorting CPU ascending does not float refusals above measured zeroes")
    func ascendingDoesNotFloatRefusals() {
        let listing = AllProcesses.listing(
            rows(), by: [KeyPathComparator(\AllProcessesRow.cpuSortKey, order: .forward)])
        #expect(listing.measurable.first?.pid == 900, "the measured zero is the smallest")
        #expect(listing.unmeasurable.count == 3)
    }

    @Test("Within the measurable set, the default order is busiest first")
    func defaultOrderIsBusiestFirst() {
        let listing = AllProcesses.listing(rows(), by: AllProcesses.defaultSort)
        #expect(listing.measurable.map(\.pid) == [4471, 4472, 900])
    }

    @Test("Sorting reorders and never changes the set of rows")
    func sortingIsOrderOnly() {
        let identifiers = Set(rows().map(\.id))
        for order in everySortOrder {
            let listing = AllProcesses.listing(rows(), by: order)
            #expect(Set((listing.measurable + listing.unmeasurable).map(\.id)) == identifiers)
        }
    }

    @Test("Unmeasurable processes contribute nothing to any total")
    func neverCountAsZeroOrAnythingElse() {
        let listing = AllProcesses.listing(rows(), by: AllProcesses.defaultSort)
        // Not "they sum to zero" — they are absent from the arithmetic entirely.
        #expect(listing.measurable.reduce(0) { $0 + $1.percentOfOneCore } == 200)
        #expect(listing.unmeasurable.allSatisfy { !$0.isMeasurable })
    }
}

@MainActor
@Suite("All processes: census and search")
struct AllProcessesCensusTests {
    @Test("The census states total, measurable, unmeasurable and how many are an app's")
    func census() {
        let census = AllProcesses.census(rows())
        #expect(census.total == 6)
        #expect(census.measurable == 3)
        #expect(census.notMeasurable == 3)
        #expect(census.belongingToApplication == 2)
        #expect(census.summary
            == "6 processes · 3 measurable · 3 not measurable · only 2 belong to an app")
    }

    /// The count under the empty state has to describe the machine, not the
    /// filtered view, or "412 processes running" would fall to 1 as the user typed.
    @Test("The census counts the machine, not the current search")
    func censusIgnoresTheSearch() {
        let listing = AllProcesses.listing(rows(), query: "backupd", by: AllProcesses.defaultSort)
        #expect(listing.measurable.isEmpty)
        #expect(listing.unmeasurable.count == 1)
        #expect(AllProcesses.census(rows()).total == 6)
    }

    @Test("Search finds a protected daemon by name and by what it is for")
    func searchFindsProtectedDaemons() {
        func hits(_ query: String) -> Int {
            rows().filter { AllProcesses.matches($0, query: query) }.count
        }
        #expect(hits("backupd") == 1)
        #expect(hits("Time Machine") == 1)
        #expect(hits("xyzzy") == 0)
    }

    @Test("Hiding the unmeasurable never changes what the count says is there")
    func hidingDoesNotChangeTheCount() {
        let listing = AllProcesses.listing(rows(), by: AllProcesses.defaultSort)
        #expect(listing.unmeasurableHeading == "3 processes we can't measure")
        #expect(AllProcesses.census(rows()).notMeasurable == listing.unmeasurable.count)
    }
}

@Suite("System process descriptors")
struct SystemProcessDescriptorTests {
    @Test("Well-known daemons carry a human-meaningful description")
    func knownDaemons() {
        #expect(SystemProcessDescriptors.meaning(forCommand: "backupd") == "Time Machine")
        #expect(SystemProcessDescriptors.meaning(forCommand: "mds_stores")
            == "Spotlight system indexer")
        #expect(SystemProcessDescriptors.meaning(forCommand: "coreaudiod") == "Core Audio")
        #expect(SystemProcessDescriptors.meaning(forCommand: "kernel_task") == "Kernel")
        #expect(SystemProcessDescriptors.meaning(forCommand: "WindowServer") == "Window server")
    }

    /// `p_comm` is 16 bytes. A table keyed on full names would silently miss every
    /// daemon with a long reverse-DNS name — which is most of the newer ones.
    @Test("A name truncated to 16 bytes by the kernel still resolves")
    func truncatedNames() {
        #expect(SystemProcessDescriptors.meaning(forCommand: "backgroundtaskma")
            == "Login and background items")
        #expect(SystemProcessDescriptors.meaning(forCommand: "com.apple.Driver") == "Device driver")
        #expect(SystemProcessDescriptors.meaning(forCommand: "TGOnDeviceInfere")
            == "On-device models")
    }

    /// Nil is a real answer. Inventing a description for an unknown process would
    /// be the fabricated claim FR-002 forbids.
    @Test("An unknown process is described as nothing, not as something")
    func unknownIsNil() {
        #expect(SystemProcessDescriptors.meaning(forCommand: "tracd") == nil)
        #expect(SystemProcessDescriptors.meaning(forCommand: "definitely-not-real") == nil)
    }

    /// Recorded for TASK-65.13: measured against the 226 other-uid processes on the
    /// development machine, the table described 223 of them — 98.7%. This test
    /// pins the sample rather than the live machine, so it measures the table
    /// rather than whatever happens to be running.
    @Test("The table covers the great majority of a real unmeasurable set")
    func coverageOfARealSample() {
        let sample = [
            "distnoted", "distnoted", "cfprefsd", "trustd", "systemstats", "launchd",
            "WindowServer", "backupd", "mds_stores", "coreaudiod", "kernel_task",
            "com.apple.geod", "com.apple.Driver", "TGOnDeviceInfere", "logd", "powerd",
            "opendirectoryd", "tccd", "syspolicyd", "cloudd",
            "tracd",  // genuinely unknown, and stays unknown
        ]
        let coverage = SystemProcessDescriptors.coverage(of: sample)
        #expect(coverage.total == 21)
        #expect(coverage.described == 20)
    }
}

@Suite("Empty application search")
struct InventorySearchOutcomeTests {
    private func outcome(_ query: String, matches: Int, total: Int = 412)
        -> InventorySearchOutcome {
        InventorySearchOutcome(query: query, matchesInAllProcesses: matches, totalProcesses: total)
    }

    /// The failure this screen prevents: "No results" would tell the user that a
    /// running process is not running.
    @Test("An empty result explains the grouping and never implies nothing is running")
    func explainsTheGrouping() {
        let result = outcome("backupd", matches: 1)
        #expect(result.title == "No application matches “backupd”")
        #expect(result.message.contains("one process in seven"))
        #expect(result.message.contains("backupd"))
        #expect(result.message.contains("All processes"))
    }

    @Test("The same search is evaluated elsewhere and the hit count is reported")
    func reportsTheCountElsewhere() {
        #expect(outcome("backupd", matches: 1).countSummary
            == "1 match in All processes · 412 processes running")
        #expect(outcome("helper", matches: 7).countSummary
            == "7 matches in All processes · 412 processes running")
    }

    @Test("A one-step route to the other scope is offered when there is one")
    func offersTheSwitch() {
        #expect(outcome("backupd", matches: 1).actionTitle == "Search All processes instead")
    }

    /// AC #4. A search that matches nothing anywhere must not read like a search
    /// that matched somewhere else — and must not offer a button that goes to
    /// another empty list.
    @Test("A search matching nothing anywhere is distinguishable and offers no route")
    func nothingAnywhereIsDifferent() {
        let nowhere = outcome("xyzzy", matches: 0)
        let elsewhere = outcome("backupd", matches: 1)

        #expect(nowhere.title != elsewhere.title)
        #expect(nowhere.title == "Nothing matches “xyzzy”")
        #expect(nowhere.actionTitle == nil)
        #expect(nowhere.countSummary == "No matches in All processes · 412 processes running")
        #expect(nowhere.message.contains("412 processes running")
            || nowhere.message.contains("412 processes"))
        #expect(nowhere.matchesElsewhere == false)
    }

    /// Even "nothing matches" has to state its own limits: the processes we cannot
    /// measure were searched too, by name.
    @Test("The nothing-anywhere wording accounts for the unmeasurable processes")
    func nothingAnywhereStillCountsTheUnmeasurable() {
        #expect(outcome("xyzzy", matches: 0).message.contains("does not report"))
    }

    @Test("Singular and plural are right at the boundaries")
    func plurals() {
        #expect(outcome("x", matches: 1, total: 1).countSummary
            == "1 match in All processes · 1 process running")
        #expect(outcome("x", matches: 2, total: 2).countSummary
            == "2 matches in All processes · 2 processes running")
    }

    @Test("VoiceOver hears the whole argument, not three fragments")
    func accessibility() {
        let description = outcome("backupd", matches: 1).accessibilityDescription
        #expect(description.contains("No application matches"))
        #expect(description.contains("1 match in All processes"))
    }
}
