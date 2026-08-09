import Darwin
import Foundation
import Network

// Is per-application network attribution (FR-051) reachable from a sandboxed,
// Mac App Store build using public APIs only?
//
// The backlog's standing suspicion is that it needs the private
// NetworkStatistics framework. This probe does not confirm that by assertion:
// it walks every public route that could plausibly carry per-process bytes and
// reports what each one yields, with counts, sandboxed and unsandboxed.
//
// No private framework is linked or dlopened. `nettop` is only *executed* (it
// is a system binary), to establish whether the sandbox even permits that
// route — the answer is evidence, not a design proposal.
//
// A zero reading proves nothing, so the caller (`run-net-probe.sh`) drives a
// real loopback transfer across the sampling window. Every counter below is
// read twice and reported as a delta.

// MARK: - Output
//
// Launched via `open`, so stdout goes nowhere. Everything is written to a file
// inside whatever home directory we end up with — the container when sandboxed.

var log = ""
func emit(_ s: String = "") {
    log += s + "\n"
    print(s)
}

func errnoName(_ e: Int32) -> String {
    switch e {
    case EPERM: return "EPERM(denied)"
    case EACCES: return "EACCES(denied)"
    case ESRCH: return "ESRCH(gone)"
    case EBADF: return "EBADF"
    case EINVAL: return "EINVAL"
    case ENOENT: return "ENOENT"
    case 0: return "none"
    default: return "errno\(e)"
    }
}

let gapSeconds = Double(ProcessInfo.processInfo.environment["NETPROBE_GAP"] ?? "") ?? 6.0

// MARK: - Route 1: getifaddrs / if_data (aggregate, per interface)
//
// `struct if_data` is public (net/if_var.h). NOTE the counter width: ifi_ibytes
// and ifi_obytes are u_int32_t here, so they wrap every 4 GiB.

struct IfCounters {
    var ibytes: UInt64 = 0
    var obytes: UInt64 = 0
    var ipackets: UInt64 = 0
    var opackets: UInt64 = 0
}

func getifaddrsCounters() -> (counters: [String: IfCounters], linkEntries: Int, total: Int, err: Int32) {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    errno = 0
    guard getifaddrs(&ifap) == 0 else { return ([:], 0, 0, errno) }
    defer { freeifaddrs(ifap) }

    var out: [String: IfCounters] = [:]
    var linkEntries = 0
    var total = 0
    var cursor = ifap
    while let p = cursor {
        total += 1
        let ifa = p.pointee
        if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let raw = ifa.ifa_data {
            linkEntries += 1
            let d = raw.assumingMemoryBound(to: if_data.self).pointee
            let name = String(cString: ifa.ifa_name)
            out[name] = IfCounters(
                ibytes: UInt64(d.ifi_ibytes),
                obytes: UInt64(d.ifi_obytes),
                ipackets: UInt64(d.ifi_ipackets),
                opackets: UInt64(d.ifi_opackets))
        }
        cursor = ifa.ifa_next
    }
    return (out, linkEntries, total, 0)
}

// MARK: - Route 2: sysctl NET_RT_IFLIST2 / if_data64 (aggregate, 64-bit)
//
// Same figures as route 1 but with 64-bit counters, which is what `netstat -ib`
// reads. Both header structs (if_msghdr2, if_data64) are in the public SDK.

let RTM_IFINFO2_TYPE: UInt8 = 0x12

