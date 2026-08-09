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
    @State private var history = FamilyHistory()

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

    private var rows: [InventoryRow] {
        let all = store.inventory
        let matching = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.children.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return Presentation.sortedInventory(matching, by: sortOrder)
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
        .onChange(of: store.lastUpdate) { _, _ in
            history.record(rows: store.inventory, families: store.families,
                           selected: selection)
        }
        .onChange(of: selection) { _, _ in
            history.record(rows: store.inventory, families: store.families,
                           selected: selection)
        }
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
                    table
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

    private func expansion(for id: InventoryRow.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            })
    }

    private var table: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                nameCell(row)
            }
            TableColumn("CPU", value: \.cpuSortKey) { row in
                measurement(row) {
                    CPUPresentation.percentOfOneCore(row.percentOfOneCore)
                }
            }
            TableColumn("Memory", value: \.memorySortKey) { row in
                measurement(row) {
                    row.residentBytes == 0
                        ? "—" : ByteCountFormatStyle().format(Int64(row.residentBytes))
                }
            }
            // A family has no PID of its own, and a dash says that better than the
            // PID of whichever member happened to be first.
            TableColumn("PID", value: \.pidSortKey) { row in
                Text(row.pid.map(String.init) ?? "—").monospacedDigit()
            }
            TableColumn("Started", value: \.startedSortKey) { row in
                Text(row.startedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                    .monospacedDigit()
            }
            TableColumn("Processes", value: \.processCount) { row in
                Text(row.kind == .member ? "" : "\(row.processCount)").monospacedDigit()
            }
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            // FR-002/FR-038: the census and the freshness are the first two lines,
            // because everything above them is only true of what we were allowed
            // to read and of when we last read it.
            HStack(spacing: 8) {
                Text(census.summary).bold()
                Text(InventoryCensus.freshness(lastUpdate: store.lastUpdate))
            }
            .accessibilityElement(children: .combine)
            Text(InventoryCensus.explanation)
            Text(CPUPresentation.convention())
            if let note = CPUPresentation.topologyNote() {
                Text(note)
            }
            Text("Resident memory. Activity Monitor's Memory column shows a different "
                 + "measure (footprint), so the numbers will not match exactly.")
            Text("Per-app disk activity is not available to App Store apps.")
            Text("Click a column heading to sort, a triangle to see the individual "
                 + "processes an application is running, or a row to inspect it.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}
