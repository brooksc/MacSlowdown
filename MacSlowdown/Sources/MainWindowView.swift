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
                let badge = section == .incidents && store.openIncident != nil ? 1 : 0
                Label(section.rawValue, systemImage: section.symbol)
                    .badge(badge)
                    .tag(section)
                    // Measured on screen 2026-08-09: with a badge attached, this
                    // row's accessibility label was the bare string "1" — the badge
                    // had replaced the name. So the one navigation control that
                    // matters most lost its name *exactly* when there was an
                    // incident to go and look at, and read correctly the rest of
                    // the time, which is why using the app casually never caught it
                    // (FR-034).
                    //
                    // Spoken as a counted noun: "1" alone does not say what is being
                    // counted.
                    .accessibilityLabel(
                        badge > 0
                            ? "\(section.rawValue), \(badge) open incident"
                            : section.rawValue)
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
    /// The clock the ages on this screen are measured against.
    ///
    /// Deliberately not the sampling cadence (DR-03). Ages have to advance while
    /// *no* sample is arriving — that is the entire condition design 1n describes —
    /// and a screen that only redraws when the store changes would sit on
    /// "current" throughout a stall.
    @State private var now = Date()

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

    /// The age of everything the sampling loop writes in one pass: CPU, the
    /// contributor list, disk throughput, swap, paging, thermals and power.
    private var sampleFreshness: NowPresentation.MetricFreshness {
        NowPresentation.metricFreshness(
            observedAt: store.lastUpdate, now: now, cadence: cadenceInterval)
    }

    /// Memory pressure is the one metric with a life of its own: the kernel pushes
    /// a transition through a dispatch source, so while that is running the level
    /// is current no matter how far behind the loop is.
    private var memoryFreshness: NowPresentation.MetricFreshness {
        store.memoryPressureIsLive ? .reportedOnChange : sampleFreshness
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let explanation = store.enumeration.explanation {
                    enumerationBanner(explanation)
                }
                if sampleFreshness.isStale {
                    catchingUpBanner
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
        .task { await tickAgeClock() }
        .searchable(text: $query, prompt: "Search contributors")
        .navigationTitle("Now")
        .navigationSubtitle(NowPresentation.machineIdentity(store.machine))
    }

    /// Advances `now` once a second while this screen is on it, and stops when it
    /// is not. Cancelled by SwiftUI with the view, so nothing ticks in the
    /// background for a screen nobody is looking at.
    private func tickAgeClock() async {
        while !Task.isCancelled {
            now = Date()
            try? await Task.sleep(for: .seconds(1))
        }
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

    /// Four cards, four across wherever they fit (design 1c).
    ///
    /// `.adaptive(minimum:)` cannot express this. It packs as many columns as the
    /// width allows, so at 900 pt it fitted three of the four and dropped "Thermals
    /// & power" below the fold, while at 1250 pt it would lay out six columns for
    /// four cards. There are exactly four, and the requirement is that all four are
    /// visible — so the number of columns is chosen against the width the container
    /// actually has, and only falls back when four genuinely will not fit.
    private var cards: some View {
        // Read once and handed to each candidate: `ViewThatFits` builds all three
        // to measure them, and `memoryDetails` calls `host_statistics64`.
        let memory = memoryDetails
        return ViewThatFits(in: .horizontal) {
            cardGrid(columns: 4, memoryDetails: memory)
            cardGrid(columns: 2, memoryDetails: memory)
            cardGrid(columns: 1, memoryDetails: memory)
        }
    }

    private func cardGrid(columns: Int, memoryDetails: [String]) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 150), spacing: 12, alignment: .top),
                count: columns),
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
                freshness: sampleFreshness,
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
                help: store.memoryPressure.explanation,
                freshness: memoryFreshness)

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
                // The same pass as the CPU attribution, so the same age. Design 1n
                // shows this card as current while CPU is stale; in this app that
                // would be a distinction we cannot support.
                freshness: sampleFreshness,
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
                help: store.thermalState.explanation,
                freshness: sampleFreshness)
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
            // FR-032: the list is headed with the age of the reading it came from,
            // so a table of figures cannot be read as live when it is not.
            if let note = NowPresentation.contributorHeaderNote(sampleFreshness) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text("Contributors").bold()
                    Text(note).foregroundStyle(.secondary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Contributors, \(note)")
            }
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
                        retained: retained, cadence: cadenceInterval,
                        age: sampleFreshness.rowCaption)
                    if row.hasChildren, expanded.contains(row.id) {
                        ForEach(row.children) { child in
                            ContributorRow(
                                row: child, store: store, isExpanded: false,
                                toggle: {}, isChild: true,
                                retained: retained, cadence: cadenceInterval,
                                age: sampleFreshness.rowCaption)
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
            // First, because while readings are late this is the note that governs
            // every figure above it (FR-002, FR-032).
            if sampleFreshness.isStale {
                ForEach(NowPresentation.staleFootnotes, id: \.self) { note in
                    Text(note)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
    /// age, and the screen says that recording has not stopped. Nothing is
    /// estimated forward (design 1n).
    private var catchingUpBanner: some View {
        let copy = NowPresentation.catchingUpBanner(cadence: cadenceInterval)
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(copy.headline).font(.headline)
                    Spacer(minLength: 8)
                    Text(copy.retry).font(.caption).foregroundStyle(.secondary)
                }
                Text(copy.body)
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
        .accessibilityLabel("\(copy.headline). \(copy.body) \(copy.retry).")
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

    /// Increase Contrast and Reduce Transparency, read from the environment so the
    /// banner re-draws when either is switched while the window is open. The rule
    /// they feed is `NowPresentation.BannerTreatment.resolve`, which is where it can
    /// be tested — the same split as `MenuBarIconTreatment` (FR-034).
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var treatment: NowPresentation.BannerTreatment {
        .resolve(
            increaseContrast: contrast == .increased,
            reduceTransparency: reduceTransparency)
    }

    /// Severity's hue. Never the only carrier of severity: the word is in the chip,
    /// the glyph's *shape* changes with it, and under Increase Contrast this is not
    /// used at all (FR-034).
    private var tint: Color {
        switch NowPresentation.tint(for: incident.severity) {
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        }
    }

    private var summary: IncidentSummary {
        IncidentSummarizer.summarize(incident: incident, attribution: store.attribution)
    }

    var body: some View {
        let summary = self.summary
        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: summary.headline)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: NowPresentation.symbolName(for: incident.severity))
                        .imageScale(.large)
                        .foregroundStyle(treatment.usesTint ? tint : Color.primary)
                        .accessibilityHidden(true)
                    Text(headline.text).font(.title3).bold()
                    chip
                }
                // The confidence for naming an application, kept with the sentence
                // that names it. A headline that stated a cause without this would
                // be the unlabelled causal claim FR-013 forbids.
                if let qualifier = headline.qualifier {
                    Text(qualifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(headline.spoken) \(NowPresentation.incidentChip(incident))")

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
                bringForwardButton
                expectedWorkloadButton
            }

            if let outcome {
                Text(outcome)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(field)
    }

    // MARK: - The field

    /// The banner's own background, in the three forms the accessibility settings
    /// allow. Every one of them is a rectangle with the same content in it; only
    /// the colour changes, which is the point (FR-034).
    @ViewBuilder
    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        switch treatment.field {
        case .tintedFill:
            shape.fill(tint.opacity(0.16))
                .overlay(shape.strokeBorder(tint.opacity(0.5), lineWidth: 1))
        case .tintedBorder:
            // Opaque, because Reduce Transparency is a request not to be shown a
            // wash. Severity moves into a solid border instead of a fill.
            shape.fill(Color(nsColor: .controlBackgroundColor))
                .overlay(shape.strokeBorder(tint, lineWidth: 2))
        case .plain:
            shape.fill(.quaternary)
                .overlay(shape.strokeBorder(Color.primary, lineWidth: 2))
        }
    }

    /// Severity and elapsed time. The severity **word** is here in every treatment,
    /// so the colour beside it is reinforcement and never the message.
    private var chip: some View {
        Text(NowPresentation.incidentChip(incident))
            .font(.caption).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(chipBackground)
    }

    @ViewBuilder
    private var chipBackground: some View {
        let capsule = Capsule()
        switch treatment.field {
        case .tintedFill: capsule.fill(tint.opacity(0.28))
        case .tintedBorder: capsule.strokeBorder(tint, lineWidth: 1.5)
        case .plain: capsule.fill(.quaternary)
        }
    }

    // MARK: - Actions

    /// Whom to bring forward.
    ///
    /// For a repeated-quit episode this is the command that kept exiting, **not**
    /// the largest CPU contributor: the two are different applications, and the
    /// contributor had nothing to do with the finding (TASK-82). The button is
    /// omitted when nothing by that name is running, because there is then nothing
    /// to bring forward and a control that could only fail is worse than none.
    @ViewBuilder
    private var bringForwardButton: some View {
        if let pattern = NowPresentation.leadingRelaunchPattern(incident) {
            if let member = NowPresentation.familyMember(
                forCommand: pattern.command, in: store.families) {
                let name = member.resolved.displayName(command: member.record.command)
                Button("Bring \(name) forward") { bringForward(member, named: name) }
            }
        } else if let leader = store.attribution?.contributors.first {
            Button("Bring \(store.displayName(for: leader)) forward") {
                bringForward(leader)
            }
        }
    }

    /// Design 1c's third action: mark this application's load as expected, at the
    /// moment it is annoying the user (FR-016).
    ///
    /// Offered only where the incident actually attributed itself to an application.
    /// "Heavy load is expected" is meaningless for a repeated-quit episode, and
    /// there would be nothing to key the rule on.
    @ViewBuilder
    private var expectedWorkloadButton: some View {
        if NowPresentation.leadingRelaunchPattern(incident) == nil,
           let leader = incident.attribution?.leadingApplication {
            Button(NowPresentation.expectedPolicyActionTitle(leader.displayName)) {
                markExpected(leader)
            }
            .help("Records that heavy load is normal for this application. It stops the "
                  + "alerts, not the monitoring — incidents are still recorded.")
        }
    }

    /// FR-016. Written through the store's `PolicyStore` and then **read back**:
    /// `setPolicy` returning is not evidence that a rule exists (FR-017, FR-050).
    private func markExpected(_ leader: IncidentContributor) {
        let policy = ApplicationPolicy(
            bundleID: leader.bundleID, bundlePath: leader.bundlePath,
            displayName: leader.displayName, classification: .expected)
        store.policies.setPolicy(policy)
        let saved = store.policies.policies.contains {
            $0.id == policy.id && $0.classification == .expected
        }
        outcome = NowPresentation.expectedPolicyOutcome(
            name: leader.displayName, saved: saved)
    }

    /// FR-017: report what happened, not that the call was made.
    private func bringForward(_ usage: ProcessCPUUsage) {
        guard let member = NowPresentation.familyMember(
            for: usage.identity, in: store.families) else {
            outcome = "\(store.displayName(for: usage)) is no longer in the last reading."
            return
        }
        bringForward(member, named: store.displayName(for: usage))
    }

    private func bringForward(_ member: FamilyMember, named name: String) {
        let result = ActionPerformer().perform(
            .activate, on: member.record, resolved: member.resolved)
        switch result {
        case .succeeded:
            outcome = "macOS brought \(name) forward. "
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
    /// How old this card's reading is (design 1n). Defaults to current so a card
    /// that has not been given one cannot silently claim freshness it was never
    /// told about — every call site on the Now screen passes one.
    var freshness: NowPresentation.MetricFreshness = .current(age: .zero)
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
                    // Greyed while late, exactly as design 1n draws it — but the
                    // caption below carries the same fact in words and a glyph,
                    // because dimming is a colour and colour never carries meaning
                    // on its own (FR-034).
                    Text(value)
                        .font(.title).bold().monospacedDigit()
                        .foregroundStyle(freshness.isStale ? .secondary : .primary)
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

            // "as of 45 seconds ago" or "current" — the age of *this* card's
            // reading, not of the screen (FR-002, FR-032).
            HStack(spacing: 4) {
                if let symbol = freshness.symbolName {
                    Image(systemName: symbol).imageScale(.small).accessibilityHidden(true)
                }
                Text(freshness.caption)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
        // Immediately after the figure, so the age is heard as a qualifier on it
        // rather than as a trailing remark (FR-034).
        parts.append(freshness.spoken)
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
    /// The age of the reading this row came from, or nil while it is current.
    /// Every row on the screen comes from the same sampling pass, so they all
    /// carry the same age — which is the truth, not a simplification.
    var age: String?

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

            if let age {
                Text(age)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
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
        if let age { parts.append("from the reading \(age)") }
        parts.append(historyAccessibility)
        if row.hasChildren { parts.append(isExpanded ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }
}
