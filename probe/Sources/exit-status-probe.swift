// MacSlowdown FR-046 exit-status probe.
//
// Answers one question: can a sandboxed Mac App Store build tell a process that
// CRASHED from one that exited normally?
//
// Today LifecycleTracker infers an exit from a (pid, start time) disappearing
// between two sysctl KERN_PROC_ALL snapshots. That carries no status at all, so
// the interface says "quit unexpectedly" about a `yes` or an `mdworker_shared`
// that simply finished. If exit status is reachable the product changes: a crash
// is worth reporting at one occurrence, a normal exit is not worth reporting at
// three.
//
// Candidates measured here, all public API:
//   1. kqueue EVFILT_PROC / NOTE_EXIT, NOTE_EXITSTATUS, NOTE_EXIT_DETAIL
//      — for processes we did NOT fork, and for children we did (the control).
//   2. kqueue EVFILT_PROC / NOTE_SIGNAL — does a fatal signal show up on the way in?
//   3. proc_pidinfo PROC_PIDT_SHORTBSDINFO — does anything survive the exit?
//   4. NSWorkspace.didTerminateApplicationNotification / NSRunningApplication —
//      does either distinguish a crashed .app from a quit one?
//
// Nothing here signals a process this probe did not create. Observing a
// termination is not process control (FR-037).
//
// The same source builds signed+sandboxed (build-probe.sh) and plain
// (swiftc); the diff between the two runs is the finding. Driven by
// run-exit-status-probe.sh, which also supplies the victim processes.

import AppKit
import Darwin
import Foundation
import ObjectiveC

// MARK: - Output

var log = ""
func emit(_ s: String = "") {
    log += s + "\n"
    print(s)
    fflush(stdout)
}

let started = Date()
func stamp() -> String { String(format: "t+%05.1fs", Date().timeIntervalSince(started)) }

// MARK: - EVFILT_PROC constants
//
// sys/event.h defines these as #defines wider than Int32, so they are restated
// here as UInt32 rather than fought with through the importer.

let fNOTE_EXIT: UInt32 = 0x8000_0000
let fNOTE_SIGNAL: UInt32 = 0x0800_0000
let fNOTE_EXITSTATUS: UInt32 = 0x0400_0000
let fNOTE_EXIT_DETAIL: UInt32 = 0x0200_0000
let fNOTE_EXIT_DECRYPTFAIL: UInt32 = 0x0001_0000
let fNOTE_EXIT_MEMORY: UInt32 = 0x0002_0000
let fNOTE_EXIT_CSERROR: UInt32 = 0x0004_0000

func flagNames(_ f: UInt32) -> String {
    var out: [String] = []
    if f & fNOTE_EXIT != 0 { out.append("NOTE_EXIT") }
    if f & fNOTE_SIGNAL != 0 { out.append("NOTE_SIGNAL") }
    if f & fNOTE_EXITSTATUS != 0 { out.append("NOTE_EXITSTATUS") }
    if f & fNOTE_EXIT_DETAIL != 0 { out.append("NOTE_EXIT_DETAIL") }
    if f & fNOTE_EXIT_DECRYPTFAIL != 0 { out.append("EXIT_DECRYPTFAIL") }
    if f & fNOTE_EXIT_MEMORY != 0 { out.append("EXIT_MEMORY") }
    if f & fNOTE_EXIT_CSERROR != 0 { out.append("EXIT_CSERROR") }
    let known = fNOTE_EXIT | fNOTE_SIGNAL | fNOTE_EXITSTATUS | fNOTE_EXIT_DETAIL
        | fNOTE_EXIT_DECRYPTFAIL | fNOTE_EXIT_MEMORY | fNOTE_EXIT_CSERROR
    let rest = f & ~known
    if rest != 0 { out.append(String(format: "0x%08x", rest)) }
    return out.isEmpty ? "(none)" : out.joined(separator: "|")
}

