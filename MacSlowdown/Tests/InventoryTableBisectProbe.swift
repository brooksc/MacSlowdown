import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-67 bisection. Diagnostic, not a guard.
///
/// The reproduction in `InventoryTableReentrancyTests` shows the warning but not
/// its cause. These variants strip the inventory table back one construct at a
/// time against the same live store, so the run that stops warning names the thing
/// that reenters. Each is deliberately as close to the shipping view as it can be
/// while differing in exactly one respect.

// MARK: - Variants

/// The plainest possible table over the same rows: no disclosure, no icons, no
/// footer, no inspector, no recording. If this warns, nothing we wrote is at fault.
struct BisectFlatTable: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(store.inventory, by: sortOrder)) { TableRow($0) }
        }
    }
}

/// Flat table plus the disclosure rows (TASK-61).
struct BisectDisclosureTable: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var expanded: Set<InventoryRow.ID> = []
    @State private var sortOrder = Presentation.defaultInventorySort

    private func expansion(for id: InventoryRow.ID) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { isExpanded in
                    if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
                })
    }

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(store.inventory, by: sortOrder)) { row in
                if row.hasChildren {
                    DisclosureTableRow(row, isExpanded: expansion(for: row.id)) {
                        ForEach(row.children) { TableRow($0) }
                    }
                } else {
                    TableRow(row)
                }
            }
        }
    }
}

/// Flat table whose cells ask the store for an icon, which is the one thing a cell
/// body does that touches shared state (TASK-65.18, TASK-55.1).
struct BisectIconTable: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack {
                    if let icon = store.icon(forExecutablePath: row.executablePath) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(row.name)
                }
            }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(store.inventory, by: sortOrder)) { TableRow($0) }
        }
    }
}

/// Flat table plus the bottom safe-area inset the shipping view carries.
struct BisectFooterTable: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(store.inventory, by: sortOrder)) { TableRow($0) }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading) {
                Text(InventoryCensus.of(store.families).summary)
                Text(InventoryCensus.freshness(lastUpdate: store.lastUpdate))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
    }
}

/// Flat table plus the per-family history recording added by TASK-65.4: an
/// `onChange` that writes to a second observable object on every sample.
struct BisectRecordingTable: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort
    @State private var history = FamilyHistory()

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(store.inventory, by: sortOrder)) { TableRow($0) }
        }
        .onChange(of: store.lastUpdate) { _, _ in
            history.record(rows: store.inventory, families: store.families, selected: selection)
        }
    }
}

/// Flat table wrapped in `.searchable`, which is what puts a search field in the
/// same hierarchy as the table.
struct BisectSearchableTable: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort
    @State private var query = ""

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(store.inventory, by: sortOrder)) { TableRow($0) }
        }
        .searchable(text: $query, prompt: "Search")
    }
}

/// A table over a *fixed* row set that never changes, to separate "a table exists"
/// from "a table whose contents are replaced every sample".
struct BisectStaticTable: View {
    let rows: [InventoryRow]
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(rows, by: sortOrder)) { TableRow($0) }
        }
    }
}

/// Changing data, but no `sortOrder` binding. TASK-63 established that SwiftUI
/// writes back to a `Table`'s `sortOrder` during layout; if that write is what
/// reenters, this variant stops warning.
struct BisectNoSortBinding: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(store.inventory) { TableRow($0) }
        }
    }
}

/// Changing data, no selection binding, no sort binding: a `Table` with no writable
/// binding of any kind. If this still warns, nothing about our bindings is at fault.
struct BisectNoBindings: View {
    let store: MonitorStore

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(store.inventory) { TableRow($0) }
        }
    }
}

/// A new array instance every update carrying identical rows: the identity set and
/// every value are unchanged, only the array is fresh. Separates "the Table is
/// handed new data" from "the Table's rows actually differ".
struct BisectSameRowsNewArray: View {
    let store: MonitorStore
    let rows: [InventoryRow]

    var body: some View {
        // Reading `lastUpdate` is what makes this re-evaluate on every sample.
        let _ = store.lastUpdate
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Array(rows)) { TableRow($0) }
        }
    }
}

