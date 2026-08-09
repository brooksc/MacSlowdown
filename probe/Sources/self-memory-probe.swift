// TASK-55.1 — where does MacSlowdown's own memory go?
//
// The running app reads ~3.3 GB resident (`pti_resident_size`, the same field the
// app reports for every other process) against FR-030's 100 MB budget, while its
// phys_footprint reads ~396 MB. `vmmap` attributes 3.0 GB of the resident total to
// mapped files under /Library/Caches/com.apple.iconservices.store.
//
// This probe attributes the cost to a stage rather than asserting a cause. Each
// mode runs in its own process so one stage cannot contaminate the next.
//
// Both numbers are reported every time, deliberately. Resident size counts clean,
// shared, file-backed pages the kernel can evict for free; phys_footprint counts
// the dirty and compressed pages the process is charged for. For this app they
// differ by an order of magnitude, and which one FR-030's budget means is exactly
// the question.
//
// Own-process measurement uses proc_pid_rusage, which is permitted for self even
// under the sandbox (it is denied for every other process — see FINDINGS.md).
//
// Usage: self-memory-probe <mode>
//   stages    enumerate → paths → names → running apps, then icons as the app fetches them
//   icons     icon(forFile:) only, no tiffRepresentation, one autorelease pool per icon
//   tiff      the tiffRepresentation comparison ProcessIconCache makes, pooled per icon
//   asapp     ProcessIconCache's exact sequence with no explicit pool, as the app runs it

import AppKit
import Darwin
import Foundation

let PROC_PIDTASKINFO_: Int32 = 4

struct SelfMemory {
    var residentBytes: UInt64
    var footprintBytes: UInt64
    var peakFootprintBytes: UInt64
}

func measureSelf() -> SelfMemory {
    let pid = getpid()

    var task = proc_taskinfo()
    let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
    let resident: UInt64 =
        proc_pidinfo(pid, PROC_PIDTASKINFO_, 0, &task, taskSize) == taskSize
        ? task.pti_resident_size : 0

    // proc_pid_rusage writes to `buffer`, not `*buffer`, despite its signature.
    var ri = rusage_info_v6()
    let rc = withUnsafeMutablePointer(to: &ri) { riPtr in
        riPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
        }
    }
    return SelfMemory(
        residentBytes: resident,
        footprintBytes: rc == 0 ? ri.ri_phys_footprint : 0,
        peakFootprintBytes: rc == 0 ? ri.ri_lifetime_max_phys_footprint : 0)
}

let started = measureSelf()
var previous = started

func report(_ stage: String) {
    let now = measureSelf()
    func mb(_ v: UInt64) -> Double { Double(v) / 1_048_576 }
    func delta(_ new: UInt64, _ old: UInt64) -> Double {
        (Double(new) - Double(old)) / 1_048_576
    }
    let label = stage.count >= 44 ? stage : stage + String(repeating: " ", count: 44 - stage.count)
    print(label + String(
        format: "rss %8.1f MB (%+8.1f)   footprint %8.1f MB (%+8.1f)",
        mb(now.residentBytes), delta(now.residentBytes, previous.residentBytes),
        mb(now.footprintBytes), delta(now.footprintBytes, previous.footprintBytes)))
    previous = now
}

// MARK: - Enumeration (the app's only process-table contact point)

func listAllPIDs() -> [Int32] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard buf.withUnsafeMutableBytes({ sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }) == 0
    else { return [] }
    let count = size / MemoryLayout<kinfo_proc>.stride
    return buf.withUnsafeBytes { raw in
        let procs = raw.bindMemory(to: kinfo_proc.self)
        return (0..<min(count, procs.count)).compactMap {
            let pid = procs[$0].kp_proc.p_pid
            return pid > 0 ? pid : nil
        }
    }
}

/// Mirrors ProcessNaming.namingBundle: the outermost `.app`, else an `.appex`.
/// `.framework` is excluded — it never yields a better name.
func namingBundle(for path: String) -> String? {
    for suffix in [".app", ".appex"] {
        if let range = path.range(of: suffix + "/") {
            return String(path[path.startIndex..<range.lowerBound]) + suffix
        }
        if path.hasSuffix(suffix) { return path }
    }
    return nil
}

