import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-77 / FR-039. The framework could already make a grouping correction, store
/// it, and turn it into a `GroupingOverrides`; `FamilyGrouper` could already apply
/// one. None of that was reachable, because `MonitorStore` never passed `overrides:`
/// and no view ever created a correction.
///
/// So these tests deliberately assert **reachability, not correctness**. Every one
/// of them starts at the app-level call the interface makes — `correctGrouping`,
/// `removeGroupingCorrection` — and ends at `store.families`, the property the
/// inventory renders. A `MetricsTests` case that drove `FamilyGrouper.group` with an
/// override directly would have passed on the day the defect was introduced, which
/// is exactly why the defect survived.
///
/// Process identities use PIDs above 99999. macOS wraps PID allocation at 99999, so
/// no such process can exist and the store's real identity resolver reliably returns
/// nothing for them — the grouping under test is then decided by the correction
/// alone, not by whatever happened to be running on the build machine.

// MARK: - Fixtures

private let thing = "/Applications/Thing.app"

private func record(_ pid: pid_t, command: String, startTime: UInt64 = 1) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: startTime),
        command: command, uid: getuid(), ppid: 1,
        metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 4096)))
}

private func snapshot(_ records: [ProcessRecord]) -> ProcessSnapshot {
    ProcessSnapshot(
        records: Dictionary(records.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a }),
        takenAt: ContinuousClock().now, sweepDuration: .milliseconds(2))
}

@MainActor
private func makeStore(_ policies: PolicyStore = PolicyStore()) -> MonitorStore {
    MonitorStore(policies: policies,
                 storage: StorageScreenModel(history: StorageHistory()))
}

private func temporaryPolicyURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("task77-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("policies.json")
}

// MARK: - The chain

@MainActor
@Suite("A grouping correction reaches the grouper (FR-039)")
struct GroupingCorrectionWiringTests {
    @Test("Without a correction, an unbundled process is standalone")
    func baseline() {
        let store = makeStore()
        store.regroup(from: snapshot([record(200_001, command: "widgetd")]))

        #expect(store.families.count == 1)
        #expect(store.families.first?.isStandalone == true)
        #expect(store.families.first?.bundlePath == nil)
    }