/// A constant identity set with changing values: no row is ever inserted or
/// removed, but every row's numbers move. Separates "rows come and go" from "row
/// contents change".
struct BisectStableIdentities: View {
    let store: MonitorStore
    let ids: [InventoryRow.ID]

    private var rows: [InventoryRow] {
        let current = Dictionary(store.inventory.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        return ids.compactMap { current[$0] }
    }

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
    }
}

/// Changing data, but only a handful of rows. If a short table does not warn, row
/// count is part of the trigger.
struct BisectSmallTable: View {
    let store: MonitorStore

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Array(store.inventory.prefix(15))) { TableRow($0) }
        }
    }
}

/// Rows re-sorted every sample so their *order* churns, but with no `sortOrder`
/// binding and no sortable columns. Isolates reordering from the binding.
struct BisectReorderOnly: View {
    let store: MonitorStore

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(
                store.inventory, by: Presentation.defaultInventorySort)) { TableRow($0) }
        }
    }
}

/// The `sortOrder` binding and sortable columns, but rows handed over in the
/// store's own order and never re-sorted. Isolates the binding from reordering.
struct BisectSortBindingUnsortedRows: View {
    let store: MonitorStore
    @State private var selection: InventoryRow.ID?
    @State private var sortOrder = Presentation.defaultInventorySort

    var body: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { Text($0.name) }
            TableColumn("CPU", value: \.cpuSortKey) { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(store.inventory) { TableRow($0) }
        }
    }
}

/// Reordering rows with animation switched off. If the reentrancy is the animated
/// row-move AppKit performs when `ForEach`'s identities change position, this stops
/// warning while still reordering.
struct BisectReorderNoAnimation: View {
    let store: MonitorStore

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(
                store.inventory, by: Presentation.defaultInventorySort)) { TableRow($0) }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

/// Reordering through the data-driven initialiser rather than the `rows` builder,
/// in case the two take different paths into `NSTableView`.
struct BisectReorderDataInit: View {
    let store: MonitorStore

    var body: some View {
        Table(Presentation.sortedInventory(
            store.inventory, by: Presentation.defaultInventorySort)) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        }
    }
}

/// Fifteen rows, reordered every sample. Separates "many rows" from "rows move".
struct BisectSmallReordered: View {
    let store: MonitorStore

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Array(Presentation.sortedInventory(
                store.inventory, by: Presentation.defaultInventorySort).prefix(15))) {
                TableRow($0)
            }
        }
    }
}

/// The All processes scope (TASK-65.13): a second `Table` of the same shape, which
/// the task asks to be checked separately.
struct BisectAllProcessesScope: View {
    let store: MonitorStore
    @State private var query = ""
    @State private var showsUnmeasurable = true
    @State private var sortOrder = AllProcesses.defaultSort

    private var contributions: [ProcessIdentity: Double] {
        Dictionary((store.attribution?.contributors ?? [])
            .map { ($0.identity, $0.percentOfOneCore) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let rows = AllProcesses.rows(store.families, contributions: contributions)
        AllProcessesView(
            rows: rows, census: AllProcesses.census(rows),
            freshness: InventoryCensus.freshness(lastUpdate: store.lastUpdate),
            query: $query, showsUnmeasurable: $showsUnmeasurable, sortOrder: $sortOrder,
            icon: { store.icon(forExecutablePath: $0) })
    }
}

/// The control that isolates order and nothing else: one frozen array of rows,
/// rotated by one position on each sample. Identities, values and count are all
/// identical between updates; only the order differs.
struct BisectRotatingRows: View {
    let store: MonitorStore
    let rows: [InventoryRow]

    var body: some View {
        let tick = store.lastUpdate.map { Int($0.timeIntervalSince1970) } ?? 0
        let offset = rows.isEmpty ? 0 : tick % rows.count
        let rotated = Array(rows[offset...] + rows[..<offset])
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(rotated) { TableRow($0) }
        }
    }
}

/// Frozen rows shuffled anew on every sample: identical identities and identical
/// values, but every row lands somewhere different. A rotation by one position moves
/// only one row, which turned out to be too small a change to tell us anything.
struct BisectShuffledRows: View {
    let store: MonitorStore
    let rows: [InventoryRow]

