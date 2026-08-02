// TASK-3 spike: can we establish stable application-family identity for an
// arbitrary PID under App Sandbox? (FR-003, FR-016, FR-039)
//
// Three candidate identity sources, in descending order of desirability:
//   1. Code signature (bundle ID + team ID) via SecCodeCopyGuestWithAttributes.
//      Best: stable across app updates, forgery-resistant, gives team identity.
//   2. Executable path walked up to the OUTERMOST .app bundle.
//      Works for other-uid processes (proc_pidpath succeeds for 1037/1058).
//   3. NSRunningApplication bundleIdentifier. GUI apps only, no helpers.

import AppKit
import Darwin
import Foundation
import Security

setvbuf(stdout, nil, _IONBF, 0)

// MARK: - Candidate 1: code signing identity

struct SignedIdentity {
    var bundleID: String?
    var teamID: String?
    var status: OSStatus
}

func signedIdentity(_ pid: Int32) -> SignedIdentity {
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
    let st = SecCodeCopyGuestWithAttributes(nil, attrs, SecCSFlags(rawValue: 0), &code)
    guard st == errSecSuccess, let code else {
        return SignedIdentity(bundleID: nil, teamID: nil, status: st)
    }
    var info: CFDictionary?
    let st2 = SecCodeCopySigningInformation(
        unsafeBitCast(code, to: SecStaticCode.self),
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &info)
    guard st2 == errSecSuccess, let dict = info as? [String: Any] else {
        return SignedIdentity(bundleID: nil, teamID: nil, status: st2)
    }
    return SignedIdentity(
        bundleID: dict[kSecCodeInfoIdentifier as String] as? String,
        teamID: dict[kSecCodeInfoTeamIdentifier as String] as? String,
        status: errSecSuccess)
}

// MARK: - Candidate 2: outermost .app bundle from executable path

/// Helpers live at .../Parent.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper.
/// The OUTERMOST .app is the user-meaningful family; the innermost is the helper.
func outermostAppBundle(_ path: String) -> String? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard let idx = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    return parts[...idx].joined(separator: "/")
}

func pidPath(_ pid: Int32) -> String? {
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
    return String(cString: buf)
}

// MARK: - Enumeration (sysctl, the sandbox-safe path)

func allProcs() -> [(pid: Int32, comm: String, uid: UInt32)] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard buf.withUnsafeMutableBytes({ sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }) == 0
    else { return [] }
    let n = size / MemoryLayout<kinfo_proc>.stride
    return buf.withUnsafeBytes { raw in
        let p = raw.bindMemory(to: kinfo_proc.self)
        return (0..<min(n, p.count)).compactMap { i in
            var kp = p[i]
            let pid = kp.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let comm = withUnsafeBytes(of: &kp.kp_proc.p_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            return (pid, comm, kp.kp_eproc.e_ucred.cr_uid)
        }
    }
}

// MARK: - Run

let procs = allProcs()
let me = geteuid()
let own = procs.filter { $0.uid == me }
let other = procs.filter { $0.uid != me }

var signedOK = 0, signedOwnOK = 0, signedOtherOK = 0
var teamOK = 0
var statusCounts: [OSStatus: Int] = [:]
var pathOK = 0, bundleOK = 0
var families: [String: [String]] = [:]
var samples: [String] = []

let clock = ContinuousClock()
let elapsed = clock.measure {
    for (pid, comm, uid) in procs {
        let sid = signedIdentity(pid)
        if sid.bundleID != nil {
            signedOK += 1
            if uid == me { signedOwnOK += 1 } else { signedOtherOK += 1 }
            if sid.teamID != nil { teamOK += 1 }
        } else {
            statusCounts[sid.status, default: 0] += 1
        }

        let path = pidPath(pid)
        if path != nil { pathOK += 1 }
        let bundle = path.flatMap(outermostAppBundle)
        if bundle != nil { bundleOK += 1 }

        if let bundle {
            families[bundle, default: []].append("\(comm)[\(pid)]")
        }
        if samples.count < 12, let path, path.contains(".app") {
            samples.append("  \(comm)[\(pid)] uid=\(uid)\n"
                + "    signed : \(sid.bundleID ?? "nil") team=\(sid.teamID ?? "nil") st=\(sid.status)\n"
                + "    bundle : \(outermostAppBundle(path) ?? "nil")")
        }
    }
}

print("=== TASK-3: application-family identity ===")
print("sandboxed: \(NSHomeDirectory().contains("/Containers/"))")
print("procs: \(procs.count) (own-uid \(own.count), other-uid \(other.count))")
print("")
print("--- Candidate 1: code signature (SecCodeCopyGuestWithAttributes) ---")
print("bundle ID obtained : \(signedOK)/\(procs.count)   own=\(signedOwnOK)/\(own.count) other=\(signedOtherOK)/\(other.count)")
print("team ID obtained   : \(teamOK)/\(procs.count)")
if !statusCounts.isEmpty {
    let top = statusCounts.sorted { $0.value > $1.value }.prefix(4)
        .map { "OSStatus \($0.key)×\($0.value)" }.joined(separator: "  ")
    print("failures           : \(top)")
}
print("")
print("--- Candidate 2: outermost .app from proc_pidpath ---")
print("path obtained      : \(pathOK)/\(procs.count)")
print("inside .app bundle : \(bundleOK)/\(procs.count)")
print("")
print("--- Candidate 3: NSRunningApplication ---")
let apps = NSWorkspace.shared.runningApplications
print("GUI apps           : \(apps.count), with bundleID \(apps.filter { $0.bundleIdentifier != nil }.count)")
print("")
print("--- Multi-process families (helper grouping, FR-003) ---")
for (bundle, members) in families.sorted(by: { $0.value.count > $1.value.count }).prefix(6) {
    print("  \(URL(fileURLWithPath: bundle).lastPathComponent)  ->  \(members.count) processes")
    print("     \(members.prefix(4).joined(separator: ", "))\(members.count > 4 ? " ..." : "")")
}
print("")
print("--- Samples ---")
samples.prefix(6).forEach { print($0) }
print("")
print(String(format: "identity sweep cost: %.1f ms for %d procs",
             elapsed.totalSecondsCompat * 1000, procs.count))

extension Duration {
    var totalSecondsCompat: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
