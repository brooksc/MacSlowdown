import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

// MARK: - Fixtures

private func record(
    _ pid: pid_t, command: String, residentBytes: UInt64?,
    startTime: UInt64? = nil, uid: uid_t = getuid()
) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: startTime ?? UInt64(pid) * 1_000_000),
        command: command, uid: uid, ppid: 1,
        metrics: residentBytes.map {
            .measured(ProcessMetrics(cpuTicks: 0, residentBytes: $0))
        } ?? .notPermitted)
}

private func member(
    _ record: ProcessRecord, bundlePath: String?,
    membership: FamilyMembership = .certain
) -> FamilyMember {
    FamilyMember(
        record: record,
        resolved: ResolvedIdentity(
            executablePath: (bundlePath ?? "/usr/libexec") + "/Contents/MacOS/" + record.command,
            appBundlePath: bundlePath, bundleID: nil, teamID: nil),
        membership: membership)
}

private func family(
    _ name: String, bundlePath: String?, members: [FamilyMember]
) -> ProcessFamily {
    ProcessFamily(id: bundlePath ?? name, displayName: name,
                  bundlePath: bundlePath, members: members)
}

private func appRow(_ id: String, cpu: Double, memory: UInt64) -> InventoryRow {
    InventoryRow(
        id: id, name: id, executablePath: nil, kind: .application,
        percentOfOneCore: cpu, residentBytes: memory, isMeasurable: true,
        processCount: 1, qualification: nil, children: [])
}

// MARK: - Census

@Suite("Inventory census")
struct InventoryCensusTests {
    @Test("Counts apps, the processes inside them, and the ones we may not measure")
    func counts() {
        let census = InventoryCensus.of([
            family("App", bundlePath: "/App.app", members: [
                member(record(10, command: "App", residentBytes: 100), bundlePath: "/App.app"),
                member(record(11, command: "Helper", residentBytes: 50), bundlePath: "/App.app"),
            ]),
            family("daemon", bundlePath: nil, members: [
                member(record(12, command: "daemon", residentBytes: 10), bundlePath: nil),
            ]),
            family("windowserver", bundlePath: nil, members: [
                member(record(13, command: "WindowServer", residentBytes: nil, uid: 0),
                       bundlePath: nil),
            ]),
        ])

        #expect(census.applicationCount == 1)
        #expect(census.standaloneCount == 2)
        #expect(census.processesInApplications == 2)
        #expect(census.totalProcesses == 4)
        #expect(census.notMeasurableProcesses == 1)
    }

    @Test("The summary states all three counts, so the list never reads as complete")
    func summary() {
        let census = InventoryCensus(
            applicationCount: 20, standaloneCount: 300, processesInApplications: 63,
            totalProcesses: 412, notMeasurableProcesses: 234)
        #expect(census.summary == "20 apps · 63 of 412 processes belong to an app · "
                + "234 not measurable")
    }

    @Test("An empty census says nothing has been read, not that nothing is running")
    func emptyCensus() {
        #expect(InventoryCensus.empty.summary == "No processes have been read yet.")
    }

    @Test("The explanation says why the counts do not add up to the visible list")
    func explanationNamesTheGaps() {
        #expect(InventoryCensus.explanation.contains("Daemons"))
        #expect(InventoryCensus.explanation.contains("another user account"))
    }

    @Test("Freshness is stated in words, and absent when there has been no reading")
    func freshness() {
        let now = Date()
        #expect(InventoryCensus.freshness(lastUpdate: nil) == "No reading yet")
        #expect(InventoryCensus.freshness(
            lastUpdate: now.addingTimeInterval(-1), now: now) == "Updated 1 s ago")
        #expect(InventoryCensus.freshness(
            lastUpdate: now.addingTimeInterval(-12), now: now) == "Updated 12 s ago")
        #expect(InventoryCensus.freshness(
            lastUpdate: now.addingTimeInterval(-600), now: now) == "Updated 10 min ago")
    }
}

// MARK: - Grouping provenance

@Suite("Grouping provenance")
struct GroupingProvenanceTests {
    @Test("Each kind of evidence is counted and stated separately")
    func counts() {
        let provenance = GroupingProvenance.of([
            member(record(1, command: "a", residentBytes: 1), bundlePath: "/A.app"),
            member(record(2, command: "b", residentBytes: 1), bundlePath: "/A.app",
                   membership: .uncertain(reason: "signed as something else")),
            member(record(3, command: "c", residentBytes: 1), bundlePath: nil,
                   membership: .byParent(reason: "started by A")),
            member(record(4, command: "d", residentBytes: 1), bundlePath: "/A.app",
                   membership: .userAssigned),
        ])

        #expect(provenance.byBundle == 1)
        #expect(provenance.byGuess == 1)
        #expect(provenance.byParent == 1)
        #expect(provenance.userAssigned == 1)
        #expect(provenance.total == 4)
        #expect(provenance.sentences.count == 4)
        #expect(provenance.sentences.contains { $0.contains("a guess") })
    }