    var body: some View {
        let tick = store.lastUpdate.map { UInt64($0.timeIntervalSince1970) } ?? 0
        var generator = SeededGenerator(seed: tick)
        let shuffled = rows.shuffled(using: &generator)
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(shuffled) { TableRow($0) }
        }
    }
}

/// A fixed identity set — nothing is ever inserted or removed — carrying live
/// values and sorted busiest-first, so the order churns with the machine. Separates
/// reordering from insertion and removal.
struct BisectSortedFixedSet: View {
    let store: MonitorStore
    let ids: Set<InventoryRow.ID>

    var body: some View {
        let rows = store.inventory.filter { ids.contains($0.id) }
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            ForEach(Presentation.sortedInventory(
                rows, by: Presentation.defaultInventorySort)) { TableRow($0) }
        }
    }
}

/// Deterministic, so a run can be repeated.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Reordering rows that are wrapped in a `Section`.
///
/// The All processes table reorders as heavily as the Apps table — measured at
/// 517 of 718 rows moving in three seconds — and never warns. The one structural
/// difference between the two rows builders is that its unmeasurable rows sit in a
/// `Section`. This asks whether that is what changes the update path.
struct BisectReorderInSection: View {
    let store: MonitorStore

    var body: some View {
        Table(of: InventoryRow.self) {
            TableColumn("Name") { Text($0.name) }
            TableColumn("CPU") { Text("\($0.percentOfOneCore)") }
        } rows: {
            Section {
                ForEach(Presentation.sortedInventory(
                    store.inventory, by: Presentation.defaultInventorySort)) { TableRow($0) }
            }
        }
    }
}

/// The All processes data, reordered, with its `Section` removed. The other half of
/// the same question: if this starts warning, the `Section` is what was protecting it.
struct BisectAllProcessesNoSection: View {
    let store: MonitorStore

    var body: some View {
        let rows = AllProcesses.rows(store.families, contributions: liveContributions(store))
        Table(of: AllProcessesRow.self) {
            TableColumn("Process") { Text($0.name) }
            TableColumn("CPU") { Text($0.cpuText) }
        } rows: {
            ForEach(AllProcesses.sorted(rows, by: AllProcesses.defaultSort)) { TableRow($0) }
        }
    }
}

/// The mirror of `BisectShuffledRows`, over `AllProcessesRow`.
///
/// The All processes table never warns in normal operation. This asks whether that
/// is something about the row type, or simply that its ordering — where the great
/// majority of rows tie at zero CPU and are held in place by the name tie-break —
/// does not really move much. If this warns, the row type is not the difference.
struct BisectShuffledAllProcesses: View {
    let store: MonitorStore
    let rows: [AllProcessesRow]

    var body: some View {
        let tick = store.lastUpdate.map { UInt64($0.timeIntervalSince1970) } ?? 0
        var generator = SeededGenerator(seed: tick)
        let shuffled = rows.shuffled(using: &generator)
        Table(of: AllProcessesRow.self) {
            TableColumn("Process") { Text($0.name) }
            TableColumn("CPU") { Text($0.cpuText) }
        } rows: {
            ForEach(shuffled) { TableRow($0) }
        }
    }
}

/// How many rows changed position *relative to each other* between two orderings.
///
/// Restricted to the ids present in both, and compared by rank within that common
/// subsequence rather than by absolute index. Absolute index is the wrong measure
/// and was used first: one process appearing near the top shifts every row below it
/// by one, which reported ~700 of 721 rows as "moved" when their relative order was
/// untouched. That artefact made the two scopes look identical when they are not.
func reorderedRows(_ before: [String], _ after: [String]) -> Int {
    let common = Set(before).intersection(after)
    let beforeRanks = before.filter { common.contains($0) }
    let afterRanks = after.filter { common.contains($0) }
    let afterIndex = Dictionary(afterRanks.enumerated().map { ($0.element, $0.offset) },
                                uniquingKeysWith: { first, _ in first })
    return beforeRanks.enumerated().reduce(0) { count, pair in
        count + (afterIndex[pair.element] == pair.offset ? 0 : 1)
    }
}

@MainActor
func liveContributions(_ store: MonitorStore) -> [ProcessIdentity: Double] {
    Dictionary((store.attribution?.contributors ?? [])
        .map { ($0.identity, $0.percentOfOneCore) }, uniquingKeysWith: { first, _ in first })
}

