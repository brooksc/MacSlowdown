import AppKit
import SwiftUI
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-75: the main window grew to 1300 x 3599 points on a 1107-point screen.
///
/// ## Why the previous offscreen investigation was wrong, and this one is not
///
/// TASK-51.1 laid the view out in an `NSHostingView` **at a supplied size**, saw
/// the content clamp to that size, and concluded the hypothesis was dead. Of
/// course it clamped: the harness decided the height. That measurement could
/// never have detected the bug.
///
/// The question a window scene asks its content is not "can you fit in this?" but
/// "how big do you want to be?". `fittingSize` / `sizeThatFits(in:)` with an
/// unbounded height ask exactly that, and they are answerable offscreen. That is
/// the whole difference between this file and the earlier dead end.
///
/// The durable assertion is `demandedHeightDoesNotScaleWithRowCount`: a table of
/// 500 rows must demand no more height than a table of 20. Everything else here
/// is the measurement that established the cause.

/// What the content *asks* for, given a fixed width and no height constraint.
///
/// A window is created so SwiftUI has a real layout context, and is never made
/// key, ordered front or shown.
struct HeightDemand: CustomStringConvertible {
    /// What a window sized to its content view controller would become.
    /// `NSHostingController` publishes this when its sizing options ask it to, and
    /// AppKit resizes the window to match — this is the mechanism, not a proxy.
    var preferred: CGFloat
    /// The minimum the content will accept. AppKit turns this into
    /// `NSWindow.contentMinSize`, which is what makes a window spring back.
    var fitting: CGFloat
    var intrinsic: CGFloat

    /// The figure the assertions use.
    var demanded: CGFloat { max(preferred, max(fitting, intrinsic)) }

    var description: String {
        "preferred=\(preferred) fitting=\(fitting) intrinsic=\(intrinsic)"
    }
}

@MainActor
private func demandedSize(_ view: some View, width: CGFloat = 1300) -> HeightDemand {
    // A hosting *controller* is what a window scene uses, and the sizing options
    // are what make it answer the question rather than accept an answer. No window
    // is attached: attaching one and then tearing it down mid-layout aborts inside
    // AppKit's display cycle, and the numbers below do not need one.
    let controller = NSHostingController(rootView: view)
    controller.sizingOptions = [.preferredContentSize, .minSize, .intrinsicContentSize]
    controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 860)
    controller.view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    controller.view.layoutSubtreeIfNeeded()

    return HeightDemand(
        preferred: controller.preferredContentSize.height,
        fitting: controller.view.fittingSize.height,
        intrinsic: max(controller.view.intrinsicContentSize.height, 0))
}

/// Test output does not survive `xcodebuild`'s stdout handling for an app-hosted
/// bundle, and these numbers are the whole point of the file. They are appended to
/// `task75-window-sizing.txt` in the host app's temporary directory — inside its
/// sandbox container, which is the only place it may write.
private func record(_ line: String) {
    print(line)
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("task75-window-sizing.txt")
    let data = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

private func syntheticRows(_ count: Int, childrenEach: Int = 0) -> [InventoryRow] {
    (0..<count).map { index in
        InventoryRow(
            id: "row-\(index)", name: "Application \(index)",
            executablePath: nil, kind: .application,
            percentOfOneCore: Double(count - index), residentBytes: 4_000_000,
            isMeasurable: true, processCount: 1 + childrenEach, qualification: nil,
            children: (0..<childrenEach).map { child in
                InventoryRow(
                    id: "row-\(index)-\(child)", name: "Helper \(child)",
                    executablePath: nil, kind: .member,
                    percentOfOneCore: 1, residentBytes: 1_000_000,
                    isMeasurable: true, processCount: 1, qualification: nil,
                    children: [])
            })
    }
}

@MainActor
private struct TableHarness: View {
    let rows: [InventoryRow]
    /// Held, not rebuilt in `body`: a new store on every body evaluation would make
    /// the measurement about allocation churn rather than about layout.
    @State private var store = MonitorStore()
    @State private var selection: InventoryRow.ID?
    @State private var expanded: Set<InventoryRow.ID> = []
    @State private var sortOrder = Presentation.defaultInventorySort

    var body: some View {
        InventoryTable(
            store: store, rows: rows, selection: $selection,
            expanded: $expanded, sortOrder: $sortOrder)
    }
}

/// `MainWindowView` with its section selectable, so each detail pane can be put in
/// the real split-view composition. Otherwise identical to the shipping view.
@MainActor
private struct SplitHarness<Detail: View>: View {
    var sidebarFooter: (any View)?
    var columnWidth = true
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        NavigationSplitView {
            let list = List(MainWindowView.Section.allCases,
                            selection: .constant(MainWindowView.Section.apps)) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            if columnWidth {
                list.navigationSplitViewColumnWidth(min: 200, ideal: 220)
            } else {
                list
            }
        } detail: {
            detail()
        }
    }
}

