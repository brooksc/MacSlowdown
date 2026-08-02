// How much of the machine can a sandboxed app actually account for?
import Darwin
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
let scale = Double(tb.numer)/Double(tb.denom)

func procs() -> [(Int32, String, UInt32)] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]; var size = 0
    guard sysctl(&mib,4,nil,&size,nil,0) == 0 else { return [] }
    var buf = [UInt8](repeating:0,count:size)
    guard buf.withUnsafeMutableBytes({ sysctl(&mib,4,$0.baseAddress,&size,nil,0) }) == 0 else { return [] }
    let c = size/MemoryLayout<kinfo_proc>.stride
    return buf.withUnsafeBytes { raw in
        let p = raw.bindMemory(to: kinfo_proc.self)
        return (0..<min(c,p.count)).compactMap { i in
            var kp = p[i]; let pid = kp.kp_proc.p_pid; guard pid > 0 else { return nil }
            let nm = withUnsafeBytes(of: &kp.kp_proc.p_comm){ String(decoding: $0.prefix{ $0 != 0 }, as: UTF8.self) }
            return (pid, nm, kp.kp_eproc.e_ucred.cr_uid)
        }
    }
}
func cpuTicks(_ pid: Int32) -> UInt64? {
    var t = proc_taskinfo(); let sz = Int32(MemoryLayout<proc_taskinfo>.size)
    guard proc_pidinfo(pid,4,0,&t,sz) == sz else { return nil }
    return t.pti_total_user + t.pti_total_system
}
func hostCPU() -> (UInt64,UInt64) {
    var n: natural_t = 0; var info: processor_info_array_t?; var ic: mach_msg_type_number_t = 0
    host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &ic)
    var u: UInt64 = 0, t: UInt64 = 0
    if let info { for c in 0..<Int(n) { let b = c*Int(CPU_STATE_MAX)
        let us=UInt64(info[b+Int(CPU_STATE_USER)]), sy=UInt64(info[b+Int(CPU_STATE_SYSTEM)])
        let ni=UInt64(info[b+Int(CPU_STATE_NICE)]), id=UInt64(info[b+Int(CPU_STATE_IDLE)])
        u += us+sy+ni; t += us+sy+ni+id } }
    return (u,t)
}
let cores = 8.0
var t0: [Int32:UInt64] = [:]
for (pid,_,_) in procs() { if let c = cpuTicks(pid) { t0[pid] = c } }
let h0 = hostCPU(); let w0 = Date()
Thread.sleep(forTimeInterval: 3.0)
let list = procs(); let h1 = hostCPU(); let wall = Date().timeIntervalSince(w0)
var visibleCoreSecs = 0.0
var deniedNames: [String:Int] = [:]
var me = geteuid()
for (pid,nm,uid) in list {
    if let c1 = cpuTicks(pid) {
        if let c0 = t0[pid], c1 >= c0 { visibleCoreSecs += Double(c1-c0)*scale/1e9 }
    } else { deniedNames[nm, default:0] += 1; _ = uid }
}
let hostBusyCoreSecs = Double(h1.0 &- h0.0)/Double(h1.1 &- h0.1) * cores * wall
print(String(format:"window: %.1fs", wall))
print(String(format:"host busy      : %.3f core-seconds (%.1f%% of machine)", hostBusyCoreSecs, hostBusyCoreSecs/(cores*wall)*100))
print(String(format:"visible procs  : %.3f core-seconds", visibleCoreSecs))
let unattributed = max(0, hostBusyCoreSecs - visibleCoreSecs)
print(String(format:"UNATTRIBUTED   : %.3f core-seconds  = %.1f%% of all busy CPU", unattributed, hostBusyCoreSecs>0 ? unattributed/hostBusyCoreSecs*100 : 0))
print("")
print("denied processes (count \(deniedNames.values.reduce(0,+))), most common names:")
for (n,c) in deniedNames.sorted(by:{ $0.value > $1.value }).prefix(18) { print("   \(n) x\(c)") }
