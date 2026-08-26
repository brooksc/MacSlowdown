import Metrics
import SwiftUI

/// Current inventory of applications and processes (FR-002), with search (FR-027),
/// per-family expansion (FR-003) and an inspector for the selected application.
///
/// Collapsed by default. The question a user has is "which application is using
/// the most", and a flat list of 800 processes buries that under helpers. The
/// aggregate answers it; the expansion explains it; the inspector accounts for it.
struct ProcessInventoryView: View {
    let store: MonitorStore
    @State private var query = ""
    /// Selection and expansion are both keyed on row identity, never row index.
    /// Rows reorder on every sample, so anything index-based would act on a
    /// different application after each refresh (FR-027).
    @State private var selection: InventoryRow.ID?
    @State private var expanded: Set<InventoryRow.ID> = []
    @State private var sortOrder = Presentation.defaultInventorySort
    @State private var scope: Scope = .apps
    /// The store's history, not this view's. It used to be `@State` here, which
    /// meant an application's series began when this screen opened and died when it
    /// closed — invisible to every other surface (TASK-95).
    private var history: FamilyHistory { store.familyHistory }
    /// Keeps the displayed order steady between samples (TASK-74). Positions only —
    /// the rows themselves are replaced every sample, so the numbers stay live.
    @State private var order = StableOrder<InventoryRow>()
    @State private var rows: [InventoryRow] = []

    /// Which list is on screen. `allProcesses` is the peer view (TASK-65.13); the
    /// control exists here so the count of what is *not* in the Apps list is
    /// visible from the Apps list, which is the honesty the design is after.
    enum Scope: String, CaseIterable, Identifiable {
        case apps, allProcesses
        var id: String { rawValue }
    }

    /// Whether the processes we may not measure are listed. Shown by default:
    /// hiding two thirds of the process table by default would reproduce, as a
    /// setting, exactly the omission the census exists to correct (TASK-65.13).
    @State private var showsUnmeasurable = true
    @State private var allProcessesSort = AllProcesses.defaultSort

    private var census: InventoryCensus { InventoryCensus.of(store.families) }

    /// Every process on the machine, flat (TASK-65.13).
    ///
    /// Built here rather than on the store so that nothing outside this view pays
    /// for it, and so the sampling loop stays the only writer of the store's state.
    private var allProcessRows: [AllProcessesRow] {
        AllProcesses.rows(store.families, contributions: contributions)
    }

    private var contributions: [ProcessIdentity: Double] {
        Dictionary(
            (store.attribution?.contributors ?? []).map { ($0.identity, $0.percentOfOneCore) },
            uniquingKeysWith: { first, _ in first })
    }

    /// Runs the same search against every process before saying anything about an
    /// empty application list (TASK-65.16).
    private var searchOutcome: InventorySearchOutcome {
        let processes = allProcessRows
        return InventorySearchOutcome(
            query: query,
            matchesInAllProcesses: processes.filter { AllProcesses.matches($0, query: query) }.count,
            totalProcesses: processes.count)
    }

    /// The ranking, recomputed from the newest sample every time it is asked for.
    /// Correct and twitchy; `rows` is this order damped (TASK-74).
    private var rankedRows: [InventoryRow] {
        let all = store.inventory
        let matching = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.children.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return Presentation.sortedInventory(matching, by: sortOrder)
    }

    /// What the table shows: the newest sample's rows, in a settled order.
    ///
    /// State rather than a computed property because settling is a decision about
    /// what changed since last time, and a view's `body` may not remember anything.
    /// Every refresh takes freshly ranked rows, so the numbers are never held back —
    /// only the sequence is.
    private func refreshRows(userAsked: Bool = false) {
        if userAsked { order.reset() }
        rows = order.settle(rankedRows)
    }

    /// The selected row, wherever it sits in the tree.
    private var selectedRow: InventoryRow? {
        guard let selection else { return nil }
        for row in rows {
            if row.id == selection { return row }
            if let child = row.children.first(where: { $0.id == selection }) { return child }
        }
        return nil
    }

