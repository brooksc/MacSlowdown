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

    /// The footer's long form. Collapsed by default: the design's footer is one
    /// sentence, and the detail is for the reader who has a question, not for
    /// every reader on every visit (TASK-65.22).
    @State private var showsFooterDetail = false

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
            // **One CPU column, and it is the mean** (design 4a, FR-059/FR-060).
            //
            // There used to be two: "Now" showing the instant and "Last minute"
            // showing the trailing mean the table actually sorts by. Both were
            // honest and each was labelled, but they sat adjacent and were sampled
            // differently, which invites the reader to subtract one from the other
            // — a comparison that means nothing. FR-059 wants the sort key visible;
            // the fix is to make the visible one the only one, not to add a second.
            //
            // The instantaneous reading is not lost. It is the live end of the
            // sparkline beside this column, and it is spoken in the row's
            // accessibility label, where a reader needs it and cannot mistake it
            // for a second figure to do arithmetic with.
            TableColumn("CPU, 60 s mean", value: \.trendSortKey) { row in
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
            // Sized by the *heading*, not by the figure. At `min: 104` the values
            // fitted and the header read "CPU, 60 s me…" — which truncates the
            // one word that says what the number is, leaving a column of
            // percentages with no stated window (FR-038). Seen on screen
            // 2026-09-16.
            .width(min: 126, ideal: 132, max: 150)
            // The trend, for the rows we retain a series for. A row with no series
            // draws nothing and says so — never a flat line, which would read as a
            // quiet application when the truth is that we were not watching it.
            TableColumn("Last 5 min") { row in
                trendCell(row)
            }
            .width(min: 72, ideal: 88, max: 110)
            TableColumn("Resident memory", value: \.memorySortKey) { row in
                measurement(row) {
                    row.residentBytes == 0
                        ? "—" : ByteCountFormatStyle().format(Int64(row.residentBytes))
                }
            }
            .width(min: 108, ideal: 120, max: 150)
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

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                // Where the "Processes" column went. A count of members is a
                // property of the name beside it, not a quantity worth its own
                // column of the width the design has to spend (4a).
                if row.kind != .member, row.processCount > 1 {
                    Text("\(row.processCount) processes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

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
        // Both figures are spoken, each saying which it is. The mean is what the
        // table shows and sorts by; the instant is the sparkline's live end, which
        // VoiceOver cannot read off the curve (design 4a).
        if row.isMeasurable {
            if let trailing = row.trailing {
                parts.append(
                    "\(CPUPresentation.percentOfOneCore(trailing.meanPercentOfOneCore)) "
                    + "of one core, \(TrailingPresentation.caption(trailing))")
            }
            parts.append(
                "\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core now")
        } else {
            parts.append("usage unavailable")
        }
        if let pid = row.pid { parts.append("PID \(pid)") }
        if let startedAt = row.startedAt {
            parts.append("started \(startedAt.formatted(date: .omitted, time: .shortened))")
        }
        if row.hasChildren {
            parts.append(expanded.contains(row.id) ? "expanded" : "collapsed")
        }
        return parts.joined(separator: ", ")
    }

    /// The row's retained curve, or an honest blank.
    ///
    /// Only a bounded set of rows is retained (`FamilyHistory.tracked`), so most
    /// rows have no series at all — and a row with no series must not draw a flat
    /// line, which reads as "this application was quiet" when the truth is "we were
    /// not watching this one". The dash and its help text say which (FR-002,
    /// FR-057).
    @ViewBuilder
    private func trendCell(_ row: InventoryRow) -> some View {
        let points = store.familyHistory.points(for: row.id)
            .map { SparklinePoint(at: $0.at, value: $0.percentOfOneCore) }
        if row.isMeasurable, points.count > 1 {
            HistorySparkline(
                points: points,
                height: 16,
                summary: SparklinePresentation.accessibilitySummary(
                    title: "\(row.name), CPU trend",
                    points: points,
                    window: .seconds(300),
                    gapThreshold: SparklinePresentation.gapThreshold(
                        cadence: MetricsHistory.defaultCadence)))
        } else {
            Text("—")
                .foregroundStyle(.secondary)
                .help(row.isMeasurable
                    ? "No trend is retained for this row yet."
                    : "macOS does not report this process's usage to App Store apps.")
        }
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
            // **One sentence, and the rest one disclosure away** (design 4,
            // TASK-65.22). This was three paragraphs rendering as five to seven
            // lines under the table. Both facts the short form keeps are the ones
            // a reader will otherwise take for defects: an application-only list
            // reads as a list that has lost its daemons, and a damped order under
            // a header that says CPU reads as broken sorting.
            //
            // Nothing is deleted. `fullExplanations` is the same constants the
            // long footer used, plus the two caveats that were previously only in
            // a tooltip — which made them unreachable from the keyboard and
            // invisible to anyone not hovering.
            DisclosureGroup(isExpanded: $showsFooterDetail) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(InventoryCensus.fullExplanations, id: \.self) { line in
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(CPUPresentation.convention())
                        .fixedSize(horizontal: false, vertical: true)
                    if let topology = CPUPresentation.topologyNote() {
                        Text(topology).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(InventoryCensus.shortExplanation)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
