import Metrics
import SwiftUI

struct MainWindowView: View {
    let store: MonitorStore
    @State private var selection: Section = .now

    enum Section: String, CaseIterable, Identifiable {
        case now = "Now"
        case apps = "Apps & Processes"
        case incidents = "Incidents"
        case storage = "Storage"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .now: "gauge.with.dots.needle.33percent"
            case .apps: "square.grid.2x2"
            case .incidents: "list.bullet.rectangle"
            case .storage: "internaldrive"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .badge(section == .incidents && store.openIncident != nil ? 1 : 0)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
            // The same bound as the detail column, for the same reason: this
            // footer's three wrapping lines are also `fixedSize` vertically, and
            // with the split view proposing no width they answered an ideal-size
            // query with over a thousand points (TASK-75).
            .frame(minHeight: 320, idealHeight: 480, maxHeight: .infinity)
        } detail: {
            detailPane
                // TASK-75: the window grew to 1300 x 3599 pt on a 1107 pt screen and
                // sprang back when resized, because the detail column's answer to
                // "how big would you like to be?" was thousands of points and the
                // window took it literally. Every pane here scrolls, so none of them
                // has a content height worth respecting — say what a sensible
                // window is once, here, rather than letting whichever pane is
                // selected decide.
                .frame(minWidth: 480, idealWidth: 700,
                       minHeight: 320, idealHeight: 480, maxHeight: .infinity)
        }
        .toolbar { ToolbarItem(placement: .primaryAction) { muteControl } }
        .onAppear { ActivationPolicy.mainWindowOpened() }
        .onDisappear { ActivationPolicy.mainWindowClosed() }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection {
        case .now: NowView(store: store, showIncidents: { selection = .incidents })
        case .apps: ProcessInventoryView(store: store)
        case .incidents: IncidentsView(store: store)
        case .storage: StorageView(store: store)
        }
    }

    /// FR-031 requires the current cadence be inspectable, and FR-030 requires we
    /// report our own cost. Both belong somewhere always visible rather than on a
    /// screen the user has to find, so they live in the sidebar footer.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(NowPresentation.cadenceLine(store.cadence))
            Text(store.selfCost)
            if !store.isWithinMemoryBudget {
                Text("Above our own \(FR030Budget.residentBytes / 1_048_576) MB budget.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .accessibilityElement(children: .combine)
    }

    /// FR-015: muting suppresses interruption only. The wording says so, because a
    /// control that looked like it stopped monitoring would be a lie about what
    /// the app is doing.
    @ViewBuilder
    private var muteControl: some View {
        if let remaining = store.mute.remaining(at: Date()) {
            Button("Muted for \(Int(remaining.totalSeconds / 60) + 1) min — unmute") {
                store.clearMute()
            }
        } else {
            Menu("Mute alerts") {
                Button("For 15 minutes") { store.mute(forMinutes: 15) }
                Button("For 1 hour") { store.mute(forMinutes: 60) }
                Button("For 8 hours") { store.mute(forMinutes: 8 * 60) }
                Divider()
                Text("Monitoring keeps running. Only the alerts stop.")
            }
            .help("Stops alerts for a period. Monitoring keeps running, so the evidence "
                  + "is intact when the mute expires.")
        }
    }
}

/// Current condition at a glance, with the numbers underneath (design 1c).
///
/// The organising rule of this screen is that the verdict comes first and the
/// figures support it. Render-only: it reads the store and formats; it never
/// samples, ranks or caches.
struct NowView: View {
    let store: MonitorStore
    /// Switches the window to the Incidents screen. Held as a closure so the
    /// banner's primary action can navigate without this view knowing what the
    /// sidebar selection is.
    var showIncidents: () -> Void = {}

    @State private var query = ""
    @State private var expanded: Set<InventoryRow.ID> = []
    /// What the last action actually did (FR-017). Never assumed from the call
    /// returning.
    @State private var lastActionOutcome: String?

    private var rows: [InventoryRow] {
        NowPresentation.matching(
            NowPresentation.contributorRows(store.inventory, limit: 5), query: query)
    }

    /// The series FR-005 retains, read once per render so the card and the table
    /// cannot be drawn from two different snapshots of it.
    private var retained: [HistorySample] { store.retainedSamples }

    private var cadenceInterval: Duration {
        store.cadence?.interval ?? MetricsHistory.defaultCadence
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let explanation = store.enumeration.explanation {
                    enumerationBanner(explanation)
                }
                if case .stale(let age) = store.freshness {
                    staleBanner(age: age)
                }

                if let incident = store.openIncident {
                    IncidentBanner(
                        incident: incident, store: store,
                        showIncidents: showIncidents,
                        outcome: $lastActionOutcome)
                }

                verdict
                cards
                contributors
                footnotes
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .searchable(text: $query, prompt: "Search contributors")
        .navigationTitle("Now")
        .navigationSubtitle(NowPresentation.machineIdentity(store.machine))
    }