    @Test("A single certain process has nothing to explain")
    func singleProcessSaysNothing() {
        let provenance = GroupingProvenance.of([
            member(record(1, command: "a", residentBytes: 1), bundlePath: "/A.app"),
        ])
        #expect(provenance.sentences.isEmpty)
    }

    @Test("A single guessed process is still explained")
    func singleGuessIsExplained() {
        let provenance = GroupingProvenance.of([
            member(record(1, command: "a", residentBytes: 1), bundlePath: "/A.app",
                   membership: .uncertain(reason: "signed as something else")),
        ])
        #expect(provenance.sentences.count == 1)
    }
}

// MARK: - Rows

@MainActor
@Suite("Inventory rows carry PID, start time and grouping confidence")
struct InventoryRowDetailTests {
    @Test("Members carry their own PID and start time")
    func memberIdentity() {
        let started = UInt64(1_700_000_000_000_000)
        let rows = Presentation.inventory(
            [family("App", bundlePath: "/App.app", members: [
                member(record(10, command: "App", residentBytes: 100, startTime: started),
                       bundlePath: "/App.app"),
                member(record(11, command: "Helper", residentBytes: 50,
                              startTime: started + 60_000_000), bundlePath: "/App.app"),
            ])],
            contributions: [:], unattributedPercentOfOneCore: 0)

        let children = rows[0].children
        #expect(children.map(\.pid).sorted { ($0 ?? 0) < ($1 ?? 0) } == [10, 11])
        #expect(children.allSatisfy { $0.startedAt != nil })
    }

    @Test("A family of several has no PID of its own and starts when its first member did")
    func familyHasNoPID() {
        let started = UInt64(1_700_000_000_000_000)
        let rows = Presentation.inventory(
            [family("App", bundlePath: "/App.app", members: [
                member(record(11, command: "Helper", residentBytes: 50,
                              startTime: started + 60_000_000), bundlePath: "/App.app"),
                member(record(10, command: "App", residentBytes: 100, startTime: started),
                       bundlePath: "/App.app"),
            ])],
            contributions: [:], unattributedPercentOfOneCore: 0)

        #expect(rows[0].pid == nil)
        #expect(rows[0].startedAt == Presentation.startDate(started))
        #expect(rows[0].bundlePath == "/App.app")
    }

    @Test("A single-process family keeps its PID, because that is the useful column")
    func standaloneKeepsPID() {
        let rows = Presentation.inventory(
            [family("daemon", bundlePath: nil, members: [
                member(record(42, command: "daemon", residentBytes: 10), bundlePath: nil),
            ])],
            contributions: [:], unattributedPercentOfOneCore: 0)
        #expect(rows[0].pid == 42)
    }

    @Test("A heuristic match is marked, a corroborated one is not")
    func guessIsMarked() {
        let rows = Presentation.inventory(
            [family("App", bundlePath: "/App.app", members: [
                member(record(10, command: "App", residentBytes: 100), bundlePath: "/App.app"),
                member(record(11, command: "odd", residentBytes: 50), bundlePath: "/App.app",
                       membership: .uncertain(reason: "signed as com.other")),
            ])],
            contributions: [:], unattributedPercentOfOneCore: 0)

        let children = rows[0].children
        #expect(children.filter(\.isGroupedByGuess).map(\.name) == ["odd"])
        #expect(rows[0].provenance.byGuess == 1)
    }

    @Test("A start time the kernel did not give us is unknown, not 1970")
    func missingStartTime() {
        #expect(Presentation.startDate(0) == nil)
        #expect(Presentation.startDate(1_700_000_000_000_000) != nil)
    }

    @Test("Sorting keeps rows without a PID or start time out of the real values")
    func sortKeys() {
        var row = appRow("a", cpu: 1, memory: 1)
        #expect(row.pidSortKey == -1)
        #expect(row.startedSortKey == -1)
        row.pid = 7
        row.startedAt = Date(timeIntervalSince1970: 100)
        #expect(row.pidSortKey == 7)
        #expect(row.startedSortKey == 100)
    }
}

// MARK: - History