func iflist2Counters() -> (counters: [String: IfCounters], bytes: Int, messages: Int, err: Int32) {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var size = 0
    errno = 0
    guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return ([:], 0, 0, errno) }
    var buf = [UInt8](repeating: 0, count: size)
    errno = 0
    guard buf.withUnsafeMutableBytes({ sysctl(&mib, 6, $0.baseAddress, &size, nil, 0) }) == 0
    else { return ([:], 0, 0, errno) }

    var out: [String: IfCounters] = [:]
    var messages = 0
    buf.withUnsafeBytes { raw in
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= size {
            let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let msglen = Int(hdr.ifm_msglen)
            guard msglen > 0, offset + msglen <= size else { break }
            messages += 1
            if hdr.ifm_type == RTM_IFINFO2_TYPE,
               offset + MemoryLayout<if_msghdr2>.size <= size {
                let m = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var nameBuf = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
                let name = if_indextoname(UInt32(m.ifm_index), &nameBuf)
                    .map { String(cString: $0) } ?? "index \(m.ifm_index)"
                out[name] = IfCounters(
                    ibytes: m.ifm_data.ifi_ibytes,
                    obytes: m.ifm_data.ifi_obytes,
                    ipackets: m.ifm_data.ifi_ipackets,
                    opackets: m.ifm_data.ifi_opackets)
            }
            offset += msglen
        }
    }
    return (out, size, messages, 0)
}

// MARK: - Process table (the enumeration path this project already uses)

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

// MARK: - Route 3: libproc per-process socket descriptors
//
// PROC_PIDLISTFDS + PROC_PIDFDSOCKETINFO is the only public per-process view of
// networking. The question is not whether it works but what it *contains*:
// `struct socket_info` (sys/proc_info.h) carries sockbuf occupancy (sbi_cc),
// not cumulative bytes.

let PROC_PIDLISTFDS_OP: Int32 = 1
let PROC_PIDFDSOCKETINFO_OP: Int32 = 3
let FDTYPE_SOCKET: UInt32 = 2

struct SocketScan {
    var pidsAttempted = 0
    var pidsWithFDList = 0
    var pidsDenied = 0
    var pidsWithSocket = 0
    var socketsSeen = 0
    var socketInfoOK = 0
    var socketInfoFailed = 0
    var errnos: [Int32: Int] = [:]
    var ownUidWithFDList = 0
    var otherUidWithFDList = 0
    var ownUidTotal = 0
    var otherUidTotal = 0
    var perPID: [Int32: Int] = [:]
    var queuedBytes: [Int32: UInt64] = [:]   // sbi_cc rcv+snd — occupancy, NOT throughput
    var elapsedMS = 0.0
}

func scanSockets(_ procs: [(pid: Int32, comm: String, uid: UInt32)]) -> SocketScan {
    var scan = SocketScan()
    let me = geteuid()
    let start = Date()

    for (pid, _, uid) in procs {
        scan.pidsAttempted += 1
        if uid == me { scan.ownUidTotal += 1 } else { scan.otherUidTotal += 1 }

        errno = 0
        let need = proc_pidinfo(pid, PROC_PIDLISTFDS_OP, 0, nil, 0)
        guard need > 0 else {
            scan.pidsDenied += 1
            scan.errnos[errno, default: 0] += 1
            continue
        }
        let capacity = Int(need) / MemoryLayout<proc_fdinfo>.stride + 32
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        errno = 0
        let got = fds.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS_OP, 0, $0.baseAddress, Int32($0.count))
        }
        guard got > 0 else {
            scan.pidsDenied += 1
            scan.errnos[errno, default: 0] += 1
            continue
        }
        scan.pidsWithFDList += 1
        if uid == me { scan.ownUidWithFDList += 1 } else { scan.otherUidWithFDList += 1 }

        var socketsHere = 0
        var queued: UInt64 = 0
        for i in 0..<(Int(got) / MemoryLayout<proc_fdinfo>.stride) {
            guard fds[i].proc_fdtype == FDTYPE_SOCKET else { continue }
            socketsHere += 1
            scan.socketsSeen += 1
            var si = socket_fdinfo()
            let sz = Int32(MemoryLayout<socket_fdinfo>.size)
            errno = 0
            let rc = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO_OP, &si, sz)
            if rc == sz {
                scan.socketInfoOK += 1
                queued += UInt64(si.psi.soi_rcv.sbi_cc) + UInt64(si.psi.soi_snd.sbi_cc)
            } else {
                scan.socketInfoFailed += 1
            }
        }
        if socketsHere > 0 {
            scan.pidsWithSocket += 1
            scan.perPID[pid] = socketsHere
            scan.queuedBytes[pid] = queued
        }
    }
    scan.elapsedMS = Date().timeIntervalSince(start) * 1000
    return scan
}

