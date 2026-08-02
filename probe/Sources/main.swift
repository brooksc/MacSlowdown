// MacSlowdown Tier 0 sandbox feasibility probe.
//
// Answers one question: under App Sandbox, can we enumerate processes and read
// per-process CPU and memory? That underpins FR-002, FR-003, FR-006 and FR-043.
// If it fails, the product concept needs revisiting before any code is written.
//
// The same binary runs sandboxed and unsandboxed; the diff is the finding.
// Disk I/O and wakeup counters come free from the same rusage call, so they are
// collected too (FR-009, FR-048).

import Darwin
import Foundation

// MARK: - Time units
//
// CRITICAL: proc_taskinfo.pti_total_{user,system} and rusage_info.ri_{user,system}_time
// are in MACH ABSOLUTE TIME UNITS, not nanoseconds. On Apple Silicon the timebase is
// 125/3 (41.667 ns per tick), so treating them as nanoseconds under-reports CPU by ~42x.
// On Intel the timebase is 1:1, which is why much published sample code omits this.
// Verified against `ps %cpu` with a synthetic single-core spinner: 99.2% vs 100.0%.

let machTimebase: Double = {
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    return Double(tb.numer) / Double(tb.denom)
}()

func machTicksToNanos(_ ticks: UInt64) -> Double {
    Double(ticks) * machTimebase
}

extension Duration {
    /// `components.attoseconds` holds only the sub-second remainder; the whole
    /// seconds live in `components.seconds`. Using attoseconds alone silently
    /// truncates any duration of one second or more.
    var totalSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

// MARK: - libproc constants (#defines, not imported into Swift)

let PROC_ALL_PIDS: UInt32 = 1
let PROC_PIDTBSDINFO: Int32 = 3
let PROC_PIDTASKINFO: Int32 = 4

// MARK: - Outcome tracking

/// Per-API tally so a failure can be reported as "denied" vs "process gone"
/// rather than a single opaque success rate.
struct APIResult {
    var attempted = 0
    var succeeded = 0
    var errnoCounts: [Int32: Int] = [:]

    mutating func record(success: Bool, err: Int32 = 0) {
        attempted += 1
        if success {
            succeeded += 1
        } else {
            errnoCounts[err, default: 0] += 1
        }
    }

    var summary: String {
        let pct = attempted == 0 ? 0 : Double(succeeded) / Double(attempted) * 100
        let errs = errnoCounts
            .sorted { $0.value > $1.value }
            .map { "\(errnoName($0.key))×\($0.value)" }
            .joined(separator: " ")
        return String(format: "%4d/%4d (%5.1f%%)", succeeded, attempted, pct)
            + (errs.isEmpty ? "" : "  errors: \(errs)")
    }
}

func errnoName(_ e: Int32) -> String {
    switch e {
    case EPERM: return "EPERM(denied)"
    case ESRCH: return "ESRCH(gone)"
    case EINVAL: return "EINVAL"
    case ENOMEM: return "ENOMEM"
    case 0: return "none(short-read)"
    default: return "errno\(e)"
    }
}

// MARK: - Per-process sample

struct ProcSample {
    var pid: Int32
    var startTime: UInt64 = 0      // with pid, forms a stable identity (PIDs get reused)
    var ppid: Int32 = 0
    var uid: UInt32 = 0
    var name = ""
    var path = ""

    var cpuTicks: UInt64 = 0       // user + system, in mach ticks (see machTicksToNanos)
    var residentBytes: UInt64 = 0
    var footprintBytes: UInt64 = 0 // phys_footprint — what Activity Monitor shows
    var diskReadBytes: UInt64 = 0
    var diskWriteBytes: UInt64 = 0
    var interruptWakeups: UInt64 = 0

