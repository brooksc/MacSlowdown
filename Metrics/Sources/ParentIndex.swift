import Darwin
import Foundation

/// Resolves a process's parent, safely (FR-003).
///
/// `ppid` comes free with the sysctl enumeration, and it is the only signal that
/// links a process living outside any bundle to the application responsible for
/// it — 14 shells under a terminal, or a CLI tool a GUI app spawned.
///
/// Measured on a real machine (probe/FINDINGS.md): it cannot replace the
/// executable path, because **82% of the process table is parented by launchd**.
/// macOS launches helpers through launchd and XPC rather than by forking from the
/// application, so for four processes in five `ppid` is 1 and carries nothing.
/// Where it does point at a real process it is worth having, and where it does
/// not it must change nothing.
public struct ParentIndex: Sendable {
    public struct Parent: Sendable, Equatable {
        public let bundlePath: String
        public let parentCommand: String
    }

    /// Only the most recently started process for each pid, so a pid that has been
    /// handed on twice resolves to the current holder.
    private let byPID: [pid_t: (identity: ProcessIdentity, bundlePath: String?, name: String)]

    public init(_ inputs: [(record: ProcessRecord, resolved: ResolvedIdentity)]) {
        var index: [pid_t: (ProcessIdentity, String?, String)] = [:]
        for input in inputs {
            // The resolved name, not p_comm. TerminalApp's executable is called "stable"
            // and AssistantApp's is "codex", so "started by stable" would tell a user
            // nothing at all.
            let candidate = (input.record.identity, input.resolved.appBundlePath,
                             input.resolved.displayName(command: input.record.command))
            if let existing = index[input.record.identity.pid],
               existing.0.startTime > input.record.identity.startTime {
                continue
            }
            index[input.record.identity.pid] = candidate
        }
        byPID = index
    }

    /// The application bundle of the process that started this one, if there is a
    /// parent we can trust.
    ///
    /// Returns nil for a process parented by launchd or the kernel, for a parent
    /// that is not itself in a bundle, and — importantly — for a parent that
    /// cannot really be the parent.
    public func bundleOfParent(of record: ProcessRecord) -> Parent? {
        // launchd (1) and the kernel (0) tell us nothing: they are the parent of
        // most of the table.
        guard record.ppid > 1 else { return nil }
        guard let parent = byPID[record.ppid] else { return nil }

        // PID reuse guard. `ppid` is a bare pid with no start time, so the process
        // now holding that number may be unrelated to the one that did the
        // forking. A real parent must have started strictly before its child.
        //
        // This is not theoretical: macOS wraps pid allocation at 99999, and on a
        // machine with 12 days of uptime the counter had already wrapped —
        // long-lived processes held pids near 99999 while new ones were being
        // issued from around 45000.
        guard parent.identity.startTime < record.identity.startTime else { return nil }

        guard let bundlePath = parent.bundlePath else { return nil }
        return Parent(bundlePath: bundlePath, parentCommand: parent.name)
    }
}
