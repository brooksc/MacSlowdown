import Darwin
import Foundation
import Testing

@testable import Metrics

/// How many members were grouped by parent lineage rather than by bundle.
///
/// A local helper rather than a property on `ProcessFamily`: the app counts the
/// same thing, but it does so in one pass across all four kinds of evidence
/// (`GroupingProvenance`), so a single-category property on the framework type
/// had no caller outside these assertions (TASK-81).
private func spawnedMemberCount(_ family: ProcessFamily?) -> Int? {
    family?.members.count { if case .byParent = $0.membership { true } else { false } }
}

private func record(
    pid: pid_t, ppid: pid_t, startTime: UInt64, command: String
) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: startTime),
        command: command, uid: getuid(), ppid: ppid,
        metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1 << 20)))
}

private func resolved(bundle: String?, bundleID: String? = nil) -> ResolvedIdentity {
    ResolvedIdentity(
        executablePath: bundle.map { $0 + "/Contents/MacOS/Thing" } ?? "/bin/zsh",
        appBundlePath: bundle, bundleID: bundleID, teamID: nil)
}

private typealias Input = (record: ProcessRecord, resolved: ResolvedIdentity)

@Suite("Parent index")
struct ParentIndexTests {
    /// 82% of a real process table is parented by launchd. For all of those, the
    /// parent link must change nothing at all.
    @Test("launchd and the kernel are not parents worth following")
    func launchdIsNotAParent() {
        let child = record(pid: 500, ppid: 1, startTime: 200, command: "daemon")
        let index = ParentIndex([(child, resolved(bundle: nil))])
        #expect(index.bundleOfParent(of: child) == nil)

        let kernelChild = record(pid: 501, ppid: 0, startTime: 200, command: "kernel-ish")
        #expect(index.bundleOfParent(of: kernelChild) == nil)
    }

    @Test("A real parent in a bundle is found, and named")
    func realParentFound() {
        let warp = record(pid: 100, ppid: 1, startTime: 100, command: "Warp")
        let shell = record(pid: 200, ppid: 100, startTime: 500, command: "zsh")
        let index = ParentIndex([
            (warp, resolved(bundle: "/Applications/Warp.app")),
            (shell, resolved(bundle: nil)),
        ])

        let parent = index.bundleOfParent(of: shell)
        #expect(parent?.bundlePath == "/Applications/Warp.app")
        #expect(parent?.parentCommand == "Warp")
    }

    /// The hazard that makes this worth guarding. macOS wraps pid allocation at
    /// 99999, and on a machine with 12 days of uptime the counter had already
    /// wrapped — so the process holding a given pid may not be the one that forked.
    @Test("A parent that started after its child is rejected")
    func recycledParentRejected() {
        // pid 100 was recycled: the process holding it now started AFTER the child.
        let impostor = record(pid: 100, ppid: 1, startTime: 900, command: "Warp")
        let orphan = record(pid: 200, ppid: 100, startTime: 500, command: "zsh")
        let index = ParentIndex([
            (impostor, resolved(bundle: "/Applications/Warp.app")),
            (orphan, resolved(bundle: nil)),
        ])

        #expect(index.bundleOfParent(of: orphan) == nil,
                "a process cannot have been started by one that did not yet exist")
    }

    @Test("A parent outside any bundle groups nothing")
    func unbundledParent() {
        let shell = record(pid: 100, ppid: 1, startTime: 100, command: "zsh")
        let child = record(pid: 200, ppid: 100, startTime: 500, command: "node")
        let index = ParentIndex([(shell, resolved(bundle: nil)), (child, resolved(bundle: nil))])
        #expect(index.bundleOfParent(of: child) == nil)
    }

    @Test("A parent that has exited is not resolved to whatever holds its pid")
    func exitedParent() {
        let child = record(pid: 200, ppid: 999, startTime: 500, command: "orphan")
        let index = ParentIndex([(child, resolved(bundle: nil))])
        #expect(index.bundleOfParent(of: child) == nil)
    }

    /// If a pid appears twice in one snapshot, the later starter is the current
    /// holder — the earlier entry is stale.
    @Test("A duplicated pid resolves to the most recently started process")
    func duplicatePIDResolvesToNewest() {
        let old = record(pid: 100, ppid: 1, startTime: 100, command: "Old")
        let new = record(pid: 100, ppid: 1, startTime: 400, command: "New")
        let child = record(pid: 200, ppid: 100, startTime: 900, command: "child")
        let index = ParentIndex([
            (old, resolved(bundle: "/Applications/Old.app")),
            (new, resolved(bundle: "/Applications/New.app")),
            (child, resolved(bundle: nil)),
        ])
        #expect(index.bundleOfParent(of: child)?.bundlePath == "/Applications/New.app")
    }
}