// MARK: - Route 4: sysctl net.inet.*.pcblist* (per-socket kernel tables)

func sysctlSize(_ name: String) -> (bytes: Int, err: Int32) {
    var size = 0
    errno = 0
    let rc = sysctlbyname(name, nil, &size, nil, 0)
    return rc == 0 ? (size, 0) : (-1, errno)
}

func sysctlFetch(_ name: String) -> (bytes: Int, err: Int32) {
    let probe = sysctlSize(name)
    guard probe.bytes > 0 else { return probe }
    var size = probe.bytes + 8192   // the table grows between the two calls
    var buf = [UInt8](repeating: 0, count: size)
    errno = 0
    let rc = buf.withUnsafeMutableBytes { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
    return rc == 0 ? (size, 0) : (-1, errno)
}

// MARK: - Route 5: NWPathMonitor (path state)

func pathMonitorSnapshot() -> String {
    let monitor = NWPathMonitor()
    let sem = DispatchSemaphore(value: 0)
    var description = "no update within 3 s"
    monitor.pathUpdateHandler = { path in
        let ifaces = path.availableInterfaces.map { "\($0.name)/\($0.type)" }.joined(separator: ",")
        description = "status=\(path.status) expensive=\(path.isExpensive) "
            + "constrained=\(path.isConstrained) interfaces=[\(ifaces)]"
        sem.signal()
    }
    monitor.start(queue: DispatchQueue(label: "netprobe.path"))
    _ = sem.wait(timeout: .now() + 3)
    monitor.cancel()
    return description
}

// MARK: - Route 6: can a sandboxed process exec `nettop`?
//
// nettop links /System/Library/PrivateFrameworks/NetworkStatistics.framework
// (verified with `otool -L`, outside this probe). We do not link or dlopen it.
// This measures only whether the sandbox permits shelling out to it, because
// "shell out to a system tool" is the workaround someone will eventually
// propose, and it should be refused on evidence rather than instinct.

func runNettop() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
    p.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]
    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do {
        try p.run()
    } catch {
        return "exec FAILED: \(error)"
    }
    let deadline = Date().addingTimeInterval(10)
    while p.isRunning && Date() < deadline { usleep(100_000) }
    if p.isRunning { p.terminate(); return "exec started but did not exit within 10 s" }
    let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
    let stderrData = err.fileHandleForReading.readDataToEndOfFile()
    let lines = String(decoding: stdoutData, as: UTF8.self)
        .split(separator: "\n", omittingEmptySubsequences: true)
    let errText = String(decoding: stderrData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return "exit=\(p.terminationStatus) stdout_lines=\(lines.count)"
        + (errText.isEmpty ? "" : " stderr=\"\(errText.prefix(160))\"")
        + (lines.isEmpty ? "" : " first=\"\(lines[0].prefix(120))\"")
}

// MARK: - Report

setvbuf(stdout, nil, _IONBF, 0)

let home = NSHomeDirectory()
let sandboxed = home.contains("/Containers/")

emit("=== FR-051 per-application network attribution probe (TASK-40) ===")
emit("sandboxed (home in a container): \(sandboxed)")
emit("home: \(home)")
emit("euid: \(geteuid())  gap: \(gapSeconds) s")
emit("entitlements: app-sandbox only — NO com.apple.security.network.client,")
emit("              NO network-server, NO NetworkExtension entitlement.")
emit("")

// --- sample 1
let if1 = getifaddrsCounters()
let il1 = iflist2Counters()
let procs1 = listAllPIDs()
let sock1 = scanSockets(procs1)

Thread.sleep(forTimeInterval: gapSeconds)

// --- sample 2
let if2 = getifaddrsCounters()
let il2 = iflist2Counters()
let procs2 = listAllPIDs()
let sock2 = scanSockets(procs2)

/// A counter that ran backwards has wrapped. Report both readings so the
/// reader can see the width it wrapped at rather than take the correction on
/// trust (FR-051: "handle counter reset and wrap").
func deltaAndNote(_ before: UInt64, _ after: UInt64) -> (delta: UInt64, note: String) {
    if after >= before { return (after - before, "") }
    let mod32 = (after &+ (1 << 32)) &- before
    return (mod32, "WRAPPED at 2^32 (before=\(before) after=\(after))")
}

