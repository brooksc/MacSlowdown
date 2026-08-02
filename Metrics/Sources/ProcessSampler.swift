import Darwin
import Foundation

/// Reads the process table and per-process CPU and memory.
///
/// Enumeration goes through `sysctl KERN_PROC_ALL`, **not** `proc_listpids`. The
/// latter is denied under App Sandbox (`process-info-listpids`, EPERM) and Apple
/// DTS has confirmed no entitlement lifts it. sysctl is a separately gated
/// operation that returns the full table. See probe/FINDINGS.md.
public struct ProcessSampler: Sendable {
    public init() {}

    /// One complete pass. Never throws: a process that vanishes mid-sweep or denies
    /// access is recorded with the reason, not dropped.
    public func snapshot() -> ProcessSnapshot {
        let clock = ContinuousClock()
        let start = clock.now
        var records: [ProcessIdentity: ProcessRecord] = [:]

        let table = Self.processTable()
        records.reserveCapacity(table.count)
        for entry in table {
            records[entry.identity] = ProcessRecord(
                identity: entry.identity,
                command: entry.command,
                uid: entry.uid,
                ppid: entry.ppid,
                metrics: Self.metrics(for: entry.identity.pid)
            )
        }

        return ProcessSnapshot(
            records: records,
            takenAt: start,
            sweepDuration: clock.now - start
        )
    }

    // MARK: - Enumeration

    struct TableEntry {
        let identity: ProcessIdentity
        let command: String
        let uid: uid_t
        let ppid: pid_t
    }

    /// Full process table via `sysctl KERN_PROC_ALL`.
    ///
    /// The table can grow between sizing and reading, so this retries rather than
    /// truncating. Returns empty only if sysctl genuinely fails.
    static func processTable(attempts: Int = 3) -> [TableEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

        for _ in 0..<attempts {
            var needed = 0
            guard sysctl(&mib, 4, nil, &needed, nil, 0) == 0, needed > 0 else { return [] }

            // Slack for processes spawned between the sizing call and the read.
            var size = needed + (needed / 8)
            var buffer = [UInt8](repeating: 0, count: size)
            let result = buffer.withUnsafeMutableBytes { raw in
                sysctl(&mib, 4, raw.baseAddress, &size, nil, 0)
            }
            if result != 0 {
                if errno == ENOMEM { continue }  // table grew again; resize and retry
                return []
            }
            return decode(buffer: buffer, byteCount: size)
        }
        return []
    }

    private static func decode(buffer: [UInt8], byteCount: Int) -> [TableEntry] {
        let stride = MemoryLayout<kinfo_proc>.stride
        let count = byteCount / stride
        guard count > 0 else { return [] }

        return buffer.withUnsafeBytes { raw -> [TableEntry] in
            let procs = raw.bindMemory(to: kinfo_proc.self)
            var entries: [TableEntry] = []
            entries.reserveCapacity(count)
            for index in 0..<min(count, procs.count) {
                var proc = procs[index]
                let pid = proc.kp_proc.p_pid
                guard pid > 0 else { continue }  // pid 0 is kernel_task

                let started = proc.kp_proc.p_starttime
                let startTime = UInt64(started.tv_sec) * 1_000_000 + UInt64(started.tv_usec)
                let command = withUnsafeBytes(of: &proc.kp_proc.p_comm) { bytes in
                    String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
                }

                entries.append(TableEntry(
                    identity: ProcessIdentity(pid: pid, startTime: startTime),
                    command: command,
                    uid: proc.kp_eproc.e_ucred.cr_uid,
                    ppid: proc.kp_eproc.e_ppid
                ))
            }
            return entries
        }
    }

    // MARK: - Per-process metrics

    /// `PROC_PIDTASKINFO` rather than `PROC_PIDTASKALLINFO`: the enumeration above
    /// already yields everything TASKALLINFO's bsdinfo half would give us (name,
    /// uid, ppid, start time), so asking for it again would copy an extra 136 bytes
    /// per process for nothing. Same syscall count, less work.
    static func metrics(for pid: pid_t) -> MetricsResult {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        errno = 0
        let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)

        guard written == size else {
            switch errno {
            case EPERM: return .notPermitted
            case ESRCH: return .exited
            case 0: return .failed(errno: 0)   // short read without an errno
            default: return .failed(errno: errno)
            }
        }

        return .measured(ProcessMetrics(
            cpuTicks: info.pti_total_user &+ info.pti_total_system,
            residentBytes: info.pti_resident_size
        ))
    }
}
