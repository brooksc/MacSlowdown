import Foundation
import Synchronization
import Testing

@testable import Metrics

// MARK: - Fixtures

/// Tests run in parallel, so fixture PIDs come from an atomic counter rather than
/// a mutable global.
private let pidCounter = Atomic<Int32>(1000)

private func fixture(
    _ command: String,
    path: String?,
    bundleID: String? = nil,
    teamID: String? = "TEAM123",
    measurable: Bool = true
) -> (record: ProcessRecord, resolved: ResolvedIdentity) {
    let pid = pidCounter.wrappingAdd(1, ordering: .relaxed).newValue
    let identity = ProcessIdentity(pid: pid, startTime: 1_700_000_000)
    let record = ProcessRecord(
        identity: identity,
        command: command,
        uid: 501,
        ppid: 1,
        metrics: measurable
            ? .measured(ProcessMetrics(cpuTicks: 1_000_000, residentBytes: 64 << 20))
            : .notPermitted
    )
    let resolved = ResolvedIdentity(
        executablePath: path,
        appBundlePath: path.flatMap(ProcessIdentityResolver.outermostAppBundle),
        bundleID: bundleID,
        teamID: teamID
    )
    return (record, resolved)
}

/// A browser-shaped fixture: one main process plus helpers nested in the bundle.
private func browserFixtures() -> [(record: ProcessRecord, resolved: ResolvedIdentity)] {
    [
        fixture("Helium", path: "/Applications/Helium.app/Contents/MacOS/Helium",
                bundleID: "net.imput.helium"),
        fixture("Helium Helper (Renderer)",
                path: "/Applications/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper",
                bundleID: "net.imput.helium.helper.renderer"),
        fixture("Helium Helper (GPU)",
                path: "/Applications/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper",
                bundleID: "net.imput.helium.helper.gpu"),
    ]
}

// MARK: - Tests

@Suite("Application family grouping")
struct FamilyGroupingTests {
    /// AC#1: helper-heavy applications aggregate into one row rather than
    /// fragmenting across many.
    @Test("Browser helpers aggregate under the parent application")
    func browserHelpersAggregate() throws {
        let families = FamilyGrouper.group(browserFixtures())
        let helium = try #require(families.first { $0.displayName == "Helium" })

        #expect(helium.members.count == 3)
        #expect(helium.bundlePath == "/Applications/Helium.app")
        #expect(families.count == 1, "helpers should not form their own families")
    }

    /// AC#3: the aggregate never replaces the individual records.
    @Test("Individual PID records are preserved beneath the aggregate")
    func pidRecordsPreserved() throws {
        let fixtures = browserFixtures()
        let families = FamilyGrouper.group(fixtures)
        let helium = try #require(families.first)

        let expected = Set(fixtures.map(\.record.identity.pid))
        let actual = Set(helium.members.map(\.record.identity.pid))
        #expect(actual == expected)
    }

    /// AC#4: daemons and CLI tools are standalone, not families of one.
    @Test("Daemons and CLI tools are standalone, not one-member applications")
    func daemonsAreStandalone() throws {
        let families = FamilyGrouper.group([
            fixture("mds_stores", path: "/usr/sbin/mds_stores", bundleID: "com.apple.mds_stores"),
            fixture("zsh", path: "/bin/zsh", bundleID: nil, teamID: nil),
        ])

        #expect(families.count == 2)
        let allStandalone = families.allSatisfy(\.isStandalone)
        let allUnbundled = families.allSatisfy { $0.bundlePath == nil }
        #expect(allStandalone)
        #expect(allUnbundled)
        #expect(Set(families.map(\.displayName)) == ["mds_stores", "zsh"])
    }

    @Test("Applications and standalone processes coexist in one listing")
    func mixedListing() {
        let families = FamilyGrouper.group(
            browserFixtures() + [fixture("mds_stores", path: "/usr/sbin/mds_stores")]
        )
        #expect(families.count == 2)
        let standaloneCount = families.count(where: \.isStandalone)
        let bundledCount = families.count(where: { !$0.isStandalone })
        #expect(standaloneCount == 1)
        #expect(bundledCount == 1)
    }

    /// AC#5: the real false-grouping case found during the Tier 0 spike — an
    /// unrelated binary executing from inside an application bundle.
    @Test("A subprocess signed differently is grouped but labeled uncertain")
    func foreignSubprocessIsLabeled() throws {
        let families = FamilyGrouper.group([
            fixture("ChatGPT", path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
                    bundleID: "com.openai.chat"),
            fixture("node_repl",
                    path: "/Applications/ChatGPT.app/Contents/Resources/node/bin/node_repl",
                    bundleID: "org.nodejs.node"),
        ])

        let chatGPT = try #require(families.first { $0.displayName == "ChatGPT" })
        #expect(chatGPT.members.count == 2)
        #expect(chatGPT.hasUncertainMembers)

        let node = try #require(chatGPT.members.first { $0.record.command == "node_repl" })
        guard case .uncertain(let reason) = node.membership else {
            Issue.record("node_repl should be uncertain, got \(node.membership)")
            return
        }
        #expect(reason.contains("org.nodejs.node"))

        let main = try #require(chatGPT.members.first { $0.record.command == "ChatGPT" })
        #expect(main.membership == .certain)
    }