    /// The whole point of the task: the app-level call changes the app-level state.
    @Test("A merge made through the store changes the grouping the inventory reads")
    func mergeReachesTheGrouper() {
        let store = makeStore()
        store.regroup(from: snapshot([record(200_001, command: "widgetd")]))
        #expect(store.families.first?.bundlePath == nil)

        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing,
            displayName: "Widget Daemon"))

        #expect(store.families.count == 1)
        #expect(store.families.first?.bundlePath == thing)
        #expect(store.families.first?.displayName == "Thing")
        // FR-038: placed by the user, and labelled as such rather than presented
        // with the same confidence as a path match.
        #expect(store.families.first?.members.first?.membership == .userAssigned)
    }

    /// A correction made before the first sample must not be lost — it is stored and
    /// applies from the next sweep.
    @Test("A correction made before any sample applies to the first one")
    func correctionBeforeFirstSample() {
        let store = makeStore()
        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing))
        #expect(store.families.isEmpty)

        store.regroup(from: snapshot([record(200_001, command: "widgetd")]))
        #expect(store.families.first?.bundlePath == thing)
    }

    /// FR-039 + the PID-recycling rule: identity is `(pid, start time)` and macOS
    /// wraps allocation at 99999, so a correction keyed on a PID would attach itself
    /// to an unrelated process. This one survives both the PID and the start time
    /// changing.
    @Test("A correction survives the process being replaced by a new PID")
    func survivesPIDReplacement() {
        let store = makeStore()
        store.regroup(from: snapshot([record(200_001, command: "widgetd", startTime: 1)]))
        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing))
        #expect(store.families.first?.bundlePath == thing)

        // The daemon quits and comes back: different PID, later start time.
        store.regroup(from: snapshot([record(200_002, command: "widgetd", startTime: 99)]))
        #expect(store.families.first?.bundlePath == thing)
        #expect(store.families.first?.members.first?.record.identity.pid == 200_002)
    }

    /// FR-039: reversible from the interface, and reversing it restores the
    /// heuristic — not some third state.
    @Test("Undoing a correction restores the grouping MacSlowdown inferred")
    func reversible() {
        let store = makeStore()
        let correction = GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing)
        store.regroup(from: snapshot([record(200_001, command: "widgetd")]))
        store.correctGrouping(correction)
        #expect(store.families.first?.bundlePath == thing)

        store.removeGroupingCorrection(id: correction.id)
        #expect(store.families.first?.isStandalone == true)
        #expect(store.groupingCorrections.isEmpty)
    }

    /// Split is reached through the same chain. Two processes are merged into one
    /// application first, because a synthetic PID resolves to no bundle and there is
    /// otherwise nothing on this machine to detach them from.
    @Test("A split made through the store pulls one process back out")
    func splitReachesTheGrouper() {
        let store = makeStore()
        let table = snapshot([record(200_001, command: "widgetd"),
                              record(200_002, command: "helperd")])
        store.regroup(from: table)

        store.correctGrouping([
            GroupingCorrection(processCommand: "widgetd", kind: .merge, intoBundlePath: thing),
            GroupingCorrection(processCommand: "helperd", kind: .merge, intoBundlePath: thing),
        ])
        #expect(store.families.count == 1)
        #expect(store.families.first?.members.count == 2)

        store.correctGrouping(GroupingCorrection(
            processCommand: "helperd", kind: .split, displayName: "helperd"))
        let bundled = store.families.first { $0.bundlePath == thing }
        #expect(store.families.count == 2)
        #expect(bundled?.members.count == 1)
        #expect(bundled?.members.first?.record.command == "widgetd")
        #expect(store.families.contains { $0.isStandalone })
    }

    /// The `Split out…` and `Merge into…` menus write one correction per process, so
    /// a second decision about the same process has to replace the first rather than
    /// leaving both stored where whichever was found first would silently win.
    @Test("Correcting the same process twice replaces the earlier decision")
    func oneCorrectionPerSubject() {
        let store = makeStore()
        store.regroup(from: snapshot([record(200_001, command: "widgetd")]))
        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing))
        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .split))

        #expect(store.groupingCorrections.count == 1)
        #expect(store.families.first?.isStandalone == true)
    }

    /// FR-039's acceptance criterion: raw PID samples remain intact. A correction
    /// changes where readings are added up, never the readings or the census.
    @Test("A correction changes no reading and loses no process")
    func rawSamplesIntact() {
        let store = makeStore()
        let table = snapshot([record(200_001, command: "widgetd"),
                              record(200_002, command: "helperd")])
        store.regroup(from: table)
        let before = InventoryCensus.of(store.families)

        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing))
        let after = InventoryCensus.of(store.families)

        #expect(after.totalProcesses == before.totalProcesses)
        #expect(after.notMeasurableProcesses == before.notMeasurableProcesses)
        // Grouping moved; the per-PID records the families carry are the same
        // objects the snapshot held.
        let residents = store.families
            .flatMap(\.members)
            .compactMap { $0.record.measurements?.residentBytes }
        #expect(residents == [4096, 4096])
        #expect(store.families.flatMap(\.members).count == 2)
    }

    /// A correction is a rule, like a policy — it belongs in `policies.json` in our
    /// own container and goes nowhere else.
    @Test("A correction survives a restart, through the same store the policies use")
    func survivesRestart() {
        let url = temporaryPolicyURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = makeStore(PolicyStore(url: url))
        first.regroup(from: snapshot([record(200_001, command: "widgetd")]))
        first.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .merge, intoBundlePath: thing))

        // A second store over the same file is what a relaunch looks like.
        let relaunched = makeStore(PolicyStore(url: url))
        #expect(relaunched.groupingCorrections.count == 1)
        relaunched.regroup(from: snapshot([record(200_003, command: "widgetd", startTime: 7)]))
        #expect(relaunched.families.first?.bundlePath == thing)
    }

    /// The inspector asks this to decide what to list under "Your corrections".
    @Test("The inspector can find the corrections about the family in front of it")
    func correctionsAffectingMembers() {
        let store = makeStore()
        store.correctGrouping(GroupingCorrection(
            processCommand: "widgetd", kind: .split, displayName: "Widget Daemon"))

        #expect(store.groupingCorrections(
            affecting: [("widgetd", nil)]).count == 1)
        #expect(store.groupingCorrections(
            affecting: [("somethingElse", nil)]).isEmpty)
    }
}

// MARK: - The durable key