func namingBundles() -> [String] {
    var bundles = Set<String>()
    for pid in listAllPIDs() {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { continue }
        if let bundle = namingBundle(for: String(cString: buf)) { bundles.insert(bundle) }
    }
    return bundles.sorted()
}

setvbuf(stdout, nil, _IONBF, 0)

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "stages"
print("=== TASK-55.1 self-memory attribution probe — mode: \(mode) ===")
print("pid \(getpid())  page size \(vm_page_size) bytes")
print("")
report("baseline (process start)")

switch mode {

case "stages":
    let pids = listAllPIDs()
    report("after sysctl KERN_PROC_ALL (\(pids.count) pids)")

    var paths: [Int32: String] = [:]
    for pid in pids {
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { paths[pid] = String(cString: buf) }
    }
    report("after proc_pidpath (\(paths.count) paths)")

    var bundles = Set<String>()
    for path in paths.values { if let b = namingBundle(for: path) { bundles.insert(b) } }
    var names = 0
    for bundle in bundles {
        if let dict = NSDictionary(contentsOfFile: bundle + "/Contents/Info.plist"),
           (dict["CFBundleDisplayName"] ?? dict["CFBundleName"]) as? String != nil {
            names += 1
        }
    }
    report("after Info.plist names (\(names)/\(bundles.count))")

    let running = NSWorkspace.shared.runningApplications
    report("after runningApplications (\(running.count))")

    _ = NSWorkspace.shared.icon(for: .unixExecutable).tiffRepresentation
    report("after ONE generic icon + tiffRepresentation")

case "icons":
    // icon(forFile:) alone, each call pooled, the NSImages retained in a cache.
    // An NSImage is a lazy promise; this is what holding 117 of them costs.
    let bundles = namingBundles()
    var cache: [String: NSImage] = [:]
    for bundle in bundles {
        autoreleasepool { cache[bundle] = NSWorkspace.shared.icon(forFile: bundle) }
    }
    report("after \(cache.count) icon(forFile:) [pooled, retained]")

    var drawn = 0
    for image in cache.values {
        autoreleasepool {
            if image.bestRepresentation(for: NSRect(x: 0, y: 0, width: 16, height: 16),
                                        context: nil, hints: nil) != nil { drawn += 1 }
        }
    }
    report("after rasterising \(drawn) at 16pt [pooled]")

    cache.removeAll()
    autoreleasepool {}
    report("after releasing the cache")

case "tiff":
    // The comparison ProcessIconCache makes against the generic icon to decide
    // whether an icon is real (FR-002 forbids showing a placeholder as an icon).
    // Pooled per icon, so what remains is retained, not autorelease garbage.
    let bundles = namingBundles()
    var generic: Data?
    autoreleasepool { generic = NSWorkspace.shared.icon(for: .unixExecutable).tiffRepresentation }
    report("after generic icon tiffRepresentation")
    if let generic { print("   generic tiffRepresentation is \(generic.count / 1_048_576) MB") }

    var real = 0
    var biggest = 0
    for bundle in bundles {
        autoreleasepool {
            let candidate = NSWorkspace.shared.icon(forFile: bundle)
            let tiff = candidate.tiffRepresentation
            biggest = max(biggest, tiff?.count ?? 0)
            if tiff != generic { real += 1 }
        }
    }
    report("after \(bundles.count) tiffRepresentation [pooled]")
    print("   largest single tiffRepresentation: \(biggest / 1_048_576) MB")

case "asapp":
    // ProcessIconCache's exact sequence, with no explicit autorelease pool —
    // one sweep of the app's icon path as the app runs it.
    let bundles = namingBundles()
    let generic = NSWorkspace.shared.icon(for: .unixExecutable).tiffRepresentation
    report("after generic icon [unpooled]")

    var cache: [String: NSImage?] = [:]
    var real = 0
    for bundle in bundles {
        let candidate = NSWorkspace.shared.icon(forFile: bundle)
        let resolved: NSImage? = candidate.tiffRepresentation == generic ? nil : candidate
        cache[bundle] = resolved
        if resolved != nil { real += 1 }
    }
    report("after \(bundles.count) icons (\(real) real) [unpooled]")

    // Draining is what a run loop does between events. If the cost is autorelease
    // garbage rather than retained memory, it comes back here.
    autoreleasepool {}
    report("after draining the autorelease pool")

    cache.removeAll()
    autoreleasepool {}
    report("after releasing the icon cache")

case "cheap":
    // Candidate replacements for the tiffRepresentation comparison. The test is
    // not "is it cheaper" alone — it must classify every bundle the same way, or
    // it trades a memory problem for an FR-002 problem (a generic placeholder
    // shown as if it were the application's own icon).
    let bundles = namingBundles()
    let genericImage = NSWorkspace.shared.icon(for: .unixExecutable)

    // Reference classification, by the method the app uses today.
    var truth: [String: Bool] = [:]
    autoreleasepool {
        let genericTIFF = genericImage.tiffRepresentation
        for bundle in bundles {
            autoreleasepool {
                truth[bundle] = NSWorkspace.shared.icon(forFile: bundle)
                    .tiffRepresentation != genericTIFF
            }
        }
    }
    report("reference classification via tiffRepresentation")
    print("   classified real: \(truth.values.filter { $0 }.count)/\(bundles.count)")

    // Candidate A: the icon's `name()`. IconServices hands back a named system
    // image for the generic case and an unnamed one for a real bundle icon.
    var byName: [String: Bool] = [:]
    let genericName = genericImage.name()
    let beforeA = measureSelf()
    for bundle in bundles {
        autoreleasepool {
            byName[bundle] = NSWorkspace.shared.icon(forFile: bundle).name() != genericName
        }
    }
    report("candidate A: NSImage.name()")
    print("   agrees with reference: \(bundles.filter { byName[$0] == truth[$0] }.count)/\(bundles.count)")
    print(String(format: "   footprint cost: %+.2f MB",
                 (Double(measureSelf().footprintBytes) - Double(beforeA.footprintBytes)) / 1_048_576))

    // Candidate B: rasterise both to a fixed 32pt bitmap and compare those bytes.
    // 32x32 RGBA is 4 KB, against 70 MB for a full-resolution TIFF.
    func thumbnail(_ image: NSImage) -> Data? {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    var byThumb: [String: Bool] = [:]
    let genericThumb = thumbnail(genericImage)
    let beforeB = measureSelf()
    for bundle in bundles {
        autoreleasepool {
            byThumb[bundle] = thumbnail(NSWorkspace.shared.icon(forFile: bundle)) != genericThumb
        }
    }
    report("candidate B: 32pt rasterised comparison")
    print("   agrees with reference: \(bundles.filter { byThumb[$0] == truth[$0] }.count)/\(bundles.count)")
    print(String(format: "   footprint cost: %+.2f MB",
                 (Double(measureSelf().footprintBytes) - Double(beforeB.footprintBytes)) / 1_048_576))

    // Negative control. Every one of the 117 bundles classified as "real", so
    // agreement above is also what a method that always says "real" would score.
    // These paths have no bundle icon and must classify as generic, or the
    // comparison is not discriminating at all.
    print("")
    print("   negative control (must classify as GENERIC):")
    for path in ["/bin/ls", "/usr/bin/true", "/no/such/path"] {
        autoreleasepool {
            let icon = NSWorkspace.shared.icon(forFile: path)
            let byRef = icon.tiffRepresentation != genericImage.tiffRepresentation
            let byThumbnail = thumbnail(icon) != genericThumb
            print("     \(path): reference says \(byRef ? "real" : "generic"), "
                + "32pt says \(byThumbnail ? "real" : "generic")"
                + (byRef == byThumbnail ? "  [agree]" : "  [DISAGREE]"))
        }
    }

default:
    print("unknown mode: \(mode)")
    exit(2)
}

let end = measureSelf()
print("")
print(String(format: "total growth: rss %+.1f MB, footprint %+.1f MB",
             (Double(end.residentBytes) - Double(started.residentBytes)) / 1_048_576,
             (Double(end.footprintBytes) - Double(started.footprintBytes)) / 1_048_576))
print(String(format: "peak footprint over the run: %.1f MB   (FR-030 budget: 100 MB)",
             Double(end.peakFootprintBytes) / 1_048_576))