    @Test("Genuine helpers sharing the parent's identifier prefix are certain")
    func genuineHelpersAreCertain() throws {
        let families = FamilyGrouper.group(browserFixtures())
        let helium = try #require(families.first)
        #expect(!helium.hasUncertainMembers)
        let allCertain = helium.members.allSatisfy { $0.membership == .certain }
        #expect(allCertain)
    }

    @Test("A process matched by path with no signature is labeled uncertain")
    func unsignedMemberIsUncertain() throws {
        let families = FamilyGrouper.group([
            fixture("Thing", path: "/Applications/Thing.app/Contents/MacOS/Thing",
                    bundleID: "com.example.thing"),
            fixture("mystery", path: "/Applications/Thing.app/Contents/Helpers/mystery",
                    bundleID: nil, teamID: nil),
        ])
        let thing = try #require(families.first)
        #expect(thing.hasUncertainMembers)
    }

    /// AC#3 again, from the other direction: a denied process stays visible inside
    /// its family rather than disappearing from the listing.
    @Test("Processes whose metrics are denied remain visible in the family")
    func deniedMembersStayVisible() throws {
        let families = FamilyGrouper.group([
            fixture("Helium", path: "/Applications/Helium.app/Contents/MacOS/Helium",
                    bundleID: "net.imput.helium"),
            fixture("Helium Helper",
                    path: "/Applications/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper",
                    bundleID: "net.imput.helium.helper", measurable: false),
        ])
        let helium = try #require(families.first)
        #expect(helium.members.count == 2)
        #expect(helium.notMeasurableCount == 1)
    }
}

/// AC#2: grouping decisions are reversible. Nothing is destroyed — an override
/// only changes placement, and removing it restores the inferred grouping.
@Suite("Grouping is reversible")
struct GroupingOverrideTests {
    @Test("A user can split a process out of its inferred family")
    func splitOut() throws {
        let fixtures = browserFixtures()
        let helper = try #require(fixtures.first { $0.record.command.contains("GPU") })

        let overrides = GroupingOverrides(detached: [helper.record.identity])
        let families = FamilyGrouper.group(fixtures, overrides: overrides)

        #expect(families.count == 2)
        let standalone = families.first(where: \.isStandalone)
        let split = try #require(standalone)
        #expect(split.members.first?.record.identity == helper.record.identity)
    }

    @Test("A user can merge a standalone process into an application")
    func mergeInto() throws {
        let daemon = fixture("updater", path: "/usr/local/bin/updater", bundleID: nil, teamID: nil)
        let overrides = GroupingOverrides(
            attached: [daemon.record.identity: "/Applications/Helium.app"])

        let families = FamilyGrouper.group(browserFixtures() + [daemon], overrides: overrides)
        let helium = try #require(families.first { $0.displayName == "Helium" })

        #expect(helium.members.count == 4)
        let merged = try #require(helium.members.first { $0.record.command == "updater" })
        #expect(merged.membership == .userAssigned)
    }

    @Test("Removing an override restores the inferred grouping")
    func overridesAreReversible() throws {
        let fixtures = browserFixtures()
        let helper = try #require(fixtures.first { $0.record.command.contains("GPU") })

        let overridden = FamilyGrouper.group(
            fixtures, overrides: GroupingOverrides(detached: [helper.record.identity]))
        #expect(overridden.count == 2)

        let restored = FamilyGrouper.group(fixtures, overrides: .none)
        #expect(restored.count == 1)
        #expect(restored.first?.members.count == 3)
    }
}

@Suite("Family grouping over the live system")
struct LiveFamilyGroupingTests {
    @Test("Grouping the real process table produces both applications and standalones")
    func realSystemGrouping() {
        let snapshot = ProcessSampler().snapshot()
        let resolver = ProcessIdentityResolver()
        let families = FamilyGrouper.group(snapshot: snapshot, resolver: resolver)

        #expect(!families.isEmpty)
        let hasStandalone = families.contains(where: { $0.isStandalone })
        #expect(hasStandalone, "no standalone processes found")

        // Every process in the snapshot appears exactly once across all families.
        let grouped = families.flatMap { $0.members.map(\.record.identity) }
        #expect(Set(grouped).count == snapshot.records.count)
        #expect(grouped.count == snapshot.records.count, "a process was duplicated across families")
    }
}
