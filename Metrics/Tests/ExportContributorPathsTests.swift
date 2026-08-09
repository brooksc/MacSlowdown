import Foundation
import Testing

@testable import Metrics

/// The "File paths" choice can only act on paths a caller supplied. If two paths
/// that produce reports gathered them differently, the same toggle would mean
/// different things in two reports of the same incident — so the gathering lives
/// with the builder and every caller uses it.
@Suite("Contributor paths for a report")
struct ExportContributorPathsTests {
    private func member(pid: pid_t, startTime: UInt64, path: String?) -> FamilyMember {
        FamilyMember(
            record: ProcessRecord(
                identity: ProcessIdentity(pid: pid, startTime: startTime),
                command: "proc\(pid)", uid: 501, ppid: 1,
                metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 0))),
            resolved: ResolvedIdentity(executablePath: path, appBundlePath: nil,
                                       bundleID: nil, teamID: nil),
            membership: .certain)
    }

    @Test("Every member with a recorded path appears, keyed by (pid, start time)")
    func pathsAreGathered() {
        let families = [
            ProcessFamily(id: "a", displayName: "A", bundlePath: "/Applications/A.app",
                          members: [member(pid: 1, startTime: 10, path: "/Applications/A.app/x"),
                                    member(pid: 2, startTime: 20, path: "/Applications/A.app/y")]),
            ProcessFamily(id: "b", displayName: "B", bundlePath: nil,
                          members: [member(pid: 3, startTime: 30, path: "/usr/bin/b")]),
        ]

        let paths = IncidentReport.contributorPaths(in: families)
        #expect(paths.count == 3)
        #expect(paths[ProcessIdentity(pid: 2, startTime: 20)] == "/Applications/A.app/y")
        #expect(paths[ProcessIdentity(pid: 3, startTime: 30)] == "/usr/bin/b")
    }

    /// A process whose path was never recorded must not acquire one, and must not be
    /// counted as a path the user hid (FR-002: unavailable is not redacted).
    @Test("A member with no recorded path contributes nothing")
    func missingPathsAreAbsent() {
        let families = [ProcessFamily(
            id: "a", displayName: "A", bundlePath: nil,
            members: [member(pid: 1, startTime: 10, path: nil),
                      member(pid: 2, startTime: 20, path: "/usr/bin/b")])]

        let paths = IncidentReport.contributorPaths(in: families)
        #expect(paths.count == 1)
        #expect(paths[ProcessIdentity(pid: 1, startTime: 10)] == nil)
    }

    /// A recycled PID must not inherit the previous process's path. macOS wraps PID
    /// allocation at 99999 and it has been observed wrapping in practice.
    @Test("A reused PID with a new start time is a different key")
    func pidReuseDoesNotMerge() {
        let families = [ProcessFamily(
            id: "a", displayName: "A", bundlePath: nil,
            members: [member(pid: 7, startTime: 1, path: "/old/binary"),
                      member(pid: 7, startTime: 2, path: "/new/binary")])]

        let paths = IncidentReport.contributorPaths(in: families)
        #expect(paths[ProcessIdentity(pid: 7, startTime: 1)] == "/old/binary")
        #expect(paths[ProcessIdentity(pid: 7, startTime: 2)] == "/new/binary")
    }
}
