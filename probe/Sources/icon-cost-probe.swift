// TASK-55.1 — before/after for the ProcessIconCache icon comparison.
//
// self-memory-probe reimplements the comparison to characterise it. This one
// runs the shipping `ProcessIconCache` itself, compiled straight from
// Metrics/Sources, so the figure belongs to the code the app runs rather than to
// a copy of it that could drift.
//
// The "before" arm reproduces the previous implementation — comparing full
// `tiffRepresentation` data — over the same bundles in the same process order,
// so the two arms differ only in the comparison.
//
// Each arm must run in its own process: malloc does not return large blocks to
// the OS promptly, so measuring both in one process charges the second arm for
// the first arm's high-water mark.
//
// Usage: icon-cost-probe <before|after>

import AppKit
import Darwin
import Foundation

let PROC_PIDTASKINFO_: Int32 = 4

func selfFootprintBytes() -> UInt64 {
    var ri = rusage_info_v6()
    let rc = withUnsafeMutablePointer(to: &ri) { riPtr in
        riPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
        }
    }
    return rc == 0 ? ri.ri_phys_footprint : 0
}

func selfPeakFootprintBytes() -> UInt64 {
    var ri = rusage_info_v6()
    let rc = withUnsafeMutablePointer(to: &ri) { riPtr in
        riPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
        }
    }
    return rc == 0 ? ri.ri_lifetime_max_phys_footprint : 0
}

func selfResidentBytes() -> UInt64 {
    var task = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    return proc_pidinfo(getpid(), PROC_PIDTASKINFO_, 0, &task, size) == size
        ? task.pti_resident_size : 0
}

func executablePaths() -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard buf.withUnsafeMutableBytes({ sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }) == 0
    else { return [] }
    let count = size / MemoryLayout<kinfo_proc>.stride
    let pids: [Int32] = buf.withUnsafeBytes { raw in
        let procs = raw.bindMemory(to: kinfo_proc.self)
        return (0..<min(count, procs.count)).compactMap {
            let pid = procs[$0].kp_proc.p_pid
            return pid > 0 ? pid : nil
        }
    }
    return pids.compactMap { pid in
        var path = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &path, UInt32(path.count)) > 0 ? String(cString: path) : nil
    }
}

func mb(_ v: UInt64) -> Double { Double(v) / 1_048_576 }

/// Top-level code is only permitted in `main.swift`, and this probe is compiled
/// alongside the framework sources, so the entry point is explicit.
@main
enum IconCostProbe {
    @MainActor
    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        let arm = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "after"
        let paths = executablePaths()

        print("=== TASK-55.1 icon comparison cost — arm: \(arm) ===")
        print("processes with a readable path: \(paths.count)")

        let before = selfFootprintBytes()
        let beforeRSS = selfResidentBytes()
        var resolved = 0
        var bundles = 0

        switch arm {
        case "after":
            // The shipping code, unchanged.
            let cache = ProcessIconCache()
            for path in paths where cache.icon(forExecutablePath: path) != nil { resolved += 1 }
            bundles = cache.cachedCount

        case "before":
            // The previous implementation, reproduced. `namingBundle` is the
            // shipping one, so only the comparison differs.
            var cache: [String: NSImage?] = [:]
            let generic = NSWorkspace.shared.icon(for: .unixExecutable).tiffRepresentation
            for path in paths {
                guard let bundle = ProcessNaming.namingBundle(for: path) else { continue }
                if let cached = cache[bundle] {
                    if cached != nil { resolved += 1 }
                    continue
                }
                let candidate = NSWorkspace.shared.icon(forFile: bundle)
                let icon: NSImage? = candidate.tiffRepresentation == generic ? nil : candidate
                cache[bundle] = icon
                if icon != nil { resolved += 1 }
            }
            bundles = cache.count

        case "agree":
            // Correctness, not cost: both classifications over the same bundles
            // in one process, so the comparison cannot be confounded by the
            // process table changing between runs. Memory here is meaningless —
            // it pays for the old method deliberately.
            let cache = ProcessIconCache()
            let genericTIFF = NSWorkspace.shared.icon(for: .unixExecutable).tiffRepresentation
            var disagreements: [String] = []
            var seen = Set<String>()
            for path in paths {
                guard let bundle = ProcessNaming.namingBundle(for: path),
                      seen.insert(bundle).inserted else { continue }
                let shipping = cache.icon(forExecutablePath: path) != nil
                let previous = autoreleasepool {
                    NSWorkspace.shared.icon(forFile: bundle).tiffRepresentation != genericTIFF
                }
                if shipping != previous { disagreements.append(bundle) }
            }
            bundles = seen.count
            print("bundles compared: \(bundles)")
            print("disagreements: \(disagreements.count)")
            for bundle in disagreements.prefix(20) { print("   \(bundle)") }

            // Negative control. Every bundle on this machine classifies as real,
            // so zero disagreements above would also be scored by a comparison
            // that never says "generic". These must come back generic.
            print("negative control (must be GENERIC under both):")
            for path in ["/bin/ls", "/usr/bin/true", "/usr/sbin/notifyd"] {
                let icon = NSWorkspace.shared.icon(forFile: path)
                let shipping = ProcessIconCache.fingerprint(icon)
                    != ProcessIconCache.fingerprint(
                        NSWorkspace.shared.icon(for: .unixExecutable))
                let previous = icon.tiffRepresentation != genericTIFF
                print("   \(path): 32pt says \(shipping ? "real" : "generic"), "
                    + "tiff says \(previous ? "real" : "generic")"
                    + (shipping == previous ? "  [agree]" : "  [DISAGREE]"))
            }

        default:
            print("unknown arm: \(arm)")
            exit(2)
        }

        let after = selfFootprintBytes()
        let afterRSS = selfResidentBytes()
        print("distinct bundles classified: \(bundles), processes given an icon: \(resolved)")
        print(String(format: "footprint: %.1f MB -> %.1f MB  (%+.1f MB)",
                     mb(before), mb(after), mb(after) - mb(before)))
        print(String(format: "resident:  %.1f MB -> %.1f MB  (%+.1f MB)",
                     mb(beforeRSS), mb(afterRSS), mb(afterRSS) - mb(beforeRSS)))
        print(String(format: "peak footprint over the run: %.1f MB   (FR-030 budget: 100 MB)",
                     mb(selfPeakFootprintBytes())))
    }
}
