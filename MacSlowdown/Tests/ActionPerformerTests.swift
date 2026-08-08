import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func record(
    pid: pid_t = 4242, command: String = "MyApp", uid: uid_t = getuid()
) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: 1),
        command: command, uid: uid, ppid: 1,
        metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1 << 20)))
}

@MainActor
@Suite("Safe actions")
struct ActionPerformerTests {
    /// FR-037's guarantee, checked rather than promised: the complete set of
    /// actions the app can perform contains nothing that changes how a process
    /// runs. There is no flag, build configuration or dormant case that adds one.
    @Test("No action is destructive, and the set is exactly the five safe ones")
    func actionSetIsSafe() {
        #expect(ProcessAction.allCases.count == 5)
        #expect(ProcessAction.allCases.allSatisfy { !$0.isDestructive })

        let names = Set(ProcessAction.allCases.map(\.rawValue))
        #expect(names == ["activate", "revealInFinder", "openActivityMonitor",
                          "copyDiagnostics", "markExpected"])

        // Nothing in the vocabulary of process control appears anywhere in it.
        let titles = ProcessAction.allCases.map(\.title).joined(separator: " ").lowercased()
        for forbidden in ["quit", "kill", "force", "suspend", "pause", "throttle",
                          "limit", "nice", "priority", "terminate"] {
            #expect(!titles.contains(forbidden))
        }
    }

    /// FR-018: a protected process withholds the actions that touch it, and says
    /// why, rather than offering them and failing.
    @Test("Acting on a protected process is withheld with a reason")
    func protectedProcessWithheld() {
        let performer = ActionPerformer()
        let systemProcess = record(pid: 1, command: "launchd", uid: 0)

        let result = performer.perform(.activate, on: systemProcess, resolved: nil)
        guard case .withheld(let reason) = result else {
            Issue.record("expected the action to be withheld, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(!result.didRun)
    }

    /// Refusing to let someone copy diagnostics about WindowServer would be safety
    /// theatre. Protection withholds only what touches the process.
    @Test("Observation and hand-off stay available for protected processes")
    func observationStaysAvailable() {
        let systemProcess = record(pid: 1, command: "WindowServer", uid: 0)
        let available = SafetyPolicy().availableActions(for: systemProcess)
        #expect(available.contains(.copyDiagnostics))
        #expect(available.contains(.openActivityMonitor))
        #expect(!available.contains(.activate))
    }

    /// FR-017: report what happened. Silently returning success when the caller
    /// forgot to handle an action elsewhere would be the worst of both.
    @Test("markExpected reports that it is handled elsewhere rather than succeeding")
    func markExpectedIsNotSilent() {
        let result = ActionPerformer().perform(.markExpected, on: record(), resolved: nil)
        guard case .failed(let reason) = result else {
            Issue.record("expected a reported failure, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("settings"))
    }

    @Test("Copying with nothing to copy fails rather than clearing the clipboard")
    func copyWithNothingToCopy() {
        let result = ActionPerformer().perform(
            .copyDiagnostics, on: record(), resolved: nil, diagnostics: "")
        guard case .failed(let reason) = result else {
            Issue.record("expected a reported failure, got \(result)")
            return
        }
        #expect(reason.contains("nothing to copy"))
    }

    /// `proc_pidpath` fails for some processes. Revealing then has no location to
    /// reveal, and must say so rather than opening the wrong folder.
    @Test("Revealing a process whose path is unknown fails with that reason")
    func revealWithoutPath() {
        let result = ActionPerformer().perform(
            .revealInFinder, on: record(command: "unknown"), resolved: nil)
        guard case .failed(let reason) = result else {
            Issue.record("expected a reported failure, got \(result)")
            return
        }
        #expect(reason.contains("location"))
        #expect(reason.contains("unknown"), "the reason should name the process")
    }

    /// A process with no GUI cannot be brought forward. The result has to say that
    /// rather than claim success for a request the system ignored.
    @Test("Activating a process with no foreground presence reports why it could not")
    func activateNonGUIProcess() {
        // A PID that is ours but certainly not an application.
        let result = ActionPerformer().perform(
            .activate, on: record(pid: -1, command: "notanapp"), resolved: nil)
        #expect(!result.didRun)
        if case .succeeded = result {
            Issue.record("a non-application must not report success")
        }
    }
}

@Suite("Protection classification")
struct ProtectionTests {
    @Test("PID 1 and below is the kernel or launchd, and always protected")
    func lowPIDsProtected() {
        #expect(SafetyPolicy().protection(for: record(pid: 0, command: "kernel_task", uid: 0))
                == .kernel)
        #expect(SafetyPolicy().protection(for: record(pid: 1, command: "launchd", uid: 0))
                == .kernel)
    }

    @Test("Named critical services are protected even when they are ours")
    func criticalServicesProtected() {
        for name in ["WindowServer", "loginwindow", "coreaudiod", "Finder", "Dock"] {
            let subject = record(pid: 500, command: name, uid: getuid())
            #expect(SafetyPolicy().protection(for: subject) == .criticalService,
                    "\(name) should be protected")
        }
    }

    @Test("Another user's process is protected as system-owned")
    func otherUIDProtected() {
        #expect(SafetyPolicy().protection(for: record(pid: 500, command: "mds_stores", uid: 0))
                == .systemOwned)
    }

    @Test("An ordinary application of ours is not protected")
    func ordinaryProcessUnprotected() {
        #expect(SafetyPolicy().protection(for: record()) == nil)
        #expect(SafetyPolicy().availableActions(for: record()).count == ProcessAction.allCases.count)
    }

    /// FR-018 requires the classification hold independently of user preference.
    /// The type takes no settings at all, which is what makes that true.
    @Test("The policy explains a refusal and offers what remains")
    func refusalIsExplained() {
        let explanation = SafetyPolicy().explanation(for: record(pid: 1, command: "launchd", uid: 0))
        #expect(explanation?.contains("Activity Monitor") == true)
        #expect(SafetyPolicy().explanation(for: record()) == nil)
    }
}
