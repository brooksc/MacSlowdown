import Darwin
import Foundation
import IOKit
import Metal

// Is GPU utilisation readable by a sandboxed App Store build (FR-052)?
//
// The claim under test: Apple Silicon GPU utilisation is available through the
// public IOAccelerator registry with no private API and no elevated privileges,
// while temperature and frequency — which need SMC access — are not.
//
// A zero reading proves nothing, so this drives a real Metal compute load and
// compares idle against busy. If the number does not move under load, it is not
// a utilisation figure we can trust, whatever it is called.

// MARK: - IORegistry

/// Every property of every IOAccelerator service.
func acceleratorProperties() -> [(name: String, properties: [String: Any])] {
    var iterator = io_iterator_t()
    guard IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }

    var result: [(String, [String: Any])] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }

        var name = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(service, &name)

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { continue }

        result.append((String(cString: name), properties))
    }
    return result
}

/// Device utilisation, as a percentage, from the first accelerator reporting it.
func deviceUtilisation() -> Double? {
    for entry in acceleratorProperties() {
        guard let statistics = entry.properties["PerformanceStatistics"] as? [String: Any]
        else { continue }
        for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
            if let value = statistics[key] as? NSNumber { return value.doubleValue }
        }
    }
    return nil
}

// MARK: - A real GPU load

/// Runs GPU work until `deadline`. Compute rather than rendering, so it needs no
/// window, no display and no screen access.
func runGPULoad(until deadline: Date) -> Bool {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue() else { return false }

    let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void burn(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
        float value = out[id];
        for (int i = 0; i < 40000; i++) { value = fma(value, 1.0000001f, 0.0000001f); }
        out[id] = value;
    }
    """
    guard let library = try? device.makeLibrary(source: source, options: nil),
          let function = library.makeFunction(name: "burn"),
          let pipeline = try? device.makeComputePipelineState(function: function),
          let buffer = device.makeBuffer(length: 1 << 20, options: .storageModeShared)
    else { return false }

    let threads = MTLSize(width: 1 << 16, height: 1, depth: 1)
    let group = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)

    while Date() < deadline {
        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
    }
    return true
}

// MARK: - Run

print("=== IOAccelerator services visible to a sandboxed app ===")
let services = acceleratorProperties()
print("services: \(services.count)")
for entry in services {
    print("  \(entry.name)")
    let statistics = entry.properties["PerformanceStatistics"] as? [String: Any] ?? [:]
    print("    PerformanceStatistics keys: \(statistics.keys.sorted().joined(separator: ", "))")
}

guard !services.isEmpty else {
    print("\nRESULT: no IOAccelerator service is readable. FR-052 is not deliverable.")
    exit(0)
}

// Sampling cost, against the FR-030 budget.
let costStart = Date()
let iterations = 20
for _ in 0..<iterations { _ = deviceUtilisation() }
let perSample = Date().timeIntervalSince(costStart) / Double(iterations) * 1000
print("")
print("=== sampling cost ===")
print(String(format: "%.2f ms per read (mean of %d)", perSample, iterations))

// Idle baseline. Several reads, because one could catch incidental activity.
print("")
print("=== idle baseline ===")
var idle: [Double] = []
for _ in 0..<8 {
    if let value = deviceUtilisation() { idle.append(value) }
    Thread.sleep(forTimeInterval: 0.25)
}
print("readings: \(idle.map { String(format: "%.1f", $0) }.joined(separator: ", "))")

guard !idle.isEmpty else {
    print("\nRESULT: no utilisation key found. FR-052 is not deliverable this way.")
    exit(0)
}

// Under load.
print("")
print("=== under a real Metal compute load ===")
let deadline = Date().addingTimeInterval(6)
let loadThread = Thread { _ = runGPULoad(until: deadline) }
loadThread.start()
Thread.sleep(forTimeInterval: 1.5)

var busy: [Double] = []
while Date() < deadline.addingTimeInterval(-0.5) {
    if let value = deviceUtilisation() { busy.append(value) }
    Thread.sleep(forTimeInterval: 0.25)
}
print("readings: \(busy.map { String(format: "%.1f", $0) }.joined(separator: ", "))")

let idlePeak = idle.max() ?? 0
let busyPeak = busy.max() ?? 0
print("")
print(String(format: "idle peak %.1f%%, busy peak %.1f%%", idlePeak, busyPeak))
print(busyPeak > idlePeak + 20
      ? "RESULT: the figure responds to real GPU work. Machine-wide utilisation is available."
      : "RESULT: the figure did NOT move materially under load. Do not trust it as utilisation.")

// MARK: - What is NOT available

print("")
print("=== confirming what remains unavailable ===")
var sawTemperature = false
var sawFrequency = false
for entry in services {
    let statistics = entry.properties["PerformanceStatistics"] as? [String: Any] ?? [:]
    for key in statistics.keys {
        let lowered = key.lowercased()
        if lowered.contains("temp") { sawTemperature = true; print("  temperature key: \(key)") }
        if lowered.contains("freq") || lowered.contains("clock") {
            sawFrequency = true; print("  frequency key: \(key)")
        }
    }
}
if !sawTemperature { print("  no temperature key in any IOAccelerator service") }
if !sawFrequency { print("  no frequency or clock key in any IOAccelerator service") }

// MARK: - Per-process?

print("")
print("=== is any of this per-process? ===")
var perProcessKeys: [String] = []
for entry in services {
    for key in entry.properties.keys {
        let lowered = key.lowercased()
        if lowered.contains("pid") || lowered.contains("process") || lowered.contains("client") {
            perProcessKeys.append("\(entry.name).\(key)")
        }
    }
}
print(perProcessKeys.isEmpty
      ? "  no per-process or per-client key found: this is machine-wide only"
      : "  candidate keys: \(perProcessKeys.joined(separator: ", "))")
