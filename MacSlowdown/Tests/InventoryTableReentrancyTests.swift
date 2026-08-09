import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-67: AppKit logs "reentrant operation in its NSTableView delegate" every
/// ~2 s, and says it will become an assert.
///
/// The warning cannot be seen without running the table, so this harness runs it:
/// the real view, offscreen, driven by the real sampling loop, with the process's
/// standard error captured across several sampling cycles. AppKit emits this class
/// of warning through `NSLog`, which lands on fd 2, so a pipe over fd 2 catches it
/// without touching the log system.
///
/// Traps this shares with `IncidentsViewRenderTests`, both of which were hit while
/// writing it:
///
/// - The view must be in a real `NSWindow` or SwiftUI never builds the underlying
///   `NSTableView` at all, and the harness reports a clean run because nothing ran.
/// - The run loop has to be spun for real time. Swift concurrency's main executor
///   drains on the main run loop, so without `RunLoop.run(until:)` the sampling
///   task never gets a turn and the table is only ever laid out once.
///
/// Nothing here is a screenshot and nothing here needs the screen: the window is
/// never made key, ordered front, or made visible.

// MARK: - Capturing what AppKit writes

/// Runs `body` with fd 2 redirected to a pipe and returns everything written.
///
/// Reads on a background thread rather than after the fact: a pipe holds 64 KB, and
/// a run that fills it would deadlock the thing being measured, which would look
/// exactly like a hang in the view under test.
@MainActor
func capturingStandardError(_ body: () async -> Void) async -> String {
    let original = dup(STDERR_FILENO)
    let pipe = Pipe()
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

    let collected = Collector()
    let reader = Thread {
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)
        }
    }
    reader.start()

    await body()

    fflush(stderr)
    dup2(original, STDERR_FILENO)
    close(original)
    try? pipe.fileHandleForWriting.close()
    while !reader.isFinished { usleep(2000) }
    return collected.text
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Hosting the real view

/// What the harness observed while the view was alive. Reported alongside every
/// result: a run that saw no table, or a table that never changed shape, proves
/// nothing about reentrancy however clean its log is.
struct HarnessRun {
    var tableViewsFound = 0
    var rowCountSamples: [Int] = []
    var distinctRowCounts: Int { Set(rowCountSamples).count }
    var maxRows: Int { rowCountSamples.max() ?? 0 }
    var layoutPasses = 0

    var description: String {
        "tables=\(tableViewsFound) layouts=\(layoutPasses) maxRows=\(maxRows) "
            + "distinctRowCounts=\(distinctRowCounts) samples=\(rowCountSamples.count)"
    }
}

@MainActor
func tableViews(in view: NSView) -> [NSTableView] {
    var found: [NSTableView] = []
    if let table = view as? NSTableView { found.append(table) }
    for subview in view.subviews { found.append(contentsOf: tableViews(in: subview)) }
    return found
}

/// Lays `view` out in an offscreen window and lets it live for `seconds`, so the
/// sampling loop delivers several updates into a table that is really there.
///
/// `each` runs once per pass with the tables the hierarchy currently holds, which
/// is how a test drives selection through the real `NSTableView` rather than
/// through a binding the production view does not expose.
@MainActor
@discardableResult
func liveOffscreen<V: View>(
    _ view: V, seconds: TimeInterval,
    size: CGSize = CGSize(width: 1200, height: 800),
    each: (Int, [NSTableView]) -> Void = { _, _ in }
) async -> HarnessRun {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.titled, .resizable],
        backing: .buffered, defer: true)
    window.contentView = host
    defer { window.contentView = nil }

    var run = HarnessRun()
    host.layoutSubtreeIfNeeded()
    let deadline = Date().addingTimeInterval(seconds)
    var pass = 0
    while Date() < deadline {
        // `await` rather than a nested `RunLoop.run(until:)`. The nested run loop
        // looked equivalent and was not: the store's sampling task never got a turn,
        // so the table it was supposedly exercising held zero rows for the whole run
        // and reported a clean log for the simple reason that nothing happened.
        try? await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        // Draw as well as lay out: the delegate callbacks that build cell views
        // fire during display, and a harness that only measures layout would miss
        // the half of the work the warning comes from.
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        let tables = tableViews(in: host)
        run.tableViewsFound = max(run.tableViewsFound, tables.count)
        if let first = tables.first { run.rowCountSamples.append(first.numberOfRows) }
        run.layoutPasses += 1
        each(pass, tables)
        pass += 1
    }
    return run
}

/// What AppKit calls this. Matched loosely because the wording has changed across
/// releases and the point is to notice it at all.
func reentrantLines(_ output: String) -> [String] {
    output.split(separator: "\n").map(String.init).filter {
        $0.lowercased().contains("reentrant")
    }
}

// MARK: - Tests

@MainActor
@Suite("Inventory table reentrancy (TASK-67)")
struct InventoryTableReentrancyTests {
    /// Guards the capture itself. If this fails, a clean result from any other test
    /// in this suite means only that nothing was being read.
    @Test("The harness captures what is written to standard error")
    func harnessCapturesStandardError() async {
        let output = await capturingStandardError {
            FileHandle.standardError.write(Data("a reentrant marker\n".utf8))
        }
        #expect(reentrantLines(output).count == 1, Comment(rawValue: "captured: " + output))
    }

    /// The harness has to build a real `NSTableView` and see it change, or a clean
    /// log means only that nothing was exercised. This is the guard on that.
    @Test("The harness drives a real NSTableView that updates",
          .enabled(if: task67ProbeEnabled), .timeLimit(.minutes(2)))
    func harnessDrivesARealTable() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        let run = await liveOffscreen(ProcessInventoryView(store: store), seconds: 12)
        print("TASK67-DIAG \(run.description) rows=\(run.rowCountSamples) "
              + "families=\(store.families.count) inventory=\(store.inventory.count) "
              + "enumeration=\(String(describing: store.enumeration.explanation))")
        #expect(run.tableViewsFound >= 1, Comment(rawValue: run.description))
        #expect(run.maxRows > 5, Comment(rawValue: run.description))
        #expect(run.distinctRowCounts > 1, Comment(rawValue: run.description))
    }

    /// The reproduction, recorded as what it currently is: a defect we did not fix.
    ///
    /// This asserts that the warning **is** emitted, which is the state of the world
    /// as measured. It is not an endorsement — it is so that whoever changes this
    /// next gets told. The test fails the day the Apps table stops reentering,
    /// whether that is because we replaced `Table` (option C in the task notes) or
    /// because Apple fixed it, and either way that is news worth a failing test.
    @Test("The inventory table still reenters, as TASK-67 recorded",
          .enabled(if: task67ProbeEnabled), .timeLimit(.minutes(2)))
    func inventoryScopeStillReenters() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        var run = HarnessRun()
        let output = await capturingStandardError {
            run = await liveOffscreen(ProcessInventoryView(store: store), seconds: 20) { pass, tables in
                guard let table = tables.first, table.numberOfRows > 2 else { return }
                // Select on one pass, move the selection on a later one: both the
                // appearance of the inspector and a change of selection while the
                // table is being updated.
                if pass == 40 { table.selectRowIndexes([1], byExtendingSelection: false) }
                if pass == 90 { table.selectRowIndexes([2], byExtendingSelection: false) }
            }
        }
        let lines = reentrantLines(output)
        #expect(!lines.isEmpty, Comment(rawValue:
            "The Apps table no longer reenters — TASK-67's finding is out of date. "
            + run.description))
    }
}
