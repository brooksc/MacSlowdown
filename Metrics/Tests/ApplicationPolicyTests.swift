import Foundation
import Testing

@testable import Metrics

private func identity(bundleID: String? = nil, path: String? = nil) -> ResolvedIdentity {
    ResolvedIdentity(executablePath: path, appBundlePath: path,
                     bundleID: bundleID, teamID: nil)
}

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("macslowdown-policy-\(UUID().uuidString)")
        .appendingPathComponent("policies.json")
}

@Suite("Application policies")
struct ApplicationPolicyTests {
    @Test("A policy matches on signed identity, which survives app updates")
    func matchesOnBundleID() {
        let policy = ApplicationPolicy(
            bundleID: "com.apple.dt.Xcode", displayName: "Xcode", classification: .expected)
        // Same app, moved to a different path — still matches.
        #expect(policy.matches(identity(bundleID: "com.apple.dt.Xcode",
                                        path: "/Volumes/Elsewhere/Xcode.app"),
                               displayName: "Xcode"))
        #expect(!policy.matches(identity(bundleID: "com.other.app"), displayName: "Other"))
    }

    @Test("A policy falls back to bundle path when no signature exists")
    func matchesOnPath() {
        let policy = ApplicationPolicy(
            bundlePath: "/Applications/Thing.app", displayName: "Thing",
            classification: .ignored)
        #expect(policy.matches(identity(path: "/Applications/Thing.app"), displayName: "Thing"))
    }

    /// FR-016: suppressing an alert must never suppress the record.
    @Test("Expected and ignored suppress alerts; watched does not")
    func suppressionSemantics() {
        #expect(PolicyClassification.expected.suppressesNotification)
        #expect(PolicyClassification.ignored.suppressesNotification)
        #expect(!PolicyClassification.watched.suppressesNotification)
    }

    @Test("Setting a policy twice replaces rather than duplicates")
    func setReplaces() {
        let store = PolicyStore()
        store.setPolicy(ApplicationPolicy(bundleID: "a", displayName: "A", classification: .expected))
        store.setPolicy(ApplicationPolicy(bundleID: "a", displayName: "A", classification: .ignored))

        #expect(store.policies.count == 1)
        #expect(store.policies.first?.classification == .ignored)
    }

    /// FR-016: the user can review and revoke. Revoking restores default
    /// behaviour completely.
    @Test("Removing a policy restores default behaviour with nothing lingering")
    func removeRestoresDefault() {
        let store = PolicyStore()
        let policy = ApplicationPolicy(bundleID: "a", displayName: "A", classification: .ignored)
        store.setPolicy(policy)
        #expect(store.policy(for: identity(bundleID: "a"), displayName: "A") != nil)

        store.removePolicy(id: policy.id)
        #expect(store.policies.isEmpty)
        #expect(store.policy(for: identity(bundleID: "a"), displayName: "A") == nil)
    }
}

@Suite("Suppression audit trail")
struct SuppressionAuditTests {
    /// FR-016: an alert the user never saw must still be findable, or a policy
    /// becomes a way to hide evidence from yourself.
    @Test("A suppressed detection is recorded and retrievable")
    func suppressionIsRecorded() throws {
        let store = PolicyStore()
        store.recordSuppression(SuppressedDetection(
            application: "HandBrake", classification: .expected, severity: .high))

        #expect(store.suppressedDetections.count == 1)
        let entry = try #require(store.suppressedDetections.first)
        #expect(entry.summary.contains("HandBrake"))
        #expect(entry.summary.contains("not alerted"))
    }

    @Test("Most recent suppressions come first and the trail is bounded")
    func trailIsBoundedAndOrdered() {
        let store = PolicyStore(maximumSuppressed: 5)
        for index in 0..<20 {
            store.recordSuppression(SuppressedDetection(
                application: "App\(index)", classification: .ignored, severity: .moderate))
        }
        #expect(store.suppressedDetections.count == 5)
        #expect(store.suppressedDetections.first?.application == "App19")
    }
}

@Suite("Grouping corrections")
struct GroupingCorrectionTests {
    private func snapshot(_ commands: [String]) -> ProcessSnapshot {
        var records: [ProcessIdentity: ProcessRecord] = [:]
        for (index, command) in commands.enumerated() {
            let id = ProcessIdentity(pid: Int32(100 + index), startTime: 1)
            records[id] = ProcessRecord(identity: id, command: command, uid: 501, ppid: 1,
                                        metrics: .measured(ProcessMetrics(cpuTicks: 1,
                                                                          residentBytes: 1)))
        }
        return ProcessSnapshot(records: records, takenAt: ContinuousClock.now,
                               sweepDuration: .milliseconds(1))
    }

