import Darwin
import Foundation

// Does the parent PID group processes better than the executable path does?
//
// The current grouping uses the outermost `.app` in the path, and marks a member
// uncertain when the code signature disagrees with the path. The question is
// whether `ppid` — which sysctl gives us for free — settles those cases.
//
// The concern is that modern macOS launches most helpers through launchd and XPC
// rather than by forking from the application, in which case ppid points at
// launchd and says nothing about which application a process serves. This
// measures how often that is true.

struct Entry {
    let pid: pid_t
    let ppid: pid_t
    let comm: String
    let startTime: UInt64
    let path: String?
    let bundle: String?
}

func processTable() -> [Entry] {
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    let count = size / MemoryLayout<kinfo_proc>.stride
    var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
    guard sysctl(&name, 4, &buffer, &size, nil, 0) == 0 else { return [] }

    return buffer.prefix(size / MemoryLayout<kinfo_proc>.stride).map { entry in
        var proc = entry.kp_proc
        let comm = withUnsafeBytes(of: &proc.p_comm) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        let start = UInt64(entry.kp_proc.p_starttime.tv_sec) * 1_000_000
            + UInt64(entry.kp_proc.p_starttime.tv_usec)
        let path = executablePath(entry.kp_proc.p_pid)
        return Entry(pid: entry.kp_proc.p_pid, ppid: entry.kp_eproc.e_ppid,
                     comm: comm, startTime: start, path: path,
                     bundle: path.flatMap(outermostAppBundle))
    }
}

func executablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
}

func outermostAppBundle(_ path: String) -> String? {
    let components = path.components(separatedBy: "/")
    guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    return components.prefix(through: index).joined(separator: "/")
}

let table = processTable()
let byPID = Dictionary(table.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

// MARK: - How informative is ppid at all?

var parentIsLaunchd = 0
var parentMissing = 0
var parentIsRealProcess = 0

for entry in table where entry.pid > 1 {
    if entry.ppid <= 1 {
        parentIsLaunchd += 1
    } else if byPID[entry.ppid] == nil {
        parentMissing += 1
    } else {
        parentIsRealProcess += 1
    }
}

print("=== is ppid informative? ===")
print("processes (excluding kernel and launchd): \(table.count { $0.pid > 1 })")
print("parent is launchd or the kernel: \(parentIsLaunchd)")
print("parent has already exited: \(parentMissing)")
print("parent is a live, identifiable process: \(parentIsRealProcess)")

// MARK: - Would ppid group bundled processes?

let bundled = table.filter { $0.bundle != nil }
var sameBundleAsParent = 0
var parentInDifferentBundle = 0
var parentNotBundled = 0
var parentIsLaunchdBundled = 0

for entry in bundled {
    guard entry.ppid > 1, let parent = byPID[entry.ppid] else {
        parentIsLaunchdBundled += 1
        continue
    }
    if parent.bundle == entry.bundle {
        sameBundleAsParent += 1
    } else if parent.bundle == nil {
        parentNotBundled += 1
    } else {
        parentInDifferentBundle += 1
    }
}

print("")
print("=== would ppid group processes that live in a .app? ===")
print("processes inside a .app: \(bundled.count)")
print("  parent is launchd, so ppid says nothing: \(parentIsLaunchdBundled)")
print("  parent is in the same bundle (ppid agrees with path): \(sameBundleAsParent)")
print("  parent is in a DIFFERENT bundle (ppid disagrees): \(parentInDifferentBundle)")
print("  parent is not in any bundle: \(parentNotBundled)")

// MARK: - The interesting case: could ppid rescue path-only guesses?

print("")
print("=== processes whose parent is in a different bundle ===")
for entry in bundled {
    guard entry.ppid > 1, let parent = byPID[entry.ppid], let parentBundle = parent.bundle,
          parentBundle != entry.bundle else { continue }
    let mine = (entry.bundle! as NSString).lastPathComponent
    let theirs = (parentBundle as NSString).lastPathComponent
    print("  \(entry.comm): path says \(mine), parent \(parent.comm) says \(theirs)")
}

// MARK: - Processes with NO bundle whose parent has one

// These are the ones grouping currently misses entirely: a helper binary living
// outside any bundle, spawned by an application. If ppid finds them, it adds
// attribution the path cannot.
print("")
print("=== unbundled processes whose parent IS an application ===")
var rescuable = 0
for entry in table where entry.bundle == nil && entry.pid > 1 {
    guard let parent = byPID[entry.ppid], let parentBundle = parent.bundle else { continue }
    rescuable += 1
    if rescuable <= 25 {
        print("  \(entry.comm) <- \((parentBundle as NSString).lastPathComponent)")
    }
}
print("total: \(rescuable)")

// MARK: - PID reuse hazard

// ppid is a bare pid, with no start time. If a parent exited and its pid was
// recycled, the "parent" we find is an unrelated process. Count how often the
// claimed parent started AFTER the child, which is impossible for a real parent.
var impossibleParents = 0
for entry in table where entry.ppid > 1 {
    guard let parent = byPID[entry.ppid] else { continue }
    if parent.startTime > entry.startTime { impossibleParents += 1 }
}
print("")
print("=== PID reuse hazard ===")
print("processes whose claimed parent started after them (so it is not the real parent): \(impossibleParents)")