/// These probes drive the real sampler and the real views for minutes at a time, so
/// they are off unless asked for. Run them with:
///
///     TASK67_PROBE=1 xcodebuild test ... \
///       -only-testing:MacSlowdownTests/InventoryTableBisectProbe
///
/// Kept in the tree rather than deleted because TASK-67's conclusion rests entirely
/// on what they measure, and a conclusion nobody can re-measure is an opinion.
var task67ProbeEnabled: Bool {
    ProcessInfo.processInfo.environment["TASK67_PROBE"] != nil
}

// MARK: - The bisection

@MainActor
@Suite("Inventory table reentrancy bisection (TASK-67, diagnostic)")
struct InventoryTableBisectProbe {
    /// Runs every variant against one live store and prints how many times each
    /// drew the warning. Always passes: this reports, it does not judge.
    @Test("Which construct reenters", .enabled(if: task67ProbeEnabled),
          .timeLimit(.minutes(10)))
    func bisect() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        // Let two samples land so every variant starts with a populated table.
        try? await Task.sleep(for: .seconds(4))
        let frozen = store.inventory

        var report: [String] = ["rows=\(frozen.count)"]

        func measure(_ name: String, _ view: some View) async {
            var run = HarnessRun()
            let output = await capturingStandardError {
                run = await liveOffscreen(view, seconds: 8)
            }
            let hits = output.split(separator: "\n").filter {
                $0.contains("reentrant operation in its NSTableView delegate")
            }.count
            report.append("\(name): warnings=\(hits) \(run.description)")
        }

        await measure("flat", BisectFlatTable(store: store))
        await measure("static", BisectStaticTable(rows: frozen))
        await measure("disclosure", BisectDisclosureTable(store: store))
        await measure("icons", BisectIconTable(store: store))
        await measure("footer", BisectFooterTable(store: store))
        await measure("recording", BisectRecordingTable(store: store))
        await measure("searchable", BisectSearchableTable(store: store))
        await measure("noSortBinding", BisectNoSortBinding(store: store))
        await measure("noBindings", BisectNoBindings(store: store))
        await measure("sameRowsNewArray", BisectSameRowsNewArray(store: store, rows: frozen))
        await measure("stableIdentities",
                      BisectStableIdentities(store: store, ids: frozen.map(\.id)))
        await measure("small", BisectSmallTable(store: store))
        await measure("reorderOnly", BisectReorderOnly(store: store))
        await measure("smallReordered", BisectSmallReordered(store: store))
        await measure("allProcessesScope", BisectAllProcessesScope(store: store))
        await measure("reorderNoAnimation", BisectReorderNoAnimation(store: store))
        await measure("reorderDataInit", BisectReorderDataInit(store: store))
        await measure("sortBindingUnsortedRows", BisectSortBindingUnsortedRows(store: store))
        await measure("shipping", ProcessInventoryView(store: store))

