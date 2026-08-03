import Darwin
import Foundation
import Testing

@testable import Metrics

private func record(
    _ command: String, pid: Int32 = 5_000, uid: uid_t = getuid()
) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: 1),
        command: command, uid: uid, ppid: 1,
        metrics: .measured(ProcessMetrics(cpuTicks: 1, residentBytes: 1 << 20)))
}

@Suite("Protected process classification")
struct ProtectionTests {
    /// FR-018: protected fixtures cannot be targeted by control actions.
    @Test("Critical services are protected")
    func criticalServicesProtected() {
        let policy = SafetyPolicy()
        for name in ["WindowServer", "launchd", "coreaudiod", "loginwindow", "Dock"] {
            #expect(policy.isProtected(record(name)), "\(name) should be protected")
        }
    }

    @Test("Processes owned by another user are protected")
    func otherUidProtected() {
        let policy = SafetyPolicy()
        #expect(policy.protection(for: record("mds_stores", uid: 0)) != nil)
        #expect(policy.protection(for: record("backupd", uid: 0)) == .systemOwned)
    }

    @Test("pid 0 and 1 are the kernel and launchd")
    func lowPidsProtected() {
        let policy = SafetyPolicy()
        #expect(policy.protection(for: record("kernel_task", pid: 0)) == .kernel)
        #expect(policy.protection(for: record("launchd", pid: 1)) == .kernel)
    }

    @Test("An ordinary user application is not protected")
    func userApplicationNotProtected() {
        let policy = SafetyPolicy()
        #expect(!policy.isProtected(record("Xcode")))
        #expect(policy.protection(for: record("Safari")) == nil)
    }

    /// FR-018: the classification is explained at a category level, not as a
    /// lecture about the specific process.
    @Test("Protection is explained, and the explanation offers what remains")
    func protectionExplained() throws {
        let policy = SafetyPolicy()
        let explanation = try #require(policy.explanation(for: record("WindowServer")))
        #expect(explanation.contains("macOS"))
        #expect(explanation.contains("Activity Monitor"),
                "refusing without offering an alternative is unhelpful")
        #expect(policy.explanation(for: record("Xcode")) == nil)
    }
}

@Suite("Action safety")
struct ActionSafetyTests {
    /// DR-06 and §7: the App Store build has no process control, so the entire
    /// action set must be non-destructive by construction rather than by filtering.
    @Test("No action in the entire set is destructive")
    func noDestructiveActionsExist() {
        for action in ProcessAction.allCases {
            #expect(!action.isDestructive, "\(action) is destructive")
            let text = (action.rawValue + " " + action.title).lowercased()
            for forbidden in ["quit", "kill", "force", "suspend", "pause", "throttle",
                              "renice", "terminate", "limit", "stop"] {
                #expect(!text.contains(forbidden), "\(action) suggests control: \(forbidden)")
            }
        }
    }

    @Test("A protected process cannot be activated or revealed")
    func protectedWithholdsTouchingActions() {
        let policy = SafetyPolicy()
        let windowServer = record("WindowServer")

        #expect(!policy.availability(of: .activate, for: windowServer).isAvailable)
        #expect(!policy.availability(of: .revealInFinder, for: windowServer).isAvailable)
        #expect(!policy.availableActions(for: windowServer).contains(.activate))
    }

    /// Refusing to let a user copy diagnostics about WindowServer would be safety
    /// theatre. Observation and hand-off stay available for everything.
    @Test("Observation and hand-off remain available for protected processes")
    func protectedKeepsObservation() {
        let policy = SafetyPolicy()
        let windowServer = record("WindowServer")

        #expect(policy.availability(of: .copyDiagnostics, for: windowServer).isAvailable)
        #expect(policy.availability(of: .openActivityMonitor, for: windowServer).isAvailable)
        #expect(!policy.availableActions(for: windowServer).isEmpty,
                "a protected process should still offer something useful")
    }

    @Test("An ordinary application offers the full set")
    func ordinaryApplicationFullSet() {
        let policy = SafetyPolicy()
        #expect(Set(policy.availableActions(for: record("Xcode"))) == Set(ProcessAction.allCases))
    }

    /// FR-017: an unavailable action is not shown as though it worked. Withheld
    /// actions are excluded from the offered list, and the reason is retrievable.
    @Test("A withheld action states why rather than failing silently")
    func withheldActionExplainsItself() throws {
        let policy = SafetyPolicy()
        let availability = policy.availability(of: .activate, for: record("coreaudiod"))
        guard case .unavailable(let reason) = availability else {
            Issue.record("expected coreaudiod's activate to be withheld")
            return
        }
        #expect(!reason.isEmpty)
        #expect(reason.lowercased().contains("macos"))
    }

    /// FR-018: the policy takes no user settings, so no preference can weaken it.
    @Test("The policy is non-overridable by construction")
    func policyTakesNoSettings() {
        // SafetyPolicy's only initialiser takes no arguments. If a settings
        // parameter is ever added, this test stops compiling, which is the point.
        let policy = SafetyPolicy()
        #expect(policy.isProtected(record("WindowServer")))
    }

    @Test("Classification holds against the live process table")
    func liveSystemClassification() {
        let policy = SafetyPolicy()
        let snapshot = ProcessSampler().snapshot()

        let protected = snapshot.records.values.filter { policy.isProtected($0) }
        let ordinary = snapshot.records.values.filter { !policy.isProtected($0) }

        #expect(!protected.isEmpty, "no protected processes found on a live Mac")
        #expect(!ordinary.isEmpty, "everything was classified protected")

        // Everything owned by another user must be protected — that is the bulk of
        // the protection and the part that must not regress.
        let otherUid = snapshot.records.values.filter { $0.uid != getuid() }
        for process in otherUid {
            #expect(policy.isProtected(process),
                    "\(process.command) (uid \(process.uid)) was not protected")
        }
    }
}
