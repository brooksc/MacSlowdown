import Darwin
import Foundation

// Which part of identity resolution costs the 819 ms? TASK-62 criterion #5.
//
// Compiled together with the framework sources rather than linking the built
// framework, because the three calls under test are internal. Making them public
// to satisfy a probe would widen the API for no product reason.
//
// Three candidates, timed separately over the same processes:
//   - proc_pidpath, which grouping cannot do without
//   - the code signature, which only decides confidence
//   - naming, which only decides what is displayed

@main
struct SplitProbe {
    static func time(_ label: String, count: Int, _ body: () -> Void) {
        let start = ContinuousClock().now
        body()
        let ms = (ContinuousClock().now - start).totalSeconds * 1000
        print(String(format: "  \(label.padding(toLength: 28, withPad: " ", startingAt: 0)) %8.1f ms total   %6.3f ms each", ms, ms / Double(count)))
    }

    static func main() {
        let snapshot = ProcessSampler().snapshot()
        let pids = snapshot.records.values.map(\.identity.pid)
        print("processes: \(pids.count)")
        print("")

        var paths: [String?] = []
        time("proc_pidpath", count: pids.count) {
            paths = pids.map { ProcessIdentityResolver.executablePath(pid: $0) }
        }
        time("code signature", count: pids.count) {
            for pid in pids { _ = ProcessIdentityResolver.codeSignature(pid: pid) }
        }
        time("naming", count: pids.count) {
            for (index, pid) in pids.enumerated() {
                _ = ProcessNaming.resolve(pid: pid, executablePath: paths[index])
            }
        }
        print("")
        time("all three together", count: pids.count) {
            for pid in pids { _ = ProcessIdentityResolver.resolve(pid: pid) }
        }

        // Naming splits again: Launch Services versus reading a plist.
        print("")
        print("naming, broken down:")
        time("NSRunningApplication only", count: pids.count) {
            for pid in pids { _ = ProcessNaming.runningApplicationName(pid: pid) }
        }
        let bundles = paths.compactMap { $0.flatMap(ProcessNaming.namingBundle(for:)) }
        time("Info.plist reads", count: max(bundles.count, 1)) {
            for bundle in bundles { _ = ProcessNaming.bundleName(atPath: bundle) }
        }
        print("  (\(bundles.count) processes live in a naming bundle)")
    }
}