/// Decodes a wait(2)-style status the way FR-046 would have to.
///
/// The distinction the product needs is not "nonzero": a compiler exiting 1 on a
/// syntax error is a normal exit. Only a fatal signal is evidence of a crash,
/// and only some signals are.
func decodeWaitStatus(_ raw: Int) -> String {
    let status = Int32(truncatingIfNeeded: raw)
    let sig = status & 0x7F
    if sig == 0 {
        let code = (status >> 8) & 0xFF
        return "WIFEXITED, exit code \(code)  -> \(code == 0 ? "NORMAL" : "normal exit, nonzero code")"
    }
    if sig == 0x7F { return "WIFSTOPPED, signal \((status >> 8) & 0xFF)  -> stopped, not exited" }
    let core = (status & 0x80) != 0
    let crashy: Set<Int32> = [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE, SIGSYS]
    let name = strsignal(sig).map { String(cString: $0) } ?? "?"
    let verdict = crashy.contains(sig) ? "CRASH" : "terminated by signal, not a crash"
    return "WIFSIGNALED, \(signalName(sig)) (\(sig)) \(name)\(core ? ", core" : "")  -> \(verdict)"
}

func signalName(_ s: Int32) -> String {
    switch s {
    case SIGSEGV: return "SIGSEGV"
    case SIGBUS: return "SIGBUS"
    case SIGILL: return "SIGILL"
    case SIGABRT: return "SIGABRT"
    case SIGTRAP: return "SIGTRAP"
    case SIGFPE: return "SIGFPE"
    case SIGSYS: return "SIGSYS"
    case SIGKILL: return "SIGKILL"
    case SIGTERM: return "SIGTERM"
    case SIGINT: return "SIGINT"
    case SIGHUP: return "SIGHUP"
    case SIGQUIT: return "SIGQUIT"
    case SIGPIPE: return "SIGPIPE"
    default: return "signal \(s)"
    }
}

func errnoName(_ e: Int32) -> String {
    switch e {
    case EPERM: return "EPERM"
    case ESRCH: return "ESRCH"
    case EACCES: return "EACCES"
    case EINVAL: return "EINVAL"
    case ENOENT: return "ENOENT"
    case 0: return "ok"
    default: return "errno \(e) (\(String(cString: strerror(e))))"
    }
}

// MARK: - Process table
//
// sysctl KERN_PROC_ALL, the enumeration path the product already uses. Identity
// is (pid, start time) because pids recycle; the start time is carried so an
// event can be matched to the process that was registered, not its successor.

struct ProcRow {
    let pid: pid_t
    let comm: String
    let uid: uid_t
    let ppid: pid_t
    let startTime: timeval
    /// SIDL/SRUN/SSLEEP/SSTOP/SZOMB. A zombie is the one state in which the
    /// kernel is still holding an exit status.
    let stat: Int8
    /// extern_proc.p_xstat — the exit status the parent has not collected yet.
    let xstat: UInt16
}

func processTable() -> [ProcRow] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard buf.withUnsafeMutableBytes({ sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }) == 0
    else { return [] }
    let count = size / MemoryLayout<kinfo_proc>.stride
    return buf.withUnsafeBytes { raw in
        let procs = raw.bindMemory(to: kinfo_proc.self)
        return (0..<Swift.min(count, procs.count)).compactMap { i -> ProcRow? in
            var kp = procs[i]
            let pid = kp.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let comm = withUnsafeBytes(of: &kp.kp_proc.p_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            return ProcRow(pid: pid, comm: comm, uid: kp.kp_eproc.e_ucred.cr_uid,
                           ppid: kp.kp_eproc.e_ppid, startTime: kp.kp_proc.p_un.__p_starttime,
                           stat: kp.kp_proc.p_stat, xstat: kp.kp_proc.p_xstat)
        }
    }
}

// MARK: - kqueue registration

let kqFull = kqueue()   // NOTE_EXIT | NOTE_EXITSTATUS | NOTE_EXIT_DETAIL | NOTE_SIGNAL
let kqBare = kqueue()   // NOTE_EXIT only — the control, in case asking for status
                        // is what makes the attach fail rather than the exit.

let fullMask = fNOTE_EXIT | fNOTE_EXITSTATUS | fNOTE_EXIT_DETAIL | fNOTE_SIGNAL

@discardableResult
func register(_ kq: Int32, pid: pid_t, fflags: UInt32) -> Int32 {
    var kev = Darwin.kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC),
                            flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR),
                            fflags: fflags, data: 0, udata: nil)
    let r = kevent(kq, &kev, 1, nil, 0, nil)
    return r == -1 ? errno : 0
}

// MARK: - Environment

