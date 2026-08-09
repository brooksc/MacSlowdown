import AppKit
import Darwin
import Foundation

// TASK-57.1: the inventory shows rows named `2.1.220` and `2.1.226`.
//
// Question: which step of the naming order produces a version number as an
// application name, and which processes on this machine are affected?
//
// Reproduces ProcessNaming's exact order — NSRunningApplication.localizedName,
// then the outermost .app/.appex Info.plist (CFBundleDisplayName, then
// CFBundleName) — and prints every process whose resolved name looks like a
// version, together with the step that produced it.

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
        let comm = withUnsafeBytes(of: &proc.p_comm) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return (entry.kp_proc.p_pid, comm)
    }
}

func executablePath(pid: pid_t) -> String? {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let written = buffer.withUnsafeMutableBytes {
        proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
    }
    guard written > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(written)), as: UTF8.self)
}

let namedBundleSuffixes = [".app", ".appex"]

func namingBundle(for path: String) -> String? {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard let index = components.firstIndex(where: { component in
        namedBundleSuffixes.contains { component.hasSuffix($0) }
    }) else { return nil }
    return components[...index].joined(separator: "/")
}

func outermostAppBundle(_ path: String) -> String? {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    return components[...index].joined(separator: "/")
}

func plist(atPath bundle: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: bundle + "/Contents/Info.plist"),
          let contents = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
    else { return nil }
    return contents
}

func bundleName(atPath bundle: String) -> (value: String, key: String)? {
    guard let contents = plist(atPath: bundle) else { return nil }
    for key in ["CFBundleDisplayName", "CFBundleName"] {
        if let value = contents[key] as? String, !value.isEmpty { return (value, key) }
    }
    return nil
}

func runningApplicationName(pid: pid_t) -> String? {
    guard let name = NSRunningApplication(processIdentifier: pid)?.localizedName,
          !name.isEmpty else { return nil }
    return name
}

/// Purely numeric, dot-separated: 2.1.220, 141.0.7390.55, 1.2, 26.
func looksLikeVersion(_ name: String) -> Bool {
    !name.isEmpty && name.allSatisfy { $0.isNumber || $0 == "." } && name.contains { $0.isNumber }
}

let table = processTable()
print("processes: \(table.count)\n")

var versionNamed = 0
var namedCount = 0

struct Hit {
    let pid: pid_t
    let comm: String
    let path: String
    let step: String
    let name: String
    let bundle: String
    let appBundle: String?
    let displayNameKey: String?
    let identifier: String?
    let executableKey: String?
}
var hits: [Hit] = []

for entry in table {
    guard let path = executablePath(pid: entry.pid) else { continue }
    let bundle = namingBundle(for: path)

    var step = ""
    var name: String?
    var key: String?
    if let running = runningApplicationName(pid: entry.pid) {
        name = running
        step = "NSRunningApplication.localizedName"
    } else if let bundle, let found = bundleName(atPath: bundle) {
        name = found.value
        step = "Info.plist \(found.key) of \(bundle)"
        key = found.key
    }

    guard let name else { continue }
    namedCount += 1
    guard looksLikeVersion(name) else { continue }
    versionNamed += 1

    let contents = bundle.flatMap(plist(atPath:))
    hits.append(Hit(
        pid: entry.pid, comm: entry.comm, path: path, step: step, name: name,
        bundle: bundle ?? "(none)",
        appBundle: outermostAppBundle(path),
        displayNameKey: key,
        identifier: contents?["CFBundleIdentifier"] as? String,
        executableKey: contents?["CFBundleExecutable"] as? String))
}

print("named: \(namedCount)   version-like names: \(versionNamed)\n")

for hit in hits.sorted(by: { $0.name < $1.name }) {
    print("name         : \(hit.name)")
    print("  pid        : \(hit.pid)  comm: \(hit.comm)")
    print("  step       : \(hit.step)")
    print("  path       : \(hit.path)")
    print("  namingBndl : \(hit.bundle)")
    print("  outermost  : \(hit.appBundle ?? "(none)")")
    print("  CFBundleID : \(hit.identifier ?? "(none)")")
    print("  CFBundleExe: \(hit.executableKey ?? "(none)")")
    print("")
}

// Second question: how many processes fall through to a p_comm that is itself a
// bundle-identifier-shaped fragment, e.g. `com.apple.Safari`?
var identifierFragments: [(pid_t, String, String?)] = []
for entry in table {
    let path = executablePath(pid: entry.pid)
    let bundle = path.flatMap(namingBundle(for:))
    let named = runningApplicationName(pid: entry.pid) != nil
        || (bundle.flatMap(bundleName(atPath:)) != nil)
    guard !named else { continue }
    if entry.comm.utf8.count >= 16 && entry.comm.contains(".")
        && entry.comm.split(separator: ".").count >= 2 {
        identifierFragments.append((entry.pid, entry.comm, path))
    }
}
print("--- unnamed processes whose p_comm is a truncated dotted identifier ---")
for item in identifierFragments.sorted(by: { $0.1 < $1.1 }) {
    print("  \(item.0)\t\(item.1)\t\(item.2 ?? "(no path)")")
}
print("count: \(identifierFragments.count)")

// Third: what the shipping resolution order produces for the same table, so the
// fix is checked against live processes and not only against fixtures.
//
// Compile with the framework's own sources rather than a copy of them:
//   swiftc -O version-name-probe.swift ../../Metrics/Sources/ProcessNaming.swift \
//          ../../Metrics/Sources/ProcessIdentityResolver.swift ...
#if METRICS
print("\n--- ProcessNaming.resolve over the live table ---")
var stillNonName = 0
for entry in table {
    let path = ProcessIdentityResolver.executablePath(pid: entry.pid)
    let resolved = ProcessNaming.resolve(pid: entry.pid, executablePath: path)
    let shown = resolved ?? ProcessNaming.labelled(command: entry.comm)
    if ProcessNaming.isNonName(shown) {
        stillNonName += 1
        print("  STILL A NON-NAME: \(shown)  <- \(path ?? "(no path)")")
    }
    if looksLikeVersion(entry.comm) || ProcessNaming.isBundleIdentifier(entry.comm) {
        print("  \(entry.comm.padding(toLength: 18, withPad: " ", startingAt: 0)) -> \(shown)")
    }
}
print("rows still showing a version or a bare identifier: \(stillNonName)")
#endif