        print("TASK67-BISECT\n" + report.joined(separator: "\n"))
    }

    /// Cheap and decisive: are the two lists' row identities unique?
    ///
    /// A `ForEach` over duplicated identities is a classic way to make AppKit
    /// misbehave, and it would make this our bug rather than SwiftUI's. Costs one
    /// sample rather than the three and a half minutes the render probes take.
    @Test("Row identities are unique in both scopes", .enabled(if: task67ProbeEnabled),
          .timeLimit(.minutes(2)))
    func identitiesAreUnique() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        try? await Task.sleep(for: .seconds(5))

        let apps = store.inventory
        let all = AllProcesses.rows(store.families, contributions: liveContributions(store))
        let appIDs = apps.map(\.id)
        let allIDs = all.map(\.id)
        let appDuplicates = appIDs.count - Set(appIDs).count
        let allDuplicates = allIDs.count - Set(allIDs).count
        // Children matter too: the Table flattens them into the same row space.
        let childIDs = apps.flatMap { $0.children.map(\.id) }
        let everyAppID = appIDs + childIDs
        let flattenedDuplicates = everyAppID.count - Set(everyAppID).count

        print("TASK67-IDS apps=\(appIDs.count) appDuplicates=\(appDuplicates) "
              + "flattened=\(everyAppID.count) flattenedDuplicates=\(flattenedDuplicates) "
              + "all=\(allIDs.count) allDuplicates=\(allDuplicates)")

        #expect(appDuplicates == 0, Comment(rawValue: "apps duplicates=\(appDuplicates)"))
        #expect(flattenedDuplicates == 0,
                Comment(rawValue: "flattened duplicates=\(flattenedDuplicates)"))
        #expect(allDuplicates == 0, Comment(rawValue: "all duplicates=\(allDuplicates)"))

        // The number that explains the difference between the two scopes: how many
        // rows swap rank with each other from one sample to the next.
        var appsChurn: [Int] = []
        var allChurn: [Int] = []
        var appsPrevious = Presentation.sortedInventory(
            apps, by: Presentation.defaultInventorySort).map(\.id)
        var allPrevious = AllProcesses.sorted(all, by: AllProcesses.defaultSort).map(\.id)
        for _ in 0..<5 {
            try? await Task.sleep(for: .seconds(2))
            let appsNow = Presentation.sortedInventory(
                store.inventory, by: Presentation.defaultInventorySort).map(\.id)
            let allNow = AllProcesses.sorted(
                AllProcesses.rows(store.families, contributions: liveContributions(store)),
                by: AllProcesses.defaultSort).map(\.id)
            appsChurn.append(reorderedRows(appsPrevious, appsNow))
            allChurn.append(reorderedRows(allPrevious, allNow))
            appsPrevious = appsNow
            allPrevious = allNow
        }
        print("TASK67-CHURN appsReordered=\(appsChurn) of ~\(appIDs.count) "
              + "allReordered=\(allChurn) of ~\(allIDs.count)")
    }

    /// The focused confirmation: order-only churn, and a longer look at both of the
    /// app's real tables. Twenty-five seconds each rather than eight, because a
    /// single short window that happens to see no row move proves nothing.
    @Test("Order alone, and both shipping tables, over a longer window",
          .enabled(if: task67ProbeEnabled), .timeLimit(.minutes(10)))
    func focused() async {
        let store = MonitorStore(cadence: .seconds(1), history: MetricsHistory())
        store.start()
        defer { store.stop() }
        try? await Task.sleep(for: .seconds(4))
        let frozen = store.inventory

        var report: [String] = ["rows=\(frozen.count)"]

        func measure(_ name: String, _ view: some View) async {
            var run = HarnessRun()
            let output = await capturingStandardError {
                run = await liveOffscreen(view, seconds: 25)
            }
            let hits = output.split(separator: "\n").filter {
                $0.contains("reentrant operation in its NSTableView delegate")
            }.count
            report.append("\(name): warnings=\(hits) \(run.description)")
        }

        // The quantity that separates the two scopes: how many rows change position
        // between two consecutive samples of each list, sorted the way it ships.
        let appsBefore = Presentation.sortedInventory(
            store.inventory, by: Presentation.defaultInventorySort).map(\.id)
        let allBefore = AllProcesses.sorted(
            AllProcesses.rows(store.families, contributions: liveContributions(store)),
            by: AllProcesses.defaultSort).map(\.id)
        try? await Task.sleep(for: .seconds(3))
        let appsAfter = Presentation.sortedInventory(
            store.inventory, by: Presentation.defaultInventorySort).map(\.id)
        let allAfter = AllProcesses.sorted(
            AllProcesses.rows(store.families, contributions: liveContributions(store)),
            by: AllProcesses.defaultSort).map(\.id)
        report.append("appsReordered=\(reorderedRows(appsBefore, appsAfter))/\(appsBefore.count)")
        report.append("allReordered=\(reorderedRows(allBefore, allAfter))/\(allBefore.count)")

        await measure("shuffledOrderOnly", BisectShuffledRows(store: store, rows: frozen))
        await measure("shuffledAllProcesses", BisectShuffledAllProcesses(
            store: store,
            rows: AllProcesses.rows(store.families, contributions: liveContributions(store))))
        await measure("frozenOrder", BisectStaticTable(rows: frozen))
        await measure("appsScope", ProcessInventoryView(store: store))
        await measure("allProcessesScope", BisectAllProcessesScope(store: store))

        print("TASK67-FOCUSED\n" + report.joined(separator: "\n"))
    }
}