let env = ProcessInfo.processInfo.environment
let sandboxed = NSHomeDirectory().contains("/Containers/")
let watchSeconds = Double(env["EXITPROBE_WATCH"] ?? "") ?? 45
let outPath = env["EXITPROBE_OUT"] ?? (NSHomeDirectory() + "/exit-status-result.txt")

// NSWorkspace's notification centre delivers nothing to a process that has not
// stood up an NSApplication: measured, an unbundled tool observing
// didLaunchApplicationNotification sees zero launches. The shipping app is a
// bundled LSUIElement NSApplication, so the probe becomes one before observing,
// and the sandboxed (bundled) pass is the run that answers the NSWorkspace
// question. .accessory keeps it off the Dock and off the screen.
let nsapp = NSApplication.shared
nsapp.setActivationPolicy(.accessory)
nsapp.finishLaunching()

emit("=== FR-046 exit-status probe ===")
emit("sandboxed        : \(sandboxed)  (home: \(NSHomeDirectory()))")
emit("uid              : \(getuid())   pid: \(getpid())")
emit("watch window     : \(watchSeconds) s")
emit("macOS            : \(ProcessInfo.processInfo.operatingSystemVersionString)")
emit()

// MARK: - Phase A: control children (processes we DID fork)
//
// Without this, a total failure is indistinguishable from a parentage
// restriction. If even our own children yield no status, the API is simply
// unavailable to us; if they do and strangers do not, the limit is parentage.

func spawnChild(_ args: [String]) -> pid_t {
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    argv.append(nil)
    defer { for p in argv where p != nil { free(p) } }
    let rc = posix_spawn(&pid, args[0], nil, nil, argv, environ)
    if rc != 0 {
        emit("  posix_spawn(\(args.joined(separator: " "))) failed: \(errnoName(rc))")
        return -1
    }
    return pid
}

struct Child {
    let pid: pid_t
    let label: String
    let expected: String
}

emit("--- Phase A: control children (we are the parent) ---")
var children: [Child] = []
let cSegv = spawnChild(["/bin/sleep", "40"])
let cExit = spawnChild(["/bin/sh", "-c", "sleep 5; exit 7"])
let cTerm = spawnChild(["/bin/sleep", "40"])
if cSegv > 0 { children.append(Child(pid: cSegv, label: "child-SEGV", expected: "SIGSEGV (crash)")) }
if cExit > 0 { children.append(Child(pid: cExit, label: "child-exit7", expected: "exit code 7 (normal)")) }
if cTerm > 0 { children.append(Child(pid: cTerm, label: "child-TERM", expected: "SIGTERM (not a crash)")) }
for c in children { emit("  spawned pid \(c.pid)  \(c.label)  expecting \(c.expected)") }
if children.isEmpty { emit("  NO CHILDREN SPAWNED — posix_spawn denied; control unavailable") }
emit()

// MARK: - Phase B: register every process in the table

emit("--- Phase B: EVFILT_PROC registration over the whole process table ---")
let table = processTable()
let myUID = getuid()
let myPID = getpid()
emit("sysctl KERN_PROC_ALL returned \(table.count) processes")

var info: [pid_t: ProcRow] = [:]
for r in table { info[r.pid] = r }
for c in children where info[c.pid] == nil {
    info[c.pid] = ProcRow(pid: c.pid, comm: c.label, uid: myUID, ppid: myPID,
                          startTime: timeval(), stat: 0, xstat: 0)
}

var okFullOwn = 0, okFullOther = 0
var failFullOwn: [Int32: Int] = [:], failFullOther: [Int32: Int] = [:]
var okBareOwn = 0, okBareOther = 0
var failBareOwn: [Int32: Int] = [:], failBareOther: [Int32: Int] = [:]
var registeredFull: Set<pid_t> = []
var fullMaskRefusers: [String] = []

// Cost: this is what the product would pay to start watching, and again for
// every newly-appeared pid on every sweep. LifecycleTracker currently pays zero.
let regStart = Date()
for r in table where r.pid != myPID {
    let own = r.uid == myUID
    let e = register(kqFull, pid: r.pid, fflags: fullMask)
    if e == 0 {
        registeredFull.insert(r.pid)
        if own { okFullOwn += 1 } else { okFullOther += 1 }
    } else if own {
        failFullOwn[e, default: 0] += 1
        if fullMaskRefusers.count < 20 { fullMaskRefusers.append("\(r.comm)(\(r.pid), \(errnoName(e)))") }
    } else {
        failFullOther[e, default: 0] += 1
    }
}
let regElapsed = Date().timeIntervalSince(regStart)