    var haveTaskInfo = false
    var haveRusage = false
}

// MARK: - Collection

func fixedCString<T>(_ tuple: T) -> String {
    var copy = tuple
    return withUnsafeBytes(of: &copy) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// proc_listpids is DENIED under App Sandbox (`process-info-listpids`, EPERM,
/// no entitlement remedy per Apple DTS). Retained only to report the contrast.
func listPIDsViaLibproc() -> (pids: [Int32], err: Int32) {
    errno = 0
    let byteCount = proc_listpids(PROC_ALL_PIDS, 0, nil, 0)
    guard byteCount > 0 else { return ([], errno) }
    let capacity = Int(byteCount) / MemoryLayout<pid_t>.size + 64
    var pids = [pid_t](repeating: 0, count: capacity)
    let written = pids.withUnsafeMutableBytes {
        proc_listpids(PROC_ALL_PIDS, 0, $0.baseAddress, Int32($0.count))
    }
    guard written > 0 else { return ([], errno) }
    return (Array(pids.prefix(Int(written) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }, 0)
}

/// sysctl KERN_PROC_ALL is a separately-gated sandbox operation and DOES work
/// sandboxed, returning the full process table including processes whose
/// per-process metrics are later denied. This is the enumeration path.
func listAllPIDs() -> [(pid: Int32, comm: String, uid: UInt32)] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard buf.withUnsafeMutableBytes({ sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }) == 0
    else { return [] }
    let count = size / MemoryLayout<kinfo_proc>.stride
    return buf.withUnsafeBytes { raw in
        let procs = raw.bindMemory(to: kinfo_proc.self)
        return (0..<min(count, procs.count)).compactMap { i in
            var kp = procs[i]
            let pid = kp.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let comm = withUnsafeBytes(of: &kp.kp_proc.p_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            return (pid, comm, kp.kp_eproc.e_ucred.cr_uid)
        }
    }
}

struct Sweep {
    var samples: [Int32: ProcSample] = [:]
    var wallClock: TimeInterval = 0
    var elapsed: Duration = .zero

    var bsdInfo = APIResult()
    var taskInfo = APIResult()
    var rusage = APIResult()
    var pidPath = APIResult()
}

func collectSweep() -> Sweep {
    var sweep = Sweep()
    let clock = ContinuousClock()

    sweep.elapsed = clock.measure {
        sweep.wallClock = Date().timeIntervalSince1970
        for (pid, comm, uid) in listAllPIDs() {
            var s = ProcSample(pid: pid)
            s.name = comm      // from kinfo_proc; survives when proc_pidinfo is denied
            s.uid = uid

            // Identity: name, start time, uid, parent.
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let bsdRC = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize)
            if bsdRC == bsdSize {
                s.startTime = UInt64(bsd.pbi_start_tvsec)
                s.ppid = Int32(bsd.pbi_ppid)
                s.uid = bsd.pbi_uid
                s.name = fixedCString(bsd.pbi_name)
                if s.name.isEmpty { s.name = fixedCString(bsd.pbi_comm) }
                sweep.bsdInfo.record(success: true)
            } else {
                sweep.bsdInfo.record(success: false, err: errno)
            }

            // CPU time + resident memory.
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let taskRC = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize)
            if taskRC == taskSize {
                s.cpuTicks = task.pti_total_user + task.pti_total_system
                s.residentBytes = task.pti_resident_size
                s.haveTaskInfo = true
                sweep.taskInfo.record(success: true)
            } else {
                sweep.taskInfo.record(success: false, err: errno)
            }

            // phys_footprint, disk I/O, wakeups.
            //
            // NOTE: despite the `rusage_info_t *buffer` signature (rusage_info_t
            // is itself void*), the kernel writes to `buffer`, not `*buffer`.
            // The struct address must be rebound to the parameter type. Passing
            // the address of a pointer variable instead smashes the stack.
            var ri = rusage_info_v6()
            let riRC = withUnsafeMutablePointer(to: &ri) { riPtr in
                riPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            if riRC == 0 {
                s.footprintBytes = ri.ri_phys_footprint
                s.diskReadBytes = ri.ri_diskio_bytesread
                s.diskWriteBytes = ri.ri_diskio_byteswritten
                s.interruptWakeups = ri.ri_interrupt_wkups
                s.haveRusage = true
                sweep.rusage.record(success: true)
            } else {
                sweep.rusage.record(success: false, err: errno)
            }

            // Executable path — needed for application-family grouping (FR-003).
            var pathBuf = [CChar](repeating: 0, count: 4096)
            let pathRC = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            if pathRC > 0 {
                s.path = String(cString: pathBuf)
                sweep.pidPath.record(success: true)
            } else {
                sweep.pidPath.record(success: false, err: errno)
            }

            sweep.samples[pid] = s
        }
    }
    return sweep
}

// MARK: - Aggregate cross-check (host-level, expected to work sandboxed)

func aggregateCPUTicks() -> (used: UInt64, total: UInt64)? {
    var cpuCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                              &cpuCount, &info, &infoCount) == KERN_SUCCESS,
          let info else { return nil }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
    }
    var used: UInt64 = 0, total: UInt64 = 0
    for cpu in 0..<Int(cpuCount) {
        let base = cpu * Int(CPU_STATE_MAX)
        let user = UInt64(info[base + Int(CPU_STATE_USER)])
        let sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
        let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
        let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
        used += user + sys + nice
        total += user + sys + nice + idle
    }
    return (used, total)
}

func logicalCoreCount() -> Int {
    var count = 0
    var size = MemoryLayout<Int>.size
    sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
    return max(count, 1)
}

// MARK: - Report

setvbuf(stdout, nil, _IONBF, 0)

let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    || FileManager.default.fileExists(
        atPath: NSHomeDirectory() + "/.com.apple.containermanagerd.metadata.plist")

let cores = logicalCoreCount()
let interval: TimeInterval = 2.0

print("=== MacSlowdown Tier 0 probe ===")
print("sandboxed (heuristic): \(isSandboxed)")
print("home: \(NSHomeDirectory())")
print("euid: \(geteuid())  cores: \(cores)")
print("")