@MainActor
@Suite("Per-family history")
struct FamilyHistoryTests {
    @Test("Only the busiest families and the selection are retained")
    func trackingIsBounded() {
        let rows = (0..<80).map { appRow("app-\($0)", cpu: Double($0), memory: 0) }
        let tracked = FamilyHistory.tracked(rows, selected: "app-0")

        #expect(tracked.count == FamilyHistory.trackedLimit + 1)
        #expect(tracked.contains("app-79"))
        // Lowest CPU of all, and retained solely because the user is looking at it.
        #expect(tracked.contains("app-0"))
        #expect(!tracked.contains("app-1"))
    }

    @Test("A selection that is not in the list adds nothing")
    func unknownSelectionIgnored() {
        let tracked = FamilyHistory.tracked([appRow("a", cpu: 1, memory: 0)],
                                            selected: "missing")
        #expect(tracked == ["a"])
    }

    @Test("A process replaced under the same command counts once")
    func replacementCounted() {
        let earlier = ["renderer": Set([ProcessIdentity(pid: 10, startTime: 1)])]
        let later = ["renderer": Set([ProcessIdentity(pid: 11, startTime: 2)])]
        #expect(FamilyHistory.replacements(from: earlier, to: later) == 1)
    }

    @Test("A recycled PID is a replacement, not continuity")
    func recycledPIDIsAReplacement() {
        let earlier = ["renderer": Set([ProcessIdentity(pid: 10, startTime: 1)])]
        let later = ["renderer": Set([ProcessIdentity(pid: 10, startTime: 999)])]
        #expect(FamilyHistory.replacements(from: earlier, to: later) == 1)
    }

    @Test("An unchanged family, and one that merely grew, count no replacements")
    func noFalsePositives() {
        let earlier = ["renderer": Set([ProcessIdentity(pid: 10, startTime: 1)])]
        #expect(FamilyHistory.replacements(from: earlier, to: earlier) == 0)

        let grown = ["renderer": Set([
            ProcessIdentity(pid: 10, startTime: 1), ProcessIdentity(pid: 12, startTime: 3),
        ])]
        #expect(FamilyHistory.replacements(from: earlier, to: grown) == 0)

        // A process that exited and did not come back is not a relaunch either.
        let shrunk: [String: Set<ProcessIdentity>] = ["renderer": []]
        #expect(FamilyHistory.replacements(from: earlier, to: shrunk) == 0)
    }

    @Test("Growth is withheld until enough of a window has actually been watched")
    func growthNeedsAWindow() {
        let history = FamilyHistory()
        let start = Date()
        let families = [family("App", bundlePath: "/App.app", members: [
            member(record(10, command: "App", residentBytes: 100), bundlePath: "/App.app"),
        ])]

        history.record(rows: [appRow("/App.app", cpu: 1, memory: 1_000_000)],
                       families: families, selected: nil, at: start)
        history.record(rows: [appRow("/App.app", cpu: 1, memory: 2_000_000)],
                       families: families, selected: nil, at: start.addingTimeInterval(30))
        #expect(history.growth(for: "/App.app") == nil)
        #expect(!history.hasWatchedLongEnough(for: "/App.app"))

        history.record(rows: [appRow("/App.app", cpu: 1, memory: 3_000_000)],
                       families: families, selected: nil, at: start.addingTimeInterval(300))
        let growth = history.growth(for: "/App.app")
        #expect(growth?.deltaBytes == 2_000_000)
        #expect(growth?.span == .seconds(300))
        #expect(history.hasWatchedLongEnough(for: "/App.app"))
    }

    @Test("Memory that fell is reported as a fall, not clamped to zero")
    func growthCanBeNegative() {
        let history = FamilyHistory()
        let start = Date()
        let families = [family("App", bundlePath: "/App.app", members: [
            member(record(10, command: "App", residentBytes: 100), bundlePath: "/App.app"),
        ])]
        history.record(rows: [appRow("/App.app", cpu: 1, memory: 5_000_000)],
                       families: families, selected: nil, at: start)
        history.record(rows: [appRow("/App.app", cpu: 1, memory: 1_000_000)],
                       families: families, selected: nil, at: start.addingTimeInterval(300))
        #expect(history.growth(for: "/App.app")?.deltaBytes == -4_000_000)
    }

    @Test("Samples older than the retention window are dropped")
    func windowIsBounded() {
        let history = FamilyHistory()
        let start = Date()
        let families = [family("App", bundlePath: "/App.app", members: [
            member(record(10, command: "App", residentBytes: 100), bundlePath: "/App.app"),
        ])]
        history.record(rows: [appRow("/App.app", cpu: 1, memory: 1)],
                       families: families, selected: nil, at: start)
        history.record(
            rows: [appRow("/App.app", cpu: 1, memory: 2)], families: families, selected: nil,
            at: start.addingTimeInterval(FamilyHistory.window.totalSeconds + 60))
        #expect(history.points(for: "/App.app").count == 1)
    }

