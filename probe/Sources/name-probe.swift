import AppKit
import Darwin
import Foundation

// Measures whether a sandboxed app can obtain a human-meaningful name for each
// process, rather than the kernel's 16-byte p_comm.
//
// Three candidate sources, in the order we would prefer them:
//   1. NSRunningApplication.localizedName — GUI applications only, no entitlement.
//   2. The outermost .app bundle's Info.plist, read from disk. This is the one in
//      doubt: reading files outside our container may be denied.
//   3. p_comm, which is what we ship today and is truncated to 16 bytes.
//
// Also measures icon availability, since the reference interface shows one per
// process, and how often a name would still be a bare fragment after all three.

struct Row {
    let pid: pid_t
    let comm: String
    let path: String?
    let bundlePath: String?
    let runningAppName: String?
    let infoPlistName: String?
    let hasIcon: Bool
}

// MARK: - Process table

func processTable() -> [(pid: pid_t, comm: String)] {
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

    let count = size / MemoryLayout<kinfo_proc>.stride
    var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
    guard sysctl(&name, 4, &buffer, &size, nil, 0) == 0 else { return [] }

    let actual = size / MemoryLayout<kinfo_proc>.stride
    return buffer.prefix(actual).map { entry in
        var proc = entry.kp_proc
        let comm = withUnsafeBytes(of: &proc.p_comm) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (entry.kp_proc.p_pid, comm)
    }
}

func executablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(cString: buffer)
}

/// The outermost `.app` in the path — the user-meaningful application, not the
/// helper bundle nested inside it.
func outermostAppBundle(_ path: String) -> String? {
    var components = path.components(separatedBy: "/")
    guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    components = Array(components.prefix(through: index))
    return components.joined(separator: "/")
}

/// Any bundle at all, outermost first. Most of the process table is XPC services,
/// app extensions and framework helpers, none of which live in a `.app` — so
/// grouping by `.app` alone leaves the large majority unnamed.
let bundleSuffixes = [".app", ".appex", ".xpc", ".framework", ".bundle", ".pluginkit"]

func outermostBundle(_ path: String) -> String? {
    let components = path.components(separatedBy: "/")
    guard let index = components.firstIndex(where: { component in
        bundleSuffixes.contains { component.hasSuffix($0) }
    }) else { return nil }
    return components.prefix(through: index).joined(separator: "/")
}

// MARK: - Name sources

/// Source 1. GUI applications only.
func runningApplicationName(_ pid: pid_t) -> String? {
    NSRunningApplication(processIdentifier: pid)?.localizedName
}

/// Source 2. Reading a bundle outside our container is exactly what the sandbox
/// may refuse, so this distinguishes "no such key" from "could not read at all".
enum PlistResult {
    case name(String)
    case noUsefulKey
    case unreadable(String)
}

func infoPlistName(bundlePath: String) -> PlistResult {
    let plistPath = bundlePath + "/Contents/Info.plist"
    guard let data = FileManager.default.contents(atPath: plistPath) else {
        // Distinguish denial from absence: statting tells us whether it exists.
        var info = stat()
        let exists = stat(plistPath, &info) == 0
        return .unreadable(exists ? "read denied (exists)" : "not readable, not stattable")
    }
    guard let plist = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any] else {
        return .unreadable("unparseable")
    }
    for key in ["CFBundleDisplayName", "CFBundleName"] {
        if let value = plist[key] as? String, !value.isEmpty { return .name(value) }
    }
    return .noUsefulKey
}

/// Whether an icon is obtainable. The reference interface shows one per row.
func hasIcon(pid: pid_t, bundlePath: String?) -> Bool {
    if NSRunningApplication(processIdentifier: pid)?.icon != nil { return true }
    guard let bundlePath else { return false }
    // NSWorkspace.icon(forFile:) returns a generic icon rather than nil when it
    // cannot read the bundle, so a non-nil result alone would overstate this.
    // Compare against the generic executable icon to tell them apart.
    let icon = NSWorkspace.shared.icon(forFile: bundlePath)
    let generic = NSWorkspace.shared.icon(forFileType: "public.executable")
    return icon.tiffRepresentation != generic.tiffRepresentation
}

// MARK: - Run

let table = processTable()
var rows: [Row] = []
var plistOutcomes: [String: Int] = [:]
var anyBundleNames = 0
var anyBundleCount = 0
var bundleKinds: [String: Int] = [:]
var anyBundleExamples: [String] = []