let bareStart = Date()
for r in table where r.pid != myPID {
    let own = r.uid == myUID
    let e = register(kqBare, pid: r.pid, fflags: fNOTE_EXIT)
    if e == 0 {
        if own { okBareOwn += 1 } else { okBareOther += 1 }
    } else if own {
        failBareOwn[e, default: 0] += 1
    } else {
        failBareOther[e, default: 0] += 1
    }
}
let bareElapsed = Date().timeIntervalSince(bareStart)

for c in children {
    let e = register(kqFull, pid: c.pid, fflags: fullMask)
    let e2 = register(kqBare, pid: c.pid, fflags: fNOTE_EXIT)
    if e == 0 { registeredFull.insert(c.pid) }
    emit("  child \(c.pid) \(c.label): full mask \(errnoName(e)), bare NOTE_EXIT \(errnoName(e2))")
}

let ownTotal = table.filter { $0.uid == myUID && $0.pid != myPID }.count
let otherTotal = table.filter { $0.uid != myUID }.count
func fails(_ d: [Int32: Int]) -> String {
    d.isEmpty ? "-" : d.map { "\(errnoName($0.key))×\($0.value)" }.sorted().joined(separator: " ")
}
emit(String(format: "full mask (EXIT|EXITSTATUS|EXIT_DETAIL|SIGNAL): own-uid %d/%d attached, other-uid %d/%d",
            okFullOwn, ownTotal, okFullOther, otherTotal))
emit("  own-uid failures  : \(fails(failFullOwn))")
if !fullMaskRefusers.isEmpty { emit("    refused: \(fullMaskRefusers.joined(separator: ", "))") }
emit("  other-uid failures: \(fails(failFullOther))")
emit(String(format: "bare NOTE_EXIT only : own-uid %d/%d attached, other-uid %d/%d",
            okBareOwn, ownTotal, okBareOther, otherTotal))
emit("  own-uid failures  : \(fails(failBareOwn))")
emit("  other-uid failures: \(fails(failBareOther))")
emit(String(format: "registration cost   : %.1f ms for %d pids (full), %.1f ms (bare) = %.3f ms/pid",
            regElapsed * 1000, table.count - 1, bareElapsed * 1000,
            regElapsed * 1000 / Double(Swift.max(1, table.count - 1))))
emit()

// MARK: - Phase C: watch

emit("--- Phase C: watching for \(watchSeconds) s ---")
emit("(events from the full-mask kqueue; a second kqueue holds bare NOTE_EXIT for comparison)")

struct Observed {
    let time: String
    let pid: pid_t
    let comm: String
    let uid: uid_t
    let ppid: pid_t
    let mine: Bool
    let fflags: UInt32
    let data: Int
}

var exits: [Observed] = []
var signals: [Observed] = []
var bareExitPIDs: Set<pid_t> = []
var withStatus = 0
var withoutStatus = 0

let childPIDs = Set(children.map { $0.pid })
var killedSegv = false, killedTerm = false
var zombieReport: [String] = []
var reaped: Set<pid_t> = []

// The second candidate route, and the cheap one: the process table the product
// already samples carries p_stat and p_xstat, so a process caught while it is
// still an unreaped zombie exposes its exit status with no new API at all. The
// question is entirely one of timing — whether anything but our own children is
// ever still a zombie when we look.
var zombieSightings: [String] = []
var zombieSeenPIDs: Set<pid_t> = []
var raceChecks: [String] = []
var censusRounds = 0
var lastCensus = Date.distantPast