@Suite("Grouping by parent")
struct ParentGroupingTests {
    /// The case that motivated this: a terminal with many shells appeared as many
    /// unrelated rows, when the honest answer is that the terminal is what is
    /// costing you.
    @Test("Shells started by a terminal are grouped under it")
    func shellsGroupUnderTerminal() {
        var inputs: [Input] = [(
            record(pid: 100, ppid: 1, startTime: 100, command: "Warp"),
            resolved(bundle: "/Applications/Warp.app", bundleID: "dev.warp.Warp"))]
        for pid in pid_t(200)..<214 {
            inputs.append((record(pid: pid, ppid: 100, startTime: 500, command: "zsh"),
                           resolved(bundle: nil)))
        }

        let families = FamilyGrouper.group(inputs)
        #expect(families.count == 1, "14 shells and a terminal is one family, not fifteen")

        #expect(families.first?.members.count == 15)
        #expect(spawnedMemberCount(families.first) == 14)
    }

    /// FR-003 keeps the individual records beneath the aggregate: grouping must
    /// never absorb a process out of existence.
    @Test("Grouped children remain individually visible")
    func childrenStayVisible() {
        let inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "Warp"),
             resolved(bundle: "/Applications/Warp.app")),
            (record(pid: 200, ppid: 100, startTime: 500, command: "zsh"),
             resolved(bundle: nil)),
        ]
        let family = FamilyGrouper.group(inputs).first
        let commands = family?.members.map(\.record.command).sorted()
        #expect(commands == ["Warp", "zsh"])
    }

    /// A child is labelled by the evidence that placed it there, which is lineage,
    /// not location. It should say so rather than claiming the same certainty as a
    /// binary living inside the bundle.
    @Test("A spawned child says which process started it")
    func spawnedChildIsLabelled() {
        let inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "Warp"),
             resolved(bundle: "/Applications/Warp.app")),
            (record(pid: 200, ppid: 100, startTime: 500, command: "zsh"),
             resolved(bundle: nil)),
        ]
        let family = FamilyGrouper.group(inputs).first
        let child = family?.members.first { $0.record.command == "zsh" }
        guard case .byParent(let reason)? = child?.membership else {
            Issue.record("expected the child to be marked as spawned")
            return
        }
        #expect(reason.contains("Warp"))
    }

    /// A spawned child brings its own name — `claude`, `zsh` — and members arrive in
    /// whatever order the snapshot's dictionary yields. Letting any member name the
    /// family would make the row's title depend on that order.
    @Test("A spawned child never supplies the family's name")
    func spawnedChildDoesNotNameTheFamily() {
        let warp = ResolvedIdentity(
            executablePath: "/Applications/Warp.app/Contents/MacOS/stable",
            appBundlePath: "/Applications/Warp.app", bundleID: "dev.warp.Warp",
            teamID: nil, friendlyName: "Warp")
        let child = ResolvedIdentity(
            executablePath: "/Users/someone/.local/share/claude/versions/2.1.226",
            appBundlePath: nil, bundleID: nil, teamID: nil, friendlyName: "claude")

        // The child first, which is the order that used to name the family "claude".
        let inputs: [Input] = [
            (record(pid: 200, ppid: 100, startTime: 500, command: "2.1.226"), child),
            (record(pid: 100, ppid: 1, startTime: 100, command: "stable"), warp),
        ]
        let family = FamilyGrouper.group(inputs).first
        #expect(family?.displayName == "Warp")
        #expect(spawnedMemberCount(family) == 1)
    }

    /// Lineage is evidence, not a guess, so it must not trip the uncertainty
    /// marker that exists for unconfirmed path claims.
    @Test("A spawned child does not make the family uncertain")
    func spawnedIsNotUncertain() {
        let inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "Warp"),
             resolved(bundle: "/Applications/Warp.app", bundleID: "dev.warp.Warp")),
            (record(pid: 200, ppid: 100, startTime: 500, command: "zsh"),
             resolved(bundle: nil)),
        ]
        let family = FamilyGrouper.group(inputs).first
        #expect(family?.hasUncertainMembers == false)
        #expect(spawnedMemberCount(family) == 1)
    }

    /// The corroboration case: the path says the binary belongs here, the
    /// signature cannot confirm it, and the parent can.
    @Test("A parent in the same bundle promotes an unsignable member to certain")
    func parentCorroboratesPath() {
        let bundle = "/Applications/Helium.app"
        let main = record(pid: 100, ppid: 1, startTime: 100, command: "Helium")
        let helper = record(pid: 200, ppid: 100, startTime: 500, command: "Helium Helper (R")

        let withoutParent: [Input] = [
            (main, resolved(bundle: bundle, bundleID: "net.imput.helium")),
            (record(pid: 200, ppid: 1, startTime: 500, command: "Helium Helper (R"),
             resolved(bundle: bundle, bundleID: nil)),
        ]
        #expect(FamilyGrouper.group(withoutParent).first?.hasUncertainMembers == true,
                "with no signature and no parent, the path claim is unconfirmed")

        let withParent: [Input] = [
            (main, resolved(bundle: bundle, bundleID: "net.imput.helium")),
            (helper, resolved(bundle: bundle, bundleID: nil)),
        ]
        #expect(FamilyGrouper.group(withParent).first?.hasUncertainMembers == false,
                "the parent link confirms what the signature could not")
    }

    /// Real case from the probe: SkyComputerUseSe runs from Codex Computer Use.app
    /// but was spawned by ChatGPT.
    ///
    /// A parent in a different bundle is **not** a contradiction when the signature
    /// already confirms the path — it just means another application launched this
    /// one, which is ordinary. Marking it uncertain would put a warning on a
    /// correct grouping. A process is never moved to its parent's family, so there
    /// is no silent choice being made either way.
    @Test("A different parent does not undermine a signature-confirmed grouping")
    func differentParentDoesNotUnsettleAConfirmedGrouping() {
        let inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "ChatGPT"),
             resolved(bundle: "/Applications/ChatGPT.app", bundleID: "com.openai.chat")),
            (record(pid: 200, ppid: 100, startTime: 500, command: "SkyComputerUseSe"),
             resolved(bundle: "/Applications/Codex Computer Use.app",
                      bundleID: "com.openai.codex")),
        ]
        let families = FamilyGrouper.group(inputs)
        let codex = families.first { $0.bundlePath?.contains("Codex") == true }
        #expect(codex?.hasUncertainMembers == false)
        #expect(families.count == 2, "it stays in its own bundle, not its launcher's")
    }

    /// Where the signature cannot confirm the path, a parent pointing somewhere
    /// else leaves the claim exactly as unconfirmed as it was. The parent link
    /// only ever promotes; it never rescues a claim it disagrees with.
    @Test("An unsignable member whose parent is elsewhere stays uncertain")
    func unconfirmedWithForeignParentStaysUncertain() {
        let inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "ChatGPT"),
             resolved(bundle: "/Applications/ChatGPT.app", bundleID: "com.openai.chat")),
            (record(pid: 200, ppid: 100, startTime: 500, command: "node_repl"),
             resolved(bundle: "/Applications/Other.app", bundleID: nil)),
        ]
        let other = FamilyGrouper.group(inputs)
            .first { $0.bundlePath?.contains("Other") == true }
        #expect(other?.hasUncertainMembers == true)
    }

    /// The overwhelmingly common case must be untouched by all of this.
    @Test("A launchd-parented process is grouped exactly as before")
    func launchdParentedUnchanged() {
        let inputs: [Input] = [
            (record(pid: 300, ppid: 1, startTime: 100, command: "notifyd"),
             resolved(bundle: nil)),
        ]
        let families = FamilyGrouper.group(inputs)
        #expect(families.count == 1)
        #expect(families.first?.isStandalone == true)
        #expect(spawnedMemberCount(families.first) == 0)
    }

    /// FR-039: a user correction outranks anything we inferred.
    @Test("Detaching a process stops it being pulled in by its parent")
    func userDetachWins() {
        let child = record(pid: 200, ppid: 100, startTime: 500, command: "zsh")
        let inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "Warp"),
             resolved(bundle: "/Applications/Warp.app")),
            (child, resolved(bundle: nil)),
        ]
        let families = FamilyGrouper.group(
            inputs, overrides: GroupingOverrides(detached: [child.identity]))
        #expect(families.count == 2, "the detached shell stands on its own again")
    }

    /// Grouping is presentation over preserved records, so nothing may vanish.
    @Test("Every input process appears in exactly one family")
    func nothingIsLost() {
        var inputs: [Input] = [
            (record(pid: 100, ppid: 1, startTime: 100, command: "Warp"),
             resolved(bundle: "/Applications/Warp.app")),
            (record(pid: 101, ppid: 1, startTime: 100, command: "notifyd"),
             resolved(bundle: nil)),
        ]
        for pid in pid_t(200)..<205 {
            inputs.append((record(pid: pid, ppid: 100, startTime: 500, command: "zsh"),
                           resolved(bundle: nil)))
        }

        let families = FamilyGrouper.group(inputs)
        let placed = families.flatMap { $0.members }.map(\.record.identity)
        #expect(placed.count == inputs.count)
        #expect(Set(placed).count == inputs.count, "no process may appear twice")
    }
}