let agg1 = aggregateCPUTicks()
let s1 = collectSweep()
Thread.sleep(forTimeInterval: interval)
let agg2 = aggregateCPUTicks()
let s2 = collectSweep()

let wallDelta = s2.wallClock - s1.wallClock

let libprocResult = listPIDsViaLibproc()
print("--- API availability (sweep 2) ---")
print("sysctl KERN_PROC_ALL: \(s2.samples.count) pids returned")
print("proc_listpids       : \(libprocResult.pids.count) pids"
    + (libprocResult.pids.isEmpty ? "  [DENIED: \(errnoName(libprocResult.err))]" : ""))
print("PROC_PIDTBSDINFO   : \(s2.bsdInfo.summary)")
print("PROC_PIDTASKINFO   : \(s2.taskInfo.summary)")
print("proc_pid_rusage    : \(s2.rusage.summary)")
print("proc_pidpath       : \(s2.pidPath.summary)")
print("")

print("--- Sweep cost (FR-030 budget: <=1% of one core) ---")
let ms1 = s1.elapsed.totalSeconds * 1000
let ms2 = s2.elapsed.totalSeconds * 1000
print(String(format: "sweep 1: %.1f ms", ms1))
print(String(format: "sweep 2: %.1f ms", ms2))
for cadence in [1.0, 2.0, 5.0] {
    let dutyPct = (ms2 / 1000.0) / cadence * 100
    let verdict = dutyPct <= 1.0 ? "OK" : "OVER BUDGET"
    print(String(format: "  at %.0fs cadence: %.2f%% of one core  [%@]",
                 cadence, dutyPct, verdict))
}
print("")

if let a1 = agg1, let a2 = agg2 {
    let usedDelta = Double(a2.used &- a1.used)
    let totalDelta = Double(a2.total &- a1.total)
    let pct = totalDelta > 0 ? usedDelta / totalDelta * 100 : 0
    print(String(format: "--- Aggregate CPU (host_processor_info): %.1f%% busy ---", pct))
} else {
    print("--- Aggregate CPU: UNAVAILABLE ---")
}
print("")

// Per-process CPU from the delta of two samples. A cumulative counter is never
// a rate (FR-006, FR-009); PID+start-time guards against reuse across sweeps.
struct Ranked {
    var name: String
    var pid: Int32
    var cpuPercentOfCore: Double
    var footprintMB: Double
    var residentMB: Double
    var readMB: Double
    var writeMB: Double
}

var ranked: [Ranked] = []
for (pid, new) in s2.samples {
    guard let old = s1.samples[pid], old.startTime == new.startTime else { continue }
    guard new.haveTaskInfo || new.haveRusage else { continue }
    let cpuDelta = new.cpuTicks >= old.cpuTicks ? new.cpuTicks - old.cpuTicks : 0
    ranked.append(Ranked(
        name: new.name.isEmpty ? "(pid \(pid))" : new.name,
        pid: pid,
        cpuPercentOfCore: machTicksToNanos(cpuDelta) / (wallDelta * 1e9) * 100,
        footprintMB: Double(new.footprintBytes) / 1_048_576,
        residentMB: Double(new.residentBytes) / 1_048_576,
        readMB: Double(new.diskReadBytes &- old.diskReadBytes) / 1_048_576,
        writeMB: Double(new.diskWriteBytes &- old.diskWriteBytes) / 1_048_576))
}

print("--- Top 15 by CPU (%% of ONE core; /\(cores) for machine-relative, FR-004) ---")
print("PROCESS".padding(toLength: 28, withPad: " ", startingAt: 0)
    + "    CPU%   FOOT_MB    RSS_MB     RD_MB     WR_MB")
func pad(_ s: String, _ n: Int) -> String {
    let t = s.count > n ? String(s.prefix(n - 1)) + "~" : s
    return t.padding(toLength: n, withPad: " ", startingAt: 0)
}
for r in ranked.sorted(by: { $0.cpuPercentOfCore > $1.cpuPercentOfCore }).prefix(15) {
    print(pad("\(r.name) [\(r.pid)]", 28)
        + String(format: "%8.1f %9.1f %9.1f %9.2f %9.2f",
                 r.cpuPercentOfCore, r.footprintMB, r.residentMB, r.readMB, r.writeMB))
}
print("")

print("--- Top 10 by memory footprint ---")
for r in ranked.sorted(by: { $0.footprintMB > $1.footprintMB }).prefix(10) {
    print(pad("\(r.name) [\(r.pid)]", 28) + String(format: "%9.1f MB", r.footprintMB))
}
print("")

let visible = ranked.count
let totalPIDs = s2.samples.count
print("--- Verdict inputs ---")
print("pids enumerated        : \(totalPIDs)")
print("pids with usable metrics: \(visible)")
print("own-uid pids           : \(s2.samples.values.filter { $0.uid == geteuid() }.count)")
print("other-uid pids         : \(s2.samples.values.filter { $0.uid != geteuid() }.count)")
