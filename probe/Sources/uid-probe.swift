import Darwin
import Foundation

// Two questions:
//   1. "Parented by launchd" and "owned by root" are different sets. How different?
//   2. Of the processes we cannot measure, how many are they, and who owns them?

struct Entry {
    let pid: pid_t
    let ppid: pid_t
    let uid: uid_t
    let comm: String
    let measurable: Bool
}

func table() -> [Entry] {
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&name, 4, nil, &size, nil, 0) == 0 else { return [] }
    var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
    guard sysctl(&name, 4, &buffer, &size, nil, 0) == 0 else { return [] }

    return buffer.prefix(size / MemoryLayout<kinfo_proc>.stride).map { entry in
        var proc = entry.kp_proc
        let comm = withUnsafeBytes(of: &proc.p_comm) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        var info = proc_taskinfo()
        let wanted = Int32(MemoryLayout<proc_taskinfo>.size)
        let got = proc_pidinfo(entry.kp_proc.p_pid, PROC_PIDTASKINFO, 0, &info, wanted)
        return Entry(pid: entry.kp_proc.p_pid, ppid: entry.kp_eproc.e_ppid,
                     uid: entry.kp_eproc.e_ucred.cr_uid, comm: comm, measurable: got == wanted)
    }
}

let all = table()
let me = getuid()

let launchdParented = all.filter { $0.ppid <= 1 && $0.pid > 1 }
print("=== launchd-parented is NOT the same as unmeasurable ===")
print("parented by launchd: \(launchdParented.count)")
print("  of those, our uid: \(launchdParented.count { $0.uid == me })")
print("  of those, MEASURABLE: \(launchdParented.count { $0.measurable })")
print("  of those, denied:    \(launchdParented.count { !$0.measurable })")

print("")
print("=== who can we actually measure? ===")
print("total processes: \(all.count)")
print("measurable: \(all.count { $0.measurable })")
print("denied:     \(all.count { !$0.measurable })")

var byUID: [uid_t: (total: Int, denied: Int)] = [:]
for entry in all {
    var bucket = byUID[entry.uid] ?? (0, 0)
    bucket.total += 1
    if !entry.measurable { bucket.denied += 1 }
    byUID[entry.uid] = bucket
}
print("")
print("=== by owner ===")
for (uid, counts) in byUID.sorted(by: { $0.value.total > $1.value.total }) {
    let who = uid == me ? "us (\(uid))" : uid == 0 ? "root" : "uid \(uid)"
    print("  \(who): \(counts.total) processes, \(counts.denied) denied")
}

print("")
print("=== would a 'System processes' bucket be well-defined? ===")
let otherUID = all.filter { $0.uid != me }
print("processes not owned by us: \(otherUID.count)")
print("  of those, denied: \(otherUID.count { !$0.measurable })")
let ourDenied = all.filter { $0.uid == me && !$0.measurable }
print("our own processes we still cannot measure: \(ourDenied.count)")
for entry in ourDenied.prefix(10) { print("    \(entry.comm) pid \(entry.pid)") }