/// The plainest possible SwiftUI `Table`, to separate the framework's own appetite
/// from anything this app added around it.
@MainActor
private struct BareTable: View {
    let rows: [InventoryRow]

    var body: some View {
        Table(rows) {
            TableColumn("Name", value: \.name)
        }
    }
}

/// Seven paragraphs of caption text under `fixedSize(vertical:)`, which is the
/// shape of the inventory's footer. Used to test the *mechanism* directly rather
/// than to assert anything about the shipping view.
@MainActor
private struct FooterReplica: View {
    let fixedVertically: Bool

    private static let lines = [
        "488 of 764 processes belong to an application. 276 do not.",
        "Some processes are owned by another user and cannot be measured.",
        "CPU is shown as a percentage of one core.",
        "This Mac has performance and efficiency cores, so a percentage of one "
            + "core is not a percentage of the machine.",
        "Resident memory. Activity Monitor's Memory column shows a different "
            + "measure (footprint), so the numbers will not match exactly.",
        "Per-app disk activity is not available to App Store apps.",
        "Click a column heading to sort, a triangle to see the individual "
            + "processes an application is running, or a row to inspect it.",
    ]

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 3) {
            ForEach(Self.lines, id: \.self) { Text($0) }
        }
        .font(.caption)
        if fixedVertically {
            stack.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        } else {
            stack.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
    }
}

@MainActor
@Suite("Window sizing (TASK-75)")
struct WindowSizingTests {
    /// Names the mechanism. A `safeAreaInset` of wrapping text that is fixed
    /// vertically answers an unwidthed ideal-size query with thousands of points;
    /// the same text without `fixedSize` does not. Always passes — it records.
    @Test("Wrapping text under fixedSize is what asks for the height")
    func footerMechanism() {
        record("TASK75 mechanism fixedSizeFooterAlone: "
               + "\(demandedSize(FooterReplica(fixedVertically: true)))")
        record("TASK75 mechanism splitTablePlusFixedFooter: "
               + "\(demandedSize(SplitHarness { BareTable(rows: syntheticRows(20)) .safeAreaInset(edge: .bottom) { FooterReplica(fixedVertically: true) } }))")
        record("TASK75 mechanism splitTablePlusLooseFooter: "
               + "\(demandedSize(SplitHarness { BareTable(rows: syntheticRows(20)).safeAreaInset(edge: .bottom) { FooterReplica(fixedVertically: false) } }))")
    }

    /// Diagnostic. Which construct in the window composition asks for the height?
    /// Always passes; it exists so the answer is on the record rather than argued.
    @Test("Which part of the window composition demands height",
          .timeLimit(.minutes(2)))
    func bisectComposition() async {
        let empty = MonitorStore()
        record("TASK75 bisect emptyMainWindow: \(demandedSize(MainWindowView(store: empty)))")
        record("TASK75 bisect splitPlain: "
               + "\(demandedSize(SplitHarness { Color.red.frame(height: 50) }))")
        record("TASK75 bisect splitNoColumnWidth: "
               + "\(demandedSize(SplitHarness(columnWidth: false) { Color.red.frame(height: 50) }))")
        record("TASK75 bisect splitApps: "
               + "\(demandedSize(SplitHarness { ProcessInventoryView(store: empty) }))")
        record("TASK75 bisect splitNow: "
               + "\(demandedSize(SplitHarness { NowView(store: empty) }))")
        record("TASK75 bisect splitIncidents: "
               + "\(demandedSize(SplitHarness { IncidentsView(store: empty) }))")
        record("TASK75 bisect splitStorage: "
               + "\(demandedSize(SplitHarness { StorageView(store: empty) }))")
        record("TASK75 bisect splitInventoryTable: "
               + "\(demandedSize(SplitHarness { TableHarness(rows: syntheticRows(20)) }))")
        record("TASK75 bisect splitBareTable: "
               + "\(demandedSize(SplitHarness { BareTable(rows: syntheticRows(20)) }))")
        record("TASK75 bisect splitSearchableText: "
               + "\(demandedSize(SplitHarness { Text("x").searchable(text: .constant("")) }))")
        record("TASK75 bisect splitList: "
               + "\(demandedSize(SplitHarness { List(0..<20, id: \.self) { Text("row \($0)") } }))")

        let live = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        live.start()
        defer { live.stop() }
        try? await Task.sleep(for: .seconds(4))
        record("TASK75 bisect liveRows=\(live.inventory.count)")
        record("TASK75 bisect liveSplitApps: "
               + "\(demandedSize(SplitHarness { ProcessInventoryView(store: live) }))")
        record("TASK75 bisect liveSplitNow: "
               + "\(demandedSize(SplitHarness { NowView(store: live) }))")
        record("TASK75 bisect liveSplitPlain: "
               + "\(demandedSize(SplitHarness { Color.red.frame(height: 50) }))")
        record("TASK75 bisect liveMainWindow: \(demandedSize(MainWindowView(store: live)))")
        record("TASK75 bisect liveTable: \(demandedSize(TableHarness(rows: live.inventory)))")
    }

