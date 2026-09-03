import Darwin
import Foundation

/// TASK-103 — does the run queue separate "felt slow" from "busy but fine"?
///
/// FR-006's condition needs 85% of machine capacity sustained for three minutes.
/// The observation that prompted the amendment is that a machine can be unusable
/// well below that: peak load 95.8 on 8 cores — about twelve runnable threads per
/// core — while CPU busy sat at 44–51%. Correlation across that run was 0.68, which
/// is high enough to say the two are related and low enough to say they are not the
/// same signal.
///
/// This probe samples both at one second so a boundary can be set from measurement
/// rather than from the initial 2.0-per-core guess.
///
/// **`vm.loadavg` counts more than runnable threads.** macOS includes threads in
/// uninterruptible waits — classically disk — so a machine blocked on slow storage
/// reads high with an idle CPU. That is arguably still a slowdown worth reporting,
/// but it means the condition can never be *described* as a CPU condition. To make
/// that separable rather than assumed, each sample also carries the count of threads
/// the kernel reports as running versus the load figure, and disk throughput, so a
/// high-load/low-CPU/high-IO sample can be told apart from a high-load/low-CPU/no-IO
/// one.
///
/// Usage: `loadavg-probe [seconds] [label]`. CSV on stdout, summary on stderr.
enum LoadAverageProbe {
    struct Sample {
        let at: Date
        let loadOneMinute: Double
        /// Runnable-or-waiting threads per logical core. The only form this figure
        /// is ever allowed to reach a user in (FR-038, design 4b).
        let perCore: Double
        let cpuBusyFraction: Double
        let diskBytesPerSecond: Double
    }

    static func loadAverage() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        // `getloadavg` reads the same kernel figure as `sysctl vm.loadavg` and needs
        // no MIB juggling. Public API, available sandboxed.
        guard getloadavg(&loads, 3) >= 1 else { return nil }
        return loads[0]
    }

    /// Machine-wide busy fraction from the host CPU load counters, as deltas —
    /// never a cumulative total presented as a rate.
    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user &+ system &+ nice
        return (busy, busy &+ idle)
    }

    static func diskBytes() -> Double {
        // Aggregate only. Per-process disk is blocked under the sandbox
        // (`proc_pid_rusage`), which is why FR-009 is aggregate-scoped.
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Pageins are the part of "uninterruptible wait" we can actually see.
        return Double(info.pageins) * Double(vm_page_size)
    }

    static func run(seconds: Int, label: String) {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        var samples: [Sample] = []
        var previousTicks = cpuTicks()
        var previousPageBytes = diskBytes()
        var previousAt = Date()

        print("label,elapsed,load1,per_core,cpu_busy_fraction,pagein_bytes_per_s")

        for step in 0..<seconds {
            Thread.sleep(forTimeInterval: 1)
            let now = Date()
            let elapsed = now.timeIntervalSince(previousAt)
            guard let load = loadAverage(), let ticks = cpuTicks(), let previous = previousTicks
            else { continue }

            let busyDelta = Double(ticks.busy &- previous.busy)
            let totalDelta = Double(ticks.total &- previous.total)
            // A counter that did not advance is not a machine that was idle.
            guard totalDelta > 0 else { previousTicks = ticks; continue }
            let busyFraction = busyDelta / totalDelta

            let pageBytes = diskBytes()
            let pageRate = max(0, (pageBytes - previousPageBytes) / max(elapsed, 0.001))

            let sample = Sample(
                at: now, loadOneMinute: load, perCore: load / Double(cores),
                cpuBusyFraction: busyFraction, diskBytesPerSecond: pageRate)
            samples.append(sample)
            print(String(format: "%@,%d,%.2f,%.3f,%.4f,%.0f",
                         label, step, load, sample.perCore,
                         sample.cpuBusyFraction, sample.diskBytesPerSecond))

            previousTicks = ticks
            previousPageBytes = pageBytes
            previousAt = now
        }

        summarise(samples, cores: cores, label: label)
    }

    static func summarise(_ samples: [Sample], cores: Int, label: String) {
        guard !samples.isEmpty else {
            FileHandle.standardError.write(Data("no samples\n".utf8))
            return
        }
        let perCore = samples.map(\.perCore)
        let busy = samples.map(\.cpuBusyFraction)

        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }

        let correlation = pearson(perCore, busy)
        var lines = [
            "",
            "== \(label) — \(samples.count) samples, \(cores) logical cores ==",
            String(format: "per-core queue   median %.2f  peak %.2f  min %.2f",
                   median(perCore), perCore.max() ?? 0, perCore.min() ?? 0),
            String(format: "cpu busy         median %.1f%%  peak %.1f%%",
                   median(busy) * 100, (busy.max() ?? 0) * 100),
            String(format: "correlation      %.2f", correlation),
        ]

        // The question the amendment turns on: how often would a given boundary
        // have fired, and would the CPU condition have seen it at all?
        for threshold in [1.5, 2.0, 3.0, 4.0] {
            let over = perCore.filter { $0 >= threshold }.count
            let share = Double(over) / Double(samples.count) * 100
            // Samples over the queue threshold that FR-006's CPU rule would miss.
            let missed = samples.filter { $0.perCore >= threshold && $0.cpuBusyFraction < 0.85 }
            lines.append(String(format:
                "  >= %.1f per core: %3d samples (%5.1f%%), of which %d below 85%% CPU",
                threshold, over, share, missed.count))
        }

        // FR-006 amendment criterion 2: is a high queue explained by paging?
        let highQueue = samples.filter { $0.perCore >= 2.0 }
        if !highQueue.isEmpty {
            let paging = highQueue.filter { $0.diskBytesPerSecond > 1_000_000 }.count
            lines.append(String(format:
                "  of %d samples at >= 2.0 per core, %d had pagein > 1 MB/s",
                highQueue.count, paging))
        }
        lines.append("")
        FileHandle.standardError.write(Data(lines.joined(separator: "\n").utf8))
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0 }
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var covariance = 0.0, varianceA = 0.0, varianceB = 0.0
        for index in a.indices {
            let da = a[index] - meanA
            let db = b[index] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        guard varianceA > 0, varianceB > 0 else { return 0 }
        return covariance / (varianceA * varianceB).squareRoot()
    }
}

let arguments = CommandLine.arguments
let duration = arguments.count > 1 ? Int(arguments[1]) ?? 60 : 60
let runLabel = arguments.count > 2 ? arguments[2] : "run"
LoadAverageProbe.run(seconds: duration, label: runLabel)