// NSWorkspace: the .app-level route. Registered here so it observes the same
// window, including the victim .app the harness crashes.
var workspaceEvents: [String] = []
var workspaceLaunches = 0
let wsLock = NSLock()
let wsCenter = NSWorkspace.shared.notificationCenter
// The control for this phase. A run that sees no launches either is a run whose
// notification plumbing is not working, and its zero terminations mean nothing.
let obsLaunch = wsCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                     object: nil, queue: nil) { _ in
    wsLock.lock(); workspaceLaunches += 1; wsLock.unlock()
}
let obs = wsCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                               object: nil, queue: nil) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    var line = "\(stamp()) didTerminateApplication: keys=\(Array(note.userInfo?.keys.map { "\($0)" } ?? []).sorted())"
    if let app {
        line += "\n    bundleID=\(app.bundleIdentifier ?? "nil") pid=\(app.processIdentifier)"
            + " name=\(app.localizedName ?? "nil") terminated=\(app.isTerminated)"
            + " active=\(app.isActive) policy=\(app.activationPolicy.rawValue)"
    }
    wsLock.lock(); workspaceEvents.append(line); wsLock.unlock()
}

func drain(_ kq: Int32, timeoutMS: Int, handler: (Darwin.kevent) -> Void) {
    var ev = [Darwin.kevent](repeating: Darwin.kevent(), count: 64)
    var ts = timespec(tv_sec: timeoutMS / 1000, tv_nsec: (timeoutMS % 1000) * 1_000_000)
    let n = kevent(kq, nil, 0, &ev, 64, &ts)
    guard n > 0 else { return }
    for i in 0..<Int(n) { handler(ev[i]) }
}