    /// FR-039: a correction must outlive the process it was made about, so it is
    /// keyed on the command rather than on a PID.
    @Test("A split correction detaches the process wherever it reappears")
    func splitApplies() {
        let store = PolicyStore()
        store.addCorrection(GroupingCorrection(processCommand: "helper", kind: .split))

        // A different PID for the same command — a relaunch.
        let overrides = store.overrides(for: snapshot(["helper", "other"]))
        #expect(overrides.detached.count == 1)
        #expect(overrides.attached.isEmpty)
    }

    @Test("A merge correction attaches the process to the named family")
    func mergeApplies() {
        let store = PolicyStore()
        store.addCorrection(GroupingCorrection(
            processCommand: "updater", kind: .merge, intoBundlePath: "/Applications/Thing.app"))

        let overrides = store.overrides(for: snapshot(["updater"]))
        #expect(overrides.attached.values.first == "/Applications/Thing.app")
    }

    /// FR-039: corrections are reversible and preserve original evidence.
    @Test("Removing a correction restores the inferred grouping")
    func correctionsAreReversible() {
        let store = PolicyStore()
        let correction = GroupingCorrection(processCommand: "helper", kind: .split)
        store.addCorrection(correction)
        #expect(!store.overrides(for: snapshot(["helper"])).detached.isEmpty)

        store.removeCorrection(id: correction.id)
        #expect(store.overrides(for: snapshot(["helper"])).detached.isEmpty)
    }

    @Test("A correction and the grouper agree end to end")
    func correctionChangesGrouping() throws {
        let store = PolicyStore()
        let helper = ProcessIdentity(pid: 200, startTime: 1)
        let record = ProcessRecord(identity: helper, command: "BrowserApp Helper", uid: 501, ppid: 1,
                                   metrics: .measured(ProcessMetrics(cpuTicks: 1, residentBytes: 1)))
        let resolved = ResolvedIdentity(
            executablePath: "/Applications/BrowserApp.app/Contents/Frameworks/H.app/Contents/MacOS/H",
            appBundlePath: "/Applications/BrowserApp.app",
            bundleID: "net.imput.helium.helper", teamID: "T")

        let grouped = FamilyGrouper.group([(record, resolved)])
        #expect(grouped.first?.bundlePath == "/Applications/BrowserApp.app")

        store.addCorrection(GroupingCorrection(processCommand: "BrowserApp Helper", kind: .split))
        let overrides = GroupingOverrides(detached: [helper])
        let split = FamilyGrouper.group([(record, resolved)], overrides: overrides)
        #expect(split.first?.isStandalone == true)
    }
}

@Suite("Policy persistence")
struct PolicyPersistenceTests {
    @Test("Policies and corrections survive a restart")
    func survivesRestart() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = PolicyStore(url: url)
        original.setPolicy(ApplicationPolicy(
            bundleID: "com.example.app", displayName: "Example", classification: .expected))
        original.addCorrection(GroupingCorrection(processCommand: "helper", kind: .split))
        original.recordSuppression(SuppressedDetection(
            application: "Example", classification: .expected, severity: .high))

        let restored = PolicyStore(url: url)
        #expect(restored.policies.count == 1)
        #expect(restored.corrections.count == 1)
        #expect(restored.suppressedDetections.count == 1)
        #expect(restored.policies.first?.classification == .expected)
    }

    /// FR-029: the user can delete everything the app has stored about them.
    @Test("Everything can be deleted")
    func deleteAll() {
        let store = PolicyStore()
        store.setPolicy(ApplicationPolicy(bundleID: "a", displayName: "A", classification: .ignored))
        store.addCorrection(GroupingCorrection(processCommand: "h", kind: .split))
        store.recordSuppression(SuppressedDetection(
            application: "A", classification: .ignored, severity: .moderate))

        store.removeAll()
        #expect(store.policies.isEmpty)
        #expect(store.corrections.isEmpty)
        #expect(store.suppressedDetections.isEmpty)
    }

    @Test("Corrupt stored state does not block startup")
    func corruptStateTolerated() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("not json".utf8).write(to: url)

        let store = PolicyStore(url: url)
        #expect(store.policies.isEmpty)
    }
}