emit("--- Route 1: getifaddrs + struct if_data (public, net/if_var.h) ---")
if if2.err != 0 {
    emit("getifaddrs FAILED: \(errnoName(if2.err))")
} else {
    emit("ifaddrs entries: \(if2.total)   AF_LINK entries with if_data: \(if2.linkEntries)")
    emit("counter width: ifi_ibytes/ifi_obytes are u_int32_t — they WRAP at 4 GiB")
    emit("interface        delta_in_B   delta_out_B")
    for name in if2.counters.keys.sorted() {
        guard let b = if1.counters[name], let a = if2.counters[name] else { continue }
        let din = deltaAndNote(b.ibytes, a.ibytes)
        let dout = deltaAndNote(b.obytes, a.obytes)
        guard din.delta != 0 || dout.delta != 0 else { continue }
        emit(name.padding(toLength: 16, withPad: " ", startingAt: 0)
            + String(format: "%12llu  %12llu", din.delta, dout.delta)
            + (din.note.isEmpty ? "" : "  in \(din.note)")
            + (dout.note.isEmpty ? "" : "  out \(dout.note)"))
    }
}
emit("")

emit("--- Route 2: sysctl NET_RT_IFLIST2 + if_msghdr2/if_data64 (public) ---")
if il2.err != 0 {
    emit("sysctl NET_RT_IFLIST2 FAILED: \(errnoName(il2.err))")
} else {
    emit("bytes returned: \(il2.bytes)   route messages: \(il2.messages)   "
        + "interfaces with if_data64: \(il2.counters.count)")
    emit("interface        delta_in_B   delta_out_B   delta_in_pkt  delta_out_pkt")
    var totalIn: UInt64 = 0, totalOut: UInt64 = 0
    for name in il2.counters.keys.sorted() {
        guard let b = il1.counters[name], let a = il2.counters[name] else { continue }
        let din = deltaAndNote(b.ibytes, a.ibytes)
        let dout = deltaAndNote(b.obytes, a.obytes)
        totalIn &+= din.delta
        totalOut &+= dout.delta
        guard din.delta != 0 || dout.delta != 0 else { continue }
        emit(name.padding(toLength: 16, withPad: " ", startingAt: 0)
            + String(format: "%12llu  %12llu  %12llu  %12llu",
                     din.delta, dout.delta,
                     a.ipackets &- b.ipackets, a.opackets &- b.opackets))
        if !din.note.isEmpty { emit("    in  \(din.note)") }
        if !dout.note.isEmpty { emit("    out \(dout.note)") }
    }
    emit(String(format: "TOTAL over %.1f s: in %llu B  out %llu B", gapSeconds, totalIn, totalOut))
}
emit("")

emit("--- Route 3: libproc PROC_PIDLISTFDS + PROC_PIDFDSOCKETINFO ---")
let s = sock2
let errText = s.errnos.sorted { $0.value > $1.value }
    .map { "\(errnoName($0.key))×\($0.value)" }.joined(separator: " ")
emit("pids attempted        : \(s.pidsAttempted)")
emit("pids yielding an FD list: \(s.pidsWithFDList)   denied/failed: \(s.pidsDenied)"
    + (errText.isEmpty ? "" : "   [\(errText)]"))
emit("  own-uid  : \(s.ownUidWithFDList)/\(s.ownUidTotal)")
emit("  other-uid: \(s.otherUidWithFDList)/\(s.otherUidTotal)")
emit("pids holding >=1 socket: \(s.pidsWithSocket)")
emit("socket FDs seen        : \(s.socketsSeen)   "
    + "PROC_PIDFDSOCKETINFO ok: \(s.socketInfoOK)  failed: \(s.socketInfoFailed)")