    @Test("A relaunch inside a tracked family is observed across two samples")
    func relaunchObserved() {
        let history = FamilyHistory()
        let start = Date()
        let row = appRow("/App.app", cpu: 1, memory: 1)

        history.record(
            rows: [row],
            families: [family("App", bundlePath: "/App.app", members: [
                member(record(10, command: "renderer", residentBytes: 1),
                       bundlePath: "/App.app"),
            ])],
            selected: nil, at: start)
        #expect(history.relaunchCount(for: "/App.app") == 0)

        history.record(
            rows: [row],
            families: [family("App", bundlePath: "/App.app", members: [
                member(record(11, command: "renderer", residentBytes: 1),
                       bundlePath: "/App.app"),
            ])],
            selected: nil, at: start.addingTimeInterval(2))
        #expect(history.relaunchCount(for: "/App.app") == 1)
    }
}

// MARK: - Diagnostics

@Suite("Family diagnostics")
struct FamilyDiagnosticsTests {
    private func text(
        row: InventoryRow, growth: MemoryGrowth? = nil, relaunches: Int? = nil
    ) -> String {
        FamilyDiagnostics.text(
            row: row, provenance: GroupingProvenance(), growth: growth,
            relaunches: relaunches, machine: MachineContext.current(),
            at: Date(timeIntervalSince1970: 0))
    }

    @Test("Disk activity is always stated as unavailable, never as a number")
    func diskIsNeverInvented() {
        let output = text(row: appRow("App", cpu: 12, memory: 1_000_000))
        #expect(output.contains("Disk activity not available"))
        #expect(output.contains("per-app disk I/O is not readable"))
    }

    @Test("Memory carries the resident-versus-footprint caveat")
    func memoryIsLabelled() {
        let output = text(row: appRow("App", cpu: 12, memory: 1_000_000))
        #expect(output.contains("resident size, not footprint"))
    }

    @Test("Growth and relaunches say they are unknown rather than reporting zero")
    func unknownIsNotZero() {
        let output = text(row: appRow("App", cpu: 12, memory: 1_000_000))
        #expect(output.contains("Growth        not enough history yet"))
        #expect(output.contains("Relaunches    not observed long enough to say"))
    }

    @Test("A measured growth and relaunch count are reported with their window")
    func measuredValuesAreReported() {
        let output = text(
            row: appRow("App", cpu: 12, memory: 1_000_000),
            growth: MemoryGrowth(deltaBytes: 1_900_000_000, span: .seconds(600)),
            relaunches: 3)
        #expect(output.contains("over the last 10 min observed"))
        #expect(output.contains("3 observed"))
    }

    @Test("A family we may not measure says so instead of printing zeroes")
    func unmeasurableFamily() {
        var row = appRow("WindowServer", cpu: 0, memory: 0)
        row = InventoryRow(
            id: row.id, name: row.name, executablePath: nil, kind: .application,
            percentOfOneCore: 0, residentBytes: 0, isMeasurable: false,
            processCount: 1, qualification: nil, children: [])
        let output = text(row: row)
        #expect(output.contains("CPU (family)  not available"))
        #expect(!output.contains("0.0% of one core"))
    }

    @Test("A signed byte figure reads as a direction, and zero as no change")
    func signedBytes() {
        #expect(FamilyDiagnostics.signedBytes(0) == "no change")
        #expect(FamilyDiagnostics.signedBytes(1_000_000).hasPrefix("+"))
        #expect(FamilyDiagnostics.signedBytes(-1_000_000).hasPrefix("−"))
    }
}

// MARK: - Inspector metadata

@MainActor
@Suite("Inspector bundle metadata")
struct InspectorMetadataTests {
    @Test("A process with no bundle has no subtitle to show")
    func noBundle() {
        #expect(FamilyInspectorView.bundleSubtitle(nil) == nil)
    }

    @Test("A real bundle yields its version and the directory it lives in")
    func realBundle() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let subtitle = FamilyInspectorView.bundleSubtitle(path)
        #expect(subtitle?.contains("/System/Applications/Utilities") == true)
    }

    @Test("A bundle with no readable Info.plist falls back to the directory alone")
    func unreadableBundle() {
        let subtitle = FamilyInspectorView.bundleSubtitle("/Applications/Nope.app")
        #expect(subtitle == "/Applications")
    }
}