func watchAndReport() {
let deadline = Date().addingTimeInterval(watchSeconds)
while Date() < deadline {
    let now = Date().timeIntervalSince(started)

    // Signal our OWN children only, to manufacture a known crash and a known
    // ordinary termination. Nothing else on this machine is touched.
    if !killedSegv, now >= 3, cSegv > 0 {
        killedSegv = true
        kill(cSegv, SIGSEGV)
        emit("\(stamp()) sent SIGSEGV to our child \(cSegv)")
    }
    if !killedTerm, now >= 7, cTerm > 0 {
        killedTerm = true
        kill(cTerm, SIGTERM)
        emit("\(stamp()) sent SIGTERM to our child \(cTerm)")
    }

    drain(kqFull, timeoutMS: 150) { ev in
        let pid = pid_t(ev.ident)
        let row = info[pid]
        let o = Observed(time: stamp(), pid: pid, comm: row?.comm ?? "?",
                         uid: row?.uid ?? 0, ppid: row?.ppid ?? 0,
                         mine: childPIDs.contains(pid), fflags: ev.fflags, data: ev.data)
        if ev.fflags & fNOTE_EXIT != 0 {
            exits.append(o)
            if ev.fflags & fNOTE_EXITSTATUS != 0 { withStatus += 1 } else { withoutStatus += 1 }
        }
        if ev.fflags & fNOTE_SIGNAL != 0 { signals.append(o) }

        // Race check: the instant we learn of an exit, is the pid still visible
        // in sysctl as a zombie carrying its status? This is the upper bound on
        // what the existing enumeration path could ever recover.
        if ev.fflags & fNOTE_EXIT != 0, !childPIDs.contains(pid), raceChecks.count < 25 {
            if let z = processTable().first(where: { $0.pid == pid }) {
                raceChecks.append("pid \(pid) \(o.comm): still listed, p_stat=\(z.stat)"
                    + (z.stat == 5 ? ", SZOMB, p_xstat=\(z.xstat) -> \(decodeWaitStatus(Int(z.xstat)))"
                                   : ", not a zombie"))
            } else {
                raceChecks.append("pid \(pid) \(o.comm): already gone from sysctl at the moment of NOTE_EXIT")
            }
        }
    }
    drain(kqBare, timeoutMS: 0) { ev in
        if ev.fflags & fNOTE_EXIT != 0 { bareExitPIDs.insert(pid_t(ev.ident)) }
    }

    // Phase D, part 1: does anything survive the exit? Ask about our own child
    // while it is still an unreaped zombie, which is the most favourable case
    // that can exist.
    if killedSegv, cSegv > 0, !reaped.contains(cSegv), zombieReport.isEmpty,
       exits.contains(where: { $0.pid == cSegv }) {
        var sb = proc_bsdshortinfo()
        let n = proc_pidinfo(cSegv, PROC_PIDT_SHORTBSDINFO, 0, &sb,
                             Int32(MemoryLayout<proc_bsdshortinfo>.size))
        if n == Int32(MemoryLayout<proc_bsdshortinfo>.size) {
            let comm = withUnsafeBytes(of: &sb.pbsi_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            zombieReport.append("zombie \(cSegv): SHORTBSDINFO ok, comm=\(comm) "
                + String(format: "status=%u flags=0x%x ppid=%u", sb.pbsi_status, sb.pbsi_flags, sb.pbsi_ppid))
        } else {
            zombieReport.append("zombie \(cSegv): SHORTBSDINFO returned \(n), \(errnoName(errno))")
        }
        // And the sysctl row for the same zombie, since that is the path the
        // product already uses. extern_proc.p_xstat is where an uncollected exit
        // status lives, so if enumeration alone could answer FR-046 it would be here.
        if let z = processTable().first(where: { $0.pid == cSegv }) {
            zombieReport.append("zombie \(cSegv): still in sysctl KERN_PROC_ALL, "
                + "p_stat=\(z.stat) (SZOMB=5), p_xstat=\(z.xstat) -> \(decodeWaitStatus(Int(z.xstat)))")
        } else {
            zombieReport.append("zombie \(cSegv): NOT in sysctl KERN_PROC_ALL")
        }
    }

    // Reap late, so the zombie window above is real.
    if now >= 15 {
        for c in children where !reaped.contains(c.pid) {
            var st: Int32 = 0
            let r = waitpid(c.pid, &st, WNOHANG)
            if r == c.pid {
                reaped.insert(c.pid)
                emit("\(stamp()) waitpid ground truth for \(c.pid) \(c.label): raw \(st) -> \(decodeWaitStatus(Int(st)))")
                if zombieReport.count < 4, c.pid == cSegv {
                    var sb = proc_bsdshortinfo()
                    let n = proc_pidinfo(c.pid, PROC_PIDT_SHORTBSDINFO, 0, &sb,
                                         Int32(MemoryLayout<proc_bsdshortinfo>.size))
                    zombieReport.append("after reap \(c.pid): SHORTBSDINFO returned \(n), \(errnoName(errno))")
                }
            }
        }
    }

    // Zombie census, 4 Hz — far faster than the product's 2-5 s cadence, so this
    // is a generous upper bound on what enumeration alone could catch.
    if Date().timeIntervalSince(lastCensus) >= 0.25 {
        lastCensus = Date()
        censusRounds += 1
        for z in processTable() where z.stat == 5 && !zombieSeenPIDs.contains(z.pid) {
            zombieSeenPIDs.insert(z.pid)
            zombieSightings.append("\(stamp()) pid \(z.pid) \(z.comm) ppid=\(z.ppid) uid=\(z.uid)"
                + " \(childPIDs.contains(z.pid) ? "[OUR CHILD]" : "[stranger]")"
                + " p_xstat=\(z.xstat) -> \(decodeWaitStatus(Int(z.xstat)))")
        }
    }

    usleep(50_000)
}

wsCenter.removeObserver(obs)
wsCenter.removeObserver(obsLaunch)

// MARK: - Results

emit()
emit("--- Phase C results: exits observed ---")
emit("NOTE_EXIT events (full-mask kqueue): \(exits.count)")
emit("  of which carried NOTE_EXITSTATUS : \(withStatus)")
emit("  of which did NOT                 : \(withoutStatus)")
let bareOwn = bareExitPIDs.filter { (info[$0]?.uid ?? myUID) == myUID }.count
emit("NOTE_EXIT events (bare kqueue)      : \(bareExitPIDs.count) distinct pids"
    + " (own-uid \(bareOwn), other-uid \(bareExitPIDs.count - bareOwn))")
emit("NOTE_SIGNAL events                  : \(signals.count)")
emit()

let ourExits = exits.filter { $0.mine }
let foreignExits = exits.filter { !$0.mine }
emit("children we forked that exited      : \(ourExits.count)/\(children.count)")
emit("  with usable status                : \(ourExits.filter { $0.fflags & fNOTE_EXITSTATUS != 0 }.count)")
emit("strangers (we did not fork) exited  : \(foreignExits.count)")
emit("  with usable status                : \(foreignExits.filter { $0.fflags & fNOTE_EXITSTATUS != 0 }.count)")
emit("  own-uid strangers                 : \(foreignExits.filter { $0.uid == myUID }.count)")
emit("  other-uid strangers               : \(foreignExits.filter { $0.uid != myUID }.count)")
emit()

emit("--- every exit event, decoded ---")
for o in exits.prefix(80) {
    emit("\(o.time) pid \(o.pid) \(o.comm) uid=\(o.uid) ppid=\(o.ppid)"
        + " \(o.mine ? "[OUR CHILD]" : "[stranger]")")
    emit("    fflags=\(flagNames(o.fflags))  data=\(o.data)")
    if o.fflags & fNOTE_EXITSTATUS != 0 {
        emit("    status: \(decodeWaitStatus(o.data))")
    } else {
        emit("    status: NOT DELIVERED — data is \(o.data), which is not a wait status we may trust")
    }
}
if exits.count > 80 { emit("... \(exits.count - 80) more") }
emit()

if !signals.isEmpty {
    emit("--- NOTE_SIGNAL events (first 40) ---")
    for o in signals.prefix(40) {
        emit("\(o.time) pid \(o.pid) \(o.comm) \(o.mine ? "[OUR CHILD]" : "[stranger]")"
            + " data=\(o.data) fflags=\(String(format: "0x%08x", o.fflags)) \(flagNames(o.fflags))")
    }
    emit()
}

emit("--- Phase E: sysctl KERN_PROC_ALL zombies (the route that costs nothing new) ---")
emit("census rounds at 4 Hz: \(censusRounds)")
emit("distinct zombies seen: \(zombieSeenPIDs.count) "
    + "(ours: \(zombieSeenPIDs.filter { childPIDs.contains($0) }.count), "
    + "strangers: \(zombieSeenPIDs.filter { !childPIDs.contains($0) }.count))")
zombieSightings.prefix(40).forEach { emit("  " + $0) }
emit()
emit("at the moment of each stranger's NOTE_EXIT, was it still a zombie in sysctl?")
if raceChecks.isEmpty { emit("  (no stranger exits observed)") }
raceChecks.forEach { emit("  " + $0) }
emit()

emit("--- Phase D: proc_pidinfo PROC_PIDT_SHORTBSDINFO across the exit ---")
if zombieReport.isEmpty {
    emit("(not exercised — no child exit was observed)")
} else {
    zombieReport.forEach { emit("  " + $0) }
}
var deadProbe = proc_bsdshortinfo()
let deadPID: pid_t = 99998  // a pid essentially certain not to be live right now
let dn = proc_pidinfo(deadPID, PROC_PIDT_SHORTBSDINFO, 0, &deadProbe,
                      Int32(MemoryLayout<proc_bsdshortinfo>.size))
emit("  never-existed pid \(deadPID): returned \(dn), \(errnoName(errno))")
emit()

emit("--- Phase D: NSWorkspace / NSRunningApplication ---")
wsLock.lock()
let wsEvents = workspaceEvents
let wsLaunches = workspaceLaunches
wsLock.unlock()
emit("didLaunchApplication notifications (plumbing control): \(wsLaunches)")
emit("didTerminateApplication notifications in window: \(wsEvents.count)")
wsEvents.forEach { emit("  " + $0) }
if wsLaunches == 0 {
    emit("PLUMBING CONTROL FAILED: a victim .app was launched inside this window and no")
    emit("didLaunchApplication arrived either, so zero terminations proves nothing about")
    emit("delivery. Measured separately: an unbundled tool sees no NSWorkspace")
    emit("notifications at all, and this bundled run sees none for an LSUIElement app.")
    emit("Treat notification delivery as NOT ESTABLISHED. The API-surface argument below")
    emit("stands on its own regardless.")
}
emit("The notification's userInfo carries an NSRunningApplication and nothing else, so")
emit("its whole property surface is the ceiling on what it could ever tell us:")
var count: UInt32 = 0
if let props = class_copyPropertyList(NSRunningApplication.self, &count) {
    var names: [String] = []
    for i in 0..<Int(count) { names.append(String(cString: property_getName(props[i]))) }
    free(props)
    emit("NSRunningApplication properties (\(names.count)): \(names.sorted().joined(separator: ", "))")
}
emit()

emit("=== written \(Date()) ===")
try? log.write(toFile: outPath, atomically: true, encoding: .utf8)
print("result written to \(outPath)")
exit(0)
}

let watcher = Thread { watchAndReport() }
watcher.stackSize = 4 << 20
watcher.start()
nsapp.run()