for entry in table {
    let path = executablePath(entry.pid)
    let bundle = path.flatMap(outermostAppBundle)

    var plistName: String?
    if let bundle {
        switch infoPlistName(bundlePath: bundle) {
        case .name(let value):
            plistName = value
            plistOutcomes["read ok", default: 0] += 1
        case .noUsefulKey:
            plistOutcomes["read ok but no name key", default: 0] += 1
        case .unreadable(let why):
            plistOutcomes[why, default: 0] += 1
        }
    }

    if let path, let anyBundle = outermostBundle(path) {
        anyBundleCount += 1
        let kind = "." + (anyBundle.components(separatedBy: ".").last ?? "?")
        bundleKinds[kind, default: 0] += 1
        if case .name(let value) = infoPlistName(bundlePath: anyBundle) {
            anyBundleNames += 1
            if bundle == nil, anyBundleExamples.count < 30 {
                anyBundleExamples.append("  \(entry.comm) -> \(value)  [\(kind)]")
            }
        }
    }

    rows.append(Row(
        pid: entry.pid, comm: entry.comm, path: path, bundlePath: bundle,
        runningAppName: runningApplicationName(entry.pid),
        infoPlistName: plistName,
        hasIcon: hasIcon(pid: entry.pid, bundlePath: bundle)))
}

let total = rows.count
let withPath = rows.count { $0.path != nil }
let inBundle = rows.count { $0.bundlePath != nil }
let withRunningName = rows.count { $0.runningAppName != nil }
let withPlistName = rows.count { $0.infoPlistName != nil }
let withAnyFriendly = rows.count { $0.runningAppName != nil || $0.infoPlistName != nil }
let withIcon = rows.count { $0.hasIcon }
/// p_comm is 16 bytes; anything at that length was almost certainly cut.
let truncated = rows.count { $0.comm.utf8.count >= 15 }
let truncatedRescued = rows.count {
    $0.comm.utf8.count >= 15 && ($0.runningAppName != nil || $0.infoPlistName != nil)
}

print("=== friendly names, sandboxed ===")
print("processes: \(total)")
print("proc_pidpath: \(withPath)")
print("inside a .app bundle: \(inBundle)")
print("NSRunningApplication.localizedName: \(withRunningName)")
print("Info.plist display name: \(withPlistName)")
print("either source: \(withAnyFriendly)  (\(percent(withAnyFriendly, total))%)")
print("icon available: \(withIcon)")
print("")
print("p_comm at the 16-byte limit (likely truncated): \(truncated)")
print("  of those, rescued by a friendly name: \(truncatedRescued)")
print("  still only a fragment: \(truncated - truncatedRescued)")
print("")
print("Info.plist read outcomes:")
for (outcome, count) in plistOutcomes.sorted(by: { $0.value > $1.value }) {
    print("  \(outcome): \(count)")
}

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "0" : String(format: "%.1f", Double(part) / Double(whole) * 100)
}

print("")
print("=== widening beyond .app: any bundle type ===")
print("processes inside a bundle of any kind: \(anyBundleCount)")
print("of which Info.plist yields a name: \(anyBundleNames)  (\(percent(anyBundleNames, total))% of all processes)")
print("bundle kinds:")
for (kind, count) in bundleKinds.sorted(by: { $0.value > $1.value }) {
    print("  \(kind): \(count)")
}
print("names gained that .app alone would have missed:")
for line in anyBundleExamples { print(line) }

print("")
print("=== every process whose p_comm looks truncated ===")
for row in rows where row.comm.utf8.count >= 15 {
    let friendly = row.runningAppName ?? row.infoPlistName ?? "(none)"
    let source = row.runningAppName != nil ? "runningApp"
        : row.infoPlistName != nil ? "Info.plist" : "-"
    print("  \(row.comm) -> \(friendly)  [\(source)]")
}

print("")
print("=== sample of bundled applications ===")
for row in rows.filter({ $0.bundlePath != nil }).prefix(25) {
    let friendly = row.runningAppName ?? row.infoPlistName ?? "(none)"
    print("  pid \(row.pid) comm=\(row.comm) friendly=\(friendly) icon=\(row.hasIcon)")
}

print("")
print("=== non-bundled processes: what is the best we can do? ===")
let standalone = rows.filter { $0.bundlePath == nil }
print("count: \(standalone.count)")
print("with a friendly name from any source: \(standalone.count { $0.runningAppName != nil })")
for row in standalone.prefix(15) {
    print("  \(row.comm)  path=\(row.path ?? "(denied)")")
}