@Suite("A correction is keyed on something that outlives the process")
struct GroupingCorrectionKeyTests {
    /// The precise key. `proc_pidpath` answers for 1042 of 1063 processes and is
    /// unaffected by the sandbox, so this is the usual case.
    @Test("A path-keyed correction matches only that executable")
    func pathIsPrecise() {
        let correction = GroupingCorrection(
            processCommand: "node", executablePath: "/opt/homebrew/bin/node", kind: .split)

        #expect(correction.matches(command: "node",
                                   executablePath: "/opt/homebrew/bin/node"))
        #expect(!correction.matches(command: "node",
                                    executablePath: "/usr/local/bin/node"))
        // Never widens to the command when the path is unreadable: a precise
        // correction silently becoming a coarse one is worse than not applying.
        #expect(!correction.matches(command: "node", executablePath: nil))
        #expect(!correction.isKeyedOnCommandOnly)
    }

    /// The fallback, and the honesty it requires. `p_comm` is 16 bytes.
    @Test("A command-keyed correction says that it may cover more than one process")
    func commandIsCoarse() {
        let correction = GroupingCorrection(processCommand: "com.apple.WebKi", kind: .split)

        #expect(correction.matches(command: "com.apple.WebKi", executablePath: nil))
        #expect(correction.matches(command: "com.apple.WebKi",
                                   executablePath: "/anywhere/at/all"))
        #expect(correction.isKeyedOnCommandOnly)
        #expect(GroupingCorrectionCopy.scope(correction) != nil)
    }

    @Test("A path-keyed correction states no such caveat, because it has none")
    func pathNeedsNoCaveat() {
        let correction = GroupingCorrection(
            processCommand: "node", executablePath: "/opt/homebrew/bin/node", kind: .split)
        #expect(GroupingCorrectionCopy.scope(correction) == nil)
    }

    /// Corrections written before the path field existed decode with a nil path and
    /// keep working on their command key.
    @Test("A correction stored without a path still decodes")
    func decodesWithoutPath() throws {
        let json = Data("""
        {"processCommand":"widgetd","kind":"split","createdAt":0}
        """.utf8)
        let decoded = try JSONDecoder().decode(GroupingCorrection.self, from: json)
        #expect(decoded.executablePath == nil)
        #expect(decoded.id == "widgetd")
        #expect(decoded.matches(command: "widgetd", executablePath: "/usr/sbin/widgetd"))
    }
}

// MARK: - What the interface says about it

@Suite("Correction copy labels the user's answer as the user's (FR-038)")
struct GroupingCorrectionCopyTests {
    @Test("The machine's grouping is offered as a guess, not as a measurement")
    func heuristicIsLabelled() {
        #expect(GroupingCorrectionCopy.heuristic.contains("guess"))
        #expect(!GroupingCorrectionCopy.heuristic.lowercased().contains("measured"))
    }

    @Test("A correction is described as the user's, and bounded")
    func userProvidedIsLabelled() {
        let copy = GroupingCorrectionCopy.userProvided
        #expect(copy.contains("your correction"))
        #expect(copy.contains("not as a measurement"))
        // The FR-039 promises, in the place the user is about to act.
        #expect(copy.contains("undone"))
        #expect(copy.contains("this Mac"))
        #expect(copy.contains("never changes what an incident already recorded"))
    }

    @Test("Each correction reads back as something the user did")
    func describesTheAction() {
        let split = GroupingCorrection(
            processCommand: "keystone", kind: .split, displayName: "Keystone Agent")
        #expect(GroupingCorrectionCopy.describe(split)
            == "Keystone Agent — you separated this from the application it was "
            + "grouped under.")

        let merge = GroupingCorrection(
            processCommand: "keystone", kind: .merge,
            intoBundlePath: "/Applications/Google Chrome.app",
            displayName: "Keystone Agent")
        #expect(GroupingCorrectionCopy.describe(merge)
            == "Keystone Agent — you placed this in Google Chrome.")
    }

    /// A correction outlives the process, so its own name has to survive without one.
    @Test("A correction with no recorded name falls back to the command")
    func namelessCorrection() {
        let correction = GroupingCorrection(processCommand: "widgetd", kind: .split)
        #expect(correction.subject == "widgetd")
        #expect(GroupingCorrectionCopy.describe(correction).hasPrefix("widgetd —"))
    }
}