emit(String(format: "scan cost              : %.1f ms for the whole table", s.elapsedMS))
emit("struct socket_info fields available: soi_type, soi_protocol, soi_family,")
emit("  soi_state, soi_rcv/soi_snd (sockbuf_info: sbi_cc, sbi_hiwat, ...), soi_proto.")
emit("  sbi_cc is CURRENT QUEUE OCCUPANCY, not a cumulative byte counter.")
emit("  There is no rx/tx byte or packet total anywhere in the struct.")
emit("top 10 pids by socket count (sockets, queued_bytes = sbi_cc rcv+snd):")
let byCount = s.perPID.sorted { $0.value > $1.value }.prefix(10)
let nameByPID = Dictionary(procs2.map { ($0.pid, $0.comm) }, uniquingKeysWith: { a, _ in a })
for (pid, count) in byCount {
    let n = nameByPID[pid] ?? "?"
    emit("  \(n) [\(pid)]".padding(toLength: 34, withPad: " ", startingAt: 0)
        + String(format: "%5d sockets  %8llu queued_B", count, s.queuedBytes[pid] ?? 0))
}
// Did the FD-count view move at all across a transfer of gigabytes?
let deltaSockets = s.socketsSeen - sock1.socketsSeen
emit("socket FD count delta across the window: \(deltaSockets) "
    + "(a count, not a volume — it cannot express throughput)")

// The load generators are the one case where the true byte volume is known, so
// they are the honest test of whether any per-process figure tracks it.
emit("the processes that generated the traffic (curl / python3 loopback load):")
var foundLoad = false
for (pid, comm, _) in procs2 where comm.contains("curl") || comm.lowercased().contains("python") {
    foundLoad = true
    emit("  \(comm) [\(pid)]".padding(toLength: 34, withPad: " ", startingAt: 0)
        + String(format: "%5d sockets  %8llu queued_B  cumulative_bytes: UNAVAILABLE",
                 s.perPID[pid] ?? 0, s.queuedBytes[pid] ?? 0))
}
if !foundLoad { emit("  (none present — was the load running?)") }
emit("")

emit("--- Route 4: sysctl per-socket kernel tables ---")
for name in ["net.inet.tcp.pcblist", "net.inet.tcp.pcblist_n",
             "net.inet.udp.pcblist", "net.inet.udp.pcblist_n",
             "net.inet.tcp.stats", "net.link.generic.system.ifcount"] {
    let r = sysctlFetch(name)
    if r.bytes >= 0 {
        emit("\(name.padding(toLength: 34, withPad: " ", startingAt: 0)) READ ok, \(r.bytes) bytes")
    } else {
        emit("\(name.padding(toLength: 34, withPad: " ", startingAt: 0)) FAILED \(errnoName(r.err))")
    }
}
emit("NOTE: struct xinpgen / xsocket_n / xsockstat_n / xtcpcb_n are NOT in the")
emit("  public SDK (grepped MacOSX.sdk/usr/include: zero hits for 'pcblist' and")
emit("  'xsocket_n'). Decoding these buffers means hardcoding kernel-private ABI.")
emit("  The one externalised socket struct that IS public — struct xsocket in")
emit("  sys/socketvar.h — carries so_rcv/so_snd occupancy and so_uid, and NO")
emit("  cumulative byte counters and no pid.")
emit("")

emit("--- Route 5: NWPathMonitor ---")
emit(pathMonitorSnapshot())
emit("NWPath exposes reachability, interface type, expensive/constrained flags.")
emit("Its API surface contains no byte or packet counter of any kind.")
emit("")

emit("--- Route 6: exec /usr/bin/nettop (links a PRIVATE framework; not linked here) ---")
emit(runNettop())
emit("")

emit("--- Verdict inputs ---")
emit("aggregate machine-wide throughput available: "
    + (il2.err == 0 && !il2.counters.isEmpty ? "YES (if_data64, 64-bit, per interface)" : "NO"))
emit("per-process byte counters from any public API: NO route above returns one")
emit("per-process socket existence: \(s.pidsWithSocket) pids, \(s.socketsSeen) sockets")

try? log.write(toFile: home + "/net-probe-result.txt", atomically: true, encoding: .utf8)
exit(0)