    /// Guards the harness. If a view whose height genuinely grows with its content
    /// does not report a growing demand here, every other result in this file is
    /// worthless — which is precisely the failure mode of the earlier attempt.
    @Test("The harness can detect a height demand that scales")
    func harnessDetectsScaling() {
        func stack(_ count: Int) -> some View {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in Color.red.frame(height: 20) }
            }
        }
        let small = demandedSize(stack(20))
        let large = demandedSize(stack(500))
        record("TASK75 control: 20 rows \(small) | 500 rows \(large)")
        #expect(large.demanded > small.demanded * 5,
                "small=\(small) large=\(large)")
    }

    /// The regression. Before the fix this measured 20 rows at ~500 pt and 500 rows
    /// at several thousand; the numbers are recorded on TASK-75.
    @Test("The inventory table's demanded height does not scale with row count")
    func demandedHeightDoesNotScaleWithRowCount() {
        let small = demandedSize(TableHarness(rows: syntheticRows(20)))
        let large = demandedSize(TableHarness(rows: syntheticRows(500)))
        let nested = demandedSize(TableHarness(rows: syntheticRows(140, childrenEach: 4)))
        record("TASK75 table: 20 rows \(small) | 500 rows \(large) "
               + "| 140x4 \(nested)")
        #expect(abs(large.demanded - small.demanded) < 20,
                "20 rows demanded \(small), 500 rows demanded \(large)")
        // Belt and braces: whatever it demands must fit on a laptop display, which
        // is the property a user actually cares about.
        #expect(large.demanded < 900, "500 rows demanded \(large)")
    }

    /// Diagnostic, not a guard: the real machine's process table through the real
    /// window composition, which is the only arrangement the symptom was ever seen
    /// in. Always passes; it exists so the numbers are on the record.
    @Test("What the live window composition demands", .timeLimit(.minutes(2)))
    func liveComposition() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        try? await Task.sleep(for: .seconds(4))

        let rows = store.inventory
        record("TASK75 live: families=\(store.families.count) topLevelRows=\(rows.count) "
               + "totalRows=\(rows.reduce(0) { $0 + 1 + $1.children.count })")
        record("TASK75 live table: \(demandedSize(TableHarness(rows: rows)))")
        record("TASK75 live pane: \(demandedSize(ProcessInventoryView(store: store)))")
        record("TASK75 live window: \(demandedSize(MainWindowView(store: store)))")
    }

    /// The same question of the whole detail pane, which is what the window scene
    /// hosts. `MonitorStore()` has no families, so this exercises the empty case;
    /// the row-count assertion above is the one with teeth.
    @Test("The whole Apps & Processes pane demands a bounded height")
    func panelDemandsBoundedHeight() {
        let demand = demandedSize(ProcessInventoryView(store: MonitorStore()))
        record("TASK75 pane: \(demand)")
        #expect(demand.demanded < 900, "pane demanded \(demand)")
    }

    /// The whole window, which is what the scene hosts and what actually grew.
    /// Driven from the live process table, because that is the only condition the
    /// symptom was ever reported under.
    @Test("The whole main window demands a height that fits on a laptop screen",
          .timeLimit(.minutes(2)))
    func mainWindowIsBounded() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        try? await Task.sleep(for: .seconds(4))
        let demand = demandedSize(MainWindowView(store: store))
        record("TASK75 mainWindow rows=\(store.inventory.count): \(demand)")
        #expect(demand.demanded < 900, "main window demanded \(demand)")
    }

    /// Every detail pane, since the window adopts whichever is selected.
    @Test("No detail pane demands more height than a laptop screen")
    func everyPaneIsBounded() {
        let store = MonitorStore()
        let heights: [(String, HeightDemand)] = [
            // The window now opens on this one, so it is the pane most able to
            // reproduce TASK-75 — and it is built from wrapping caption paragraphs
            // under `fixedSize`, which is the exact construct that asked for 3599 pt.
            ("Overview", demandedSize(OverviewView(store: store))),
            ("Now", demandedSize(NowView(store: store))),
            ("Apps", demandedSize(ProcessInventoryView(store: store))),
            ("Incidents", demandedSize(IncidentsView(store: store))),
            ("Storage", demandedSize(StorageView(store: store))),
        ]
        for (name, demand) in heights {
            record("TASK75 pane \(name): \(demand)")
            #expect(demand.demanded < 900, "\(name) demanded \(demand)")
        }
    }
}