    // MARK: - Verdict

    private var verdict: some View {
        let text = NowPresentation.verdict(
            severity: store.severity,
            attribution: store.attribution,
            incidentOpen: store.openIncident != nil)
        // Symbol and word together — severity is never carried by colour alone
        // (FR-034).
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: store.severity.symbolName).imageScale(.large)
            VStack(alignment: .leading, spacing: 3) {
                Text(text.headline).font(.title2).bold()
                Text(text.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.severity.label). \(text.headline). \(text.detail)")
    }

    // MARK: - Cards

    private var cards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: 12, alignment: .top)],
            spacing: 12
        ) {
            MetricCard(
                title: "CPU",
                state: store.severity.label,
                stateSymbol: store.severity.symbolName,
                value: store.attribution.map {
                    CPUPresentation.percentOfOneCore($0.totalBusyPercentOfOneCore)
                },
                unit: "of one core",
                details: store.attribution.map {
                    [CPUPresentation.machineRelative($0.totalBusyPercentOfOneCore)]
                } ?? [],
                unavailableReason: store.attribution == nil
                    ? "CPU is measured between two samples." : nil,
                // The retained series, not one this view accumulated: the card and
                // the incident report draw the same evidence (FR-005).
                history: HistorySparklineBlock(
                    title: "Total CPU",
                    points: SparklinePresentation.totalBusySeries(retained),
                    cadence: cadenceInterval))

            MetricCard(
                title: "Memory pressure",
                state: store.memoryPressure.label,
                stateSymbol: symbol(for: store.memoryPressure),
                value: store.memoryPressure.label,
                unit: nil,
                details: memoryDetails,
                help: store.memoryPressure.explanation)

            MetricCard(
                title: "Disk",
                state: nil,
                stateSymbol: "internaldrive",
                value: NowPresentation.diskWrite(store.diskRates),
                unit: "write",
                details: [NowPresentation.diskRead(store.diskRates)],
                // The framework's own sentence, not a second one written here. Two
                // hand-written paraphrases of the same limitation used to sit on
                // this screen — this card's help and a footnote — and either could
                // have drifted from what the app actually does (FR-009).
                help: DiskSignals.perApplicationUnavailable,
                // Design 1c shows a sparkline here. `MetricsHistory` retains CPU and
                // nothing else, so there is no series to draw — stated rather than
                // filled in from readings taken while this screen happened to be open.
                historyNote: NowPresentation.diskHistoryNote)

            MetricCard(
                title: "Thermals & power",
                state: store.thermalState.label,
                stateSymbol: "thermometer.medium",
                value: store.thermalState.label,
                unit: nil,
                details: [store.power.summary],
                help: store.thermalState.explanation)
        }
    }

    /// The memory figure is *calculated* from the kernel's page counters, and is
    /// labelled as such: it is not the pressure signal, and it must never be read
    /// as one (FR-007).
    /// Swap comes from the store, not from a `SwapSignals.swapUsage()` call made
    /// here: the loop reads it once so every surface quotes the same figure
    /// (FR-008).
    private var memoryDetails: [String] {
        NowPresentation.memoryCardDetails(
            statistics: MemorySignals.statistics(),
            physicalMemoryBytes: store.machine.physicalMemoryBytes,
            swapActivity: store.swapActivity,
            swapUsage: store.swapUsage)
    }

    private func symbol(for level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: "memorychip"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }

    // MARK: - Contributors

    @ViewBuilder
    private var contributors: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContributorHeader()
            Divider()

            if let explanation = store.enumeration.explanation {
                // An empty list here would read as "nothing is running", which is
                // the opposite of the truth (FR-002).
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else if rows.isEmpty {
                Text(query.isEmpty
                     ? "No application has measurable usage yet."
                     : "No contributor on this screen matches “\(query)”. This screen "
                       + "shows only the largest few — the full list is in Apps & Processes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                ForEach(rows) { row in
                    ContributorRow(
                        row: row, store: store,
                        isExpanded: expanded.contains(row.id),
                        toggle: { toggle(row.id) },
                        retained: retained, cadence: cadenceInterval)
                    if row.hasChildren, expanded.contains(row.id) {
                        ForEach(row.children) { child in
                            ContributorRow(
                                row: child, store: store, isExpanded: false,
                                toggle: {}, isChild: true,
                                retained: retained, cadence: cadenceInterval)
                        }
                    }
                    Divider()
                }
                Text("The largest few, plus everything we may not measure. The full list "
                     + "is in Apps & Processes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggle(_ id: InventoryRow.ID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: - Footnotes

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(NowPresentation.footnotes(), id: \.self) { note in
                Text(note).fixedSize(horizontal: false, vertical: true)
            }
            if let outcome = lastActionOutcome {
                Text(outcome).foregroundStyle(.primary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Existing banners

    /// FR-002: if the process table cannot be read, say so. An empty inventory
    /// would read as "nothing is running", which would be false — the truth is
    /// that we are not permitted to look. Aggregate metrics are unaffected and
    /// stay on screen.
    private func enumerationBanner(_ explanation: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Applications can't be listed on this Mac").font(.headline)
                Text(explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Applications cannot be listed on this Mac. \(explanation)")
    }

    /// FR-032/FR-002: a late reading is shown as the last complete one, with its
    /// age. Nothing is estimated forward.
    private func staleBanner(age: Duration) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("These readings are catching up").font(.headline)
                Text("The system was too busy to sample on time, so this is the last "
                     + "reading we trust, from \(Int(age.totalSeconds)) seconds ago — "
                     + "not a guess at what is happening now.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readings are catching up. Showing the last complete "
                            + "reading from \(Int(age.totalSeconds)) seconds ago.")
    }
}

/// The open incident, at the top of Now, with what can be done about it.
///
/// The body is the summariser's own output. Every line arrives already carrying
/// its evidence class and, where it is a hypothesis, its confidence — so the
/// banner cannot state a cause more strongly than the evidence allows (FR-013,
/// FR-038). Nothing is rewritten here into a flatter sentence.
struct IncidentBanner: View {
    let incident: Incident
    let store: MonitorStore
    let showIncidents: () -> Void
    @Binding var outcome: String?

    private var summary: IncidentSummary {
        IncidentSummarizer.summarize(incident: incident, attribution: store.attribution)
    }

    var body: some View {
        let summary = self.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(summary.headline).font(.title3).bold()
                Text(NowPresentation.incidentChip(incident))
                    .font(.caption).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.headline), \(NowPresentation.incidentChip(incident))")

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(summary.conclusions.enumerated()), id: \.offset) { _, conclusion in
                    Text(conclusion.display)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(summary.ruledOut.enumerated()), id: \.offset) { _, conclusion in
                    Text(conclusion.display)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Open incident", action: showIncidents)
                    .buttonStyle(.borderedProminent)
                if let leader = store.attribution?.contributors.first {
                    Button("Bring \(store.displayName(for: leader)) forward") {
                        bringForward(leader)
                    }
                }
            }

            if let outcome {
                Text(outcome).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// FR-017: report what happened, not that the call was made.
    private func bringForward(_ usage: ProcessCPUUsage) {
        guard let member = NowPresentation.familyMember(
            for: usage.identity, in: store.families) else {
            outcome = "\(store.displayName(for: usage)) is no longer in the last reading."
            return
        }
        let result = ActionPerformer().perform(
            .activate, on: member.record, resolved: member.resolved)
        switch result {
        case .succeeded:
            outcome = "macOS brought \(store.displayName(for: usage)) forward. "
                + "That changes what you are looking at, not what it is using."
        case .failed(let reason), .withheld(let reason):
            outcome = reason
        }
    }
}

/// One metric, as a card: a state, a figure, and what qualifies it.
struct MetricCard: View {
    let title: String
    /// The state word, when the metric has one. Never colour alone (FR-034).
    var state: String?
    var stateSymbol: String
    /// Nil when the value could not be read — shown as unavailable, never as zero.
    var value: String?
    var unit: String?
    var details: [String] = []
    var help: String?
    var unavailableReason: String?
    /// A short curve over what was retained, for the metrics we actually keep a
    /// series for. Nil is not "flat" — it is "no series", and `historyNote` is how
    /// that gets said.
    var history: HistorySparklineBlock?
    /// Why there is no curve, for a metric the design charts but we do not retain.
    var historyNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: stateSymbol).imageScale(.small).accessibilityHidden(true)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }

            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title).bold().monospacedDigit()
                    if let unit {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Unavailable").font(.title3).foregroundStyle(.secondary)
                if let unavailableReason {
                    Text(unavailableReason).font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let history {
                history.padding(.top, 2)
            }
            if let historyNote {
                Text(historyNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .help(help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [title]
        if let state { parts.append(state) }
        if let value {
            parts.append(unit.map { "\(value) \($0)" } ?? value)
        } else {
            parts.append("unavailable")
        }
        parts.append(contentsOf: details)
        // Folded in rather than left to `children: .combine`, which an explicit
        // label overrides — a sparkline VoiceOver cannot reach is not accessible.
        if let history { parts.append(history.accessibleSummary) }
        if let historyNote { parts.append(historyNote) }
        return parts.joined(separator: ", ")
    }
}

struct ContributorHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("App").frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: 90, alignment: .trailing)
            Text("Resident memory").frame(width: 130, alignment: .trailing)
            // Named for what is retained rather than "Last 5 min": the span is
            // whatever we have kept, and the cell states it.
            Text("Retained history").frame(width: 110, alignment: .trailing)
        }
        .font(.caption).bold()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

/// One contributor row, with its qualifiers stated in words.
struct ContributorRow: View {
    let row: InventoryRow
    let store: MonitorStore
    let isExpanded: Bool
    let toggle: () -> Void
    var isChild = false
    /// The retained series, passed down so every row on the screen is drawn from
    /// the same snapshot the CPU card used.
    var retained: [HistorySample] = []
    var cadence: Duration = MetricsHistory.defaultCadence

    var body: some View {
        HStack(spacing: 8) {
            if row.hasChildren {
                Button(action: toggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(row.name)" : "Expand \(row.name)")
            } else {
                Spacer().frame(width: 13)
            }

            if row.kind == .systemProcesses {
                Image(systemName: "lock").foregroundStyle(.secondary).accessibilityHidden(true)
            } else if let icon = store.icon(forExecutablePath: row.executablePath) {
                // Decoration only: the name carries the meaning (FR-034).
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }

            Text(row.name).lineLimit(1)

            if row.kind != .member, row.processCount > 1 {
                Text("\(row.processCount) processes")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(NowPresentation.chips(for: row), id: \.self) { chip in
                Text(chip)
                    .font(.caption)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            Spacer(minLength: 8)

            measurement { CPUPresentation.percentOfOneCore(row.percentOfOneCore) }
                .frame(width: 90, alignment: .trailing)
            measurement {
                row.residentBytes == 0
                    ? "—" : ByteCountFormatStyle().format(Int64(row.residentBytes))
            }
            .frame(width: 130, alignment: .trailing)

            history.frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .padding(.leading, isChild ? 22 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The retained history cell.
    ///
    /// Exactly one kind of row has a series behind it. "System processes" carries
    /// `unattributedPercentOfOneCore` (see `InventoryRow`), and every retained
    /// sample records that figure — so its curve has the same coverage as the
    /// machine total. Application rows do not: `MetricsHistory` keeps a bounded
    /// set of leading *processes*, so a per-app curve would be assembled from
    /// readings we only sometimes recorded. It says "not retained" instead, which
    /// is a statement about our records, not about the application.
    @ViewBuilder
    private var history: some View {
        if row.kind == .systemProcesses {
            let points = SparklinePresentation.unattributedSeries(retained)
            switch SparklinePresentation.readiness(points) {
            case .tooFew(let sentence):
                Text("Too few readings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(sentence)
            case .ready:
                HistorySparkline(
                    points: points,
                    gapThreshold: SparklinePresentation.gapThreshold(cadence: cadence),
                    height: 20,
                    summary: historyAccessibility)
            }
        } else {
            Text("Not retained")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help(SparklinePresentation.perFamilyHistoryExplanation)
        }
    }

    private var historyAccessibility: String {
        guard row.kind == .systemProcesses else {
            return "No retained history. " + SparklinePresentation.perFamilyHistoryExplanation
        }
        return SparklinePresentation.accessibilitySummary(
            title: "Unattributed system activity",
            points: SparklinePresentation.unattributedSeries(retained),
            window: MetricsHistory.defaultRetention,
            gapThreshold: SparklinePresentation.gapThreshold(cadence: cadence))
    }

    /// FR-002: a value we were refused reads as unavailable, never as zero.
    @ViewBuilder
    private func measurement(_ text: () -> String) -> some View {
        if row.isMeasurable {
            Text(text()).monospacedDigit()
        } else {
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("macOS does not report this process's usage to App Store apps.")
        }
    }

    private var accessibilityLabel: String {
        var parts = [row.name]
        if row.kind != .member { parts.append("\(row.processCount) processes") }
        parts.append(contentsOf: NowPresentation.chips(for: row))
        if row.isMeasurable {
            parts.append("\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core")
            if row.residentBytes > 0 {
                parts.append(ByteCountFormatStyle().format(Int64(row.residentBytes)) + " resident")
            }
        } else {
            parts.append("usage unavailable")
        }
        parts.append(historyAccessibility)
        if row.hasChildren { parts.append(isExpanded ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }
}