    private var selectedFamily: ProcessFamily? {
        guard let selection else { return nil }
        return store.families.first { $0.id == selection }
    }

    var body: some View {
        Group {
            if let explanation = store.enumeration.explanation {
                // Never render an empty table here: a blank list would say
                // "nothing is running" when the truth is that we were refused.
                ContentUnavailableView {
                    Label("Applications can't be listed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(explanation)
                }
            } else {
                VStack(spacing: 0) {
                    scopeControl
                    Divider()
                    content
                }
            }
        }
        // Search covers both scopes and shares its term between them: switching
        // scope to find what the other list is hiding is the whole of screen 1p.
        .searchable(text: $query, prompt: searchPrompt)
        .navigationTitle("Apps & Processes")
        .onAppear { refreshRows(userAsked: true) }
        .onChange(of: store.lastUpdate) { _, _ in
            // Every sample: new numbers, settled order.
            // Recording happens on the sampling pass in `MonitorStore`; this only
            // re-ranks what is on screen.
            refreshRows()
        }
        // User intent re-ranks at once. A person who clicks "CPU" or types a search
        // term is asking to see the list rearranged, and making them wait would be
        // damping the wrong thing.
        .onChange(of: sortOrder) { _, _ in refreshRows(userAsked: true) }
        .onChange(of: query) { _, _ in refreshRows(userAsked: true) }
        // Tell the store what is selected so its history keeps tracking that family
        // even once it drops out of the busiest few.
        .onChange(of: selection) { _, _ in store.selectedFamilyID = selection }
        .onAppear { store.selectedFamilyID = selection }
    }

    private var scopeControl: some View {
        HStack {
            Picker("Show", selection: $scope) {
                Text("Apps · \(census.applicationCount)").tag(Scope.apps)
                Text("All processes · \(census.totalProcesses)").tag(Scope.allProcesses)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            if scope == .allProcesses {
                // The count is stated either way, so hiding them is a visible
                // choice rather than a silently shorter list.
                Toggle(isOn: $showsUnmeasurable) {
                    Text("Show unmeasurable · \(census.notMeasurableProcesses)")
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(10)
    }

    private var searchPrompt: String {
        scope == .apps ? "Search applications" : "Search processes"
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .apps:
            if rows.isEmpty && !query.isEmpty {
                // FR-002's rule applied to an empty list: "we found nothing here"
                // must never be delivered as "it is not running" (TASK-65.16).
                InventorySearchEmptyView(outcome: searchOutcome) { scope = .allProcesses }
            } else {
                HStack(spacing: 0) {
                    InventoryTable(
                        store: store, rows: rows, selection: $selection,
                        expanded: $expanded, sortOrder: $sortOrder)
                    if let selectedRow, selectedRow.kind != .member {
                        Divider()
                        FamilyInspectorView(
                            store: store, history: history,
                            row: selectedRow, family: selectedFamily)
                            .frame(width: 340)
                    }
                }
            }
        case .allProcesses:
            AllProcessesView(
                rows: allProcessRows,
                census: AllProcesses.census(allProcessRows),
                freshness: InventoryCensus.freshness(lastUpdate: store.lastUpdate),
                query: $query,
                showsUnmeasurable: $showsUnmeasurable,
                sortOrder: $allProcessesSort,
                icon: { store.icon(forExecutablePath: $0) })
        }
    }
}

/// The inventory table itself, with `rows` passed in rather than read from the
/// store.
///
/// Injected deliberately (TASK-75). The window grew to 3599 pt, and the only honest
/// way to test that is to ask this view what height it demands for a known number
/// of rows. A view that reads its own rows from a shared store cannot be asked
/// that question.
///
/// The answer, measured, was not the one anybody expected: the demand does not come
/// from the rows at all. 20 rows and 500 rows both demand 137 pt on their own, and
/// both demand ~9,500 pt inside a `NavigationSplitView` detail column. The footer
/// is what asks: seven paragraphs of caption text under
/// `fixedSize(horizontal: false, vertical: true)` inside a `safeAreaInset`. When
/// the split view asks the detail column for an ideal size it proposes no width,
/// so every sentence wraps to one word per line and the footer answers with
/// thousands of points. The rows were never involved.
struct InventoryTable: View {
    let store: MonitorStore
    let rows: [InventoryRow]
    @Binding var selection: InventoryRow.ID?
    @Binding var expanded: Set<InventoryRow.ID>
    @Binding var sortOrder: [KeyPathComparator<InventoryRow>]

    private var census: InventoryCensus { InventoryCensus.of(store.families) }

    var body: some View {
        // The bound that stops the footer's answer reaching the window. A table
        // scrolls, so its *ideal* height is a matter of taste rather than of
        // content, and stating one here is what makes the window's size the user's
        // business instead of the layout engine's.
        table.frame(minHeight: 160, idealHeight: 420, maxHeight: .infinity)
    }

    private func expansion(for id: InventoryRow.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            })
    }

    private var table: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            // Widths are declared because otherwise SwiftUI shares the table
            // evenly and the name — the only column carrying meaning — loses.
            // Measured on screen 2026-08-09 in a 1250 pt window: Name got about
            // 105 pt and rendered "1Passwo…", "iStat Me…", "System p…",
            // "loginwin…". Every numeric column here has a known maximum width, so
            // pinning those and leaving Name flexible gives it everything left over.
            TableColumn("Name", value: \.name) { row in
                nameCell(row)
            }
            .width(min: 220, ideal: 420)
            TableColumn("Now", value: \.cpuSortKey) { row in
                measurement(row) {
                    CPUPresentation.percentOfOneCore(row.percentOfOneCore)
                }
            }
            .width(min: 64, ideal: 76, max: 96)
            // The column the table is **sorted by** by default, which until now was
            // not on screen at all (TASK-96 finding 13): the list opened ordered by
            // the trailing minute under a "CPU" header showing the instant, with no
            // sort indicator anywhere and a footer explaining a different cause —
            // the 10 s order hold. The Now screen already solved this with two
            // labelled columns; this is the same pair.
            TableColumn("Last minute", value: \.trendSortKey) { row in
                if let trailing = row.trailing {
                    Text(CPUPresentation.percentOfOneCore(trailing.meanPercentOfOneCore))
                        .monospacedDigit()
                        .help(TrailingPresentation.caption(trailing)
                            + ", from \(trailing.sampleCount) readings")
                } else {
                    // Nothing retained is not a reading of zero (FR-002).
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 84, ideal: 96, max: 120)
            TableColumn("Memory", value: \.memorySortKey) { row in
                measurement(row) {
                    row.residentBytes == 0
                        ? "—" : ByteCountFormatStyle().format(Int64(row.residentBytes))
                }
            }
            .width(min: 84, ideal: 96, max: 120)
            // A family has no PID of its own, and a dash says that better than the
            // PID of whichever member happened to be first.
            TableColumn("PID", value: \.pidSortKey) { row in
                Text(row.pid.map(String.init) ?? "—").monospacedDigit()
            }
            .width(min: 56, ideal: 64, max: 80)
            TableColumn("Started", value: \.startedSortKey) { row in
                Text(row.startedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                    .monospacedDigit()
            }
            .width(min: 72, ideal: 84, max: 104)
            TableColumn("Processes", value: \.processCount) { row in
                Text(row.kind == .member ? "" : "\(row.processCount)").monospacedDigit()
            }
            .width(min: 64, ideal: 76, max: 96)
        } rows: {
            ForEach(rows) { row in
                if row.hasChildren {
                    DisclosureTableRow(row, isExpanded: expansion(for: row.id)) {
                        ForEach(row.children) { TableRow($0) }
                    }
                } else {
                    TableRow(row)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    @ViewBuilder
    private func nameCell(_ row: InventoryRow) -> some View {
        HStack(spacing: 6) {
            if row.kind == .systemProcesses {
                Image(systemName: "lock").foregroundStyle(.secondary).accessibilityHidden(true)
            } else if let icon = store.icon(forExecutablePath: row.executablePath) {
                // Decoration only: the name carries the meaning, so a missing icon
                // costs nothing and VoiceOver ignores it (FR-034).
                Image(nsImage: icon)
                    .resizable().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }

            Text(row.name)

            if row.isGroupedByGuess {
                // The chip is a word, not a colour: severity and doubt are never
                // carried by colour alone (FR-034).
                Text("Grouped by guess")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .help(row.qualification ?? "")
            } else if let qualification = row.qualification {
                // Stated in words rather than carried by an icon a user has to
                // hover to decode.
                Text(qualification)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(row))
    }

    private func accessibilityLabel(_ row: InventoryRow) -> String {
        var parts = [row.name]
        // The ellipsis in `row.name` is silent to VoiceOver, so the cut is said in
        // words instead (FR-002, FR-034).
        if row.nameIsShortened { parts.append(ProcessNaming.truncationNote) }
        if row.isGroupedByGuess { parts.append("grouped by guess") }
        if let qualification = row.qualification { parts.append(qualification) }
        if row.kind != .member { parts.append("\(row.processCount) processes") }
        parts.append(row.isMeasurable
            ? "\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core"
            : "usage unavailable")
        if let pid = row.pid { parts.append("PID \(pid)") }
        if let startedAt = row.startedAt {
            parts.append("started \(startedAt.formatted(date: .omitted, time: .shortened))")
        }
        if row.hasChildren {
            parts.append(expanded.contains(row.id) ? "expanded" : "collapsed")
        }
        return parts.joined(separator: ", ")
    }

    /// FR-002: a value we were refused reads as unavailable, never as zero.
    @ViewBuilder
    private func measurement(_ row: InventoryRow, _ text: () -> String) -> some View {
        if row.isMeasurable {
            Text(text()).monospacedDigit()
        } else {
            Text("Unavailable")
                .foregroundStyle(.secondary)
                .help("macOS does not report this process's usage to App Store apps.")
        }
    }

    /// The census, the freshness, and the one caveat that is about *this list*.
    ///
    /// It used to be seven paragraphs. Measured on screen 2026-08-09 in a 900 pt
    /// window: roughly 180 pt of caption, more vertical space than the table it was
    /// explaining, in the pane whose whole job is to show a long list (design 1d
    /// carries one sentence here).
    ///
    /// Nothing was deleted. The resident-memory and per-app-disk caveats already
    /// appear in `FamilyInspectorView`, beside the very figures they qualify, which
    /// is where the design puts them and where they are actually read; keeping a
    /// second copy down here was duplication, not diligence. The CPU convention and
    /// the P/E core note move behind the help affordance on the column itself, for
    /// the same reason: a caveat is worth most next to the number.
    ///
    /// What stays is what is true of the *list* rather than of a cell — the census,
    /// how fresh it is, and the fact that this list deliberately omits daemons.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            // FR-002/FR-038: the census and the freshness lead, because everything
            // above them is only true of what we were allowed to read and of when
            // we last read it.
            HStack(spacing: 8) {
                Text(census.summary).bold()
                Text(InventoryCensus.freshness(lastUpdate: store.lastUpdate))
            }
            .accessibilityElement(children: .combine)
            Text(InventoryCensus.explanation)
            // This one stays visible rather than moving behind help. Observed on
            // screen after the columns were widened: the list is plainly not in CPU
            // order under a header that says CPU, because TASK-74 holds the order
            // for 10 s. A user who sees that and has not been told will conclude the
            // sort is broken — which is exactly what TASK-63 turned out to be, an
            // hour spent on a table that was sorting correctly. An unexplained
            // deliberate behaviour is indistinguishable from a bug.
            Text(OrderStability.explanation)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        // Still reachable, and still one source of truth — the strings are the same
        // constants, not copies (TASK-65.22).
        .help(([CPUPresentation.convention(), CPUPresentation.topologyNote(),
                InventoryCensus.residentMemoryCaveat,
                InventoryCensus.perApplicationDiskCaveat]
                .compactMap { $0 }).joined(separator: "\n\n"))
    }
}
