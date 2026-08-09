import Metrics
import SwiftUI

/// Compact persistent status surface (FR-001). Design references: 1a and 1b.
///
/// Reassurance first, numbers second. The popover answers "is my Mac all right?"
/// in a sentence, proves that monitoring is actually running, and only then shows
/// figures — a severity word over a table answers a question nobody asked.
///
/// It changes shape during an incident (design 1b): the condition and how long it
/// has held replace the verdict, one labelled causal sentence replaces the metric
/// strip, and the contributor list becomes a share of the incident's busy time
/// that visibly adds to 100%.
///
/// Render-only. It reads from the store and opens windows; it never samples or
/// computes. The two exceptions are volume capacity and disk-counter availability,
/// which the store does not carry and which are read once when the popover
/// appears rather than on the sampling loop.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    let store: MonitorStore

    /// Startup volume capacity, read when the popover opens. Nil means either
    /// "not read yet" or "did not report", and both render as unavailable.
    @State private var startupVolume: VolumeCapacity?
    /// Whether the machine reports disk byte counters at all. Nil until checked.
    @State private var diskCountersAvailable: Bool?
    @State private var showsUnattributedExplanation = false
    /// What actually happened when the user pressed "Show …". Reported rather than
    /// assumed: the request being accepted is not the window coming forward
    /// (FR-017).
    @State private var showOutcome: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let incident = store.openIncident, let attribution = store.attribution {
                triage(incident: incident, attribution: attribution)
            } else {
                verdict

                Divider()

                metricStrip

                contributors
            }

            Divider()

            actions
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .task {
            startupVolume = StorageSignals.snapshot().startupVolume
            diskCountersAvailable = DiskSignals.counters() != nil
        }
    }

    // MARK: - Verdict

    private var verdict: some View {
        let verdict = PopoverPresentation.verdict(
            severity: store.severity, incidentOpen: store.openIncident != nil)
        // Symbol and sentence together: severity is never carried by colour alone
        // (FR-034).
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: verdict.symbolName)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(monitoringLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .stale(let age) = store.freshness {
                    // A late reading is shown as late rather than as current.
                    Text("Last complete reading, \(Int(age.totalSeconds))s ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(verdict.headline). \(monitoringLine)")
    }

    private var monitoringLine: String {
        PopoverPresentation.monitoringLine(
            isRunning: store.isRunning,
            watchingSince: PopoverPresentation.launchedAt,
            now: Date(),
            incidentCount: store.recentIncidents.count + (store.openIncident == nil ? 0 : 1))
    }

    // MARK: - Headline figures

    private var metricStrip: some View {
        let tiles = PopoverPresentation.tiles(
            attribution: store.attribution,
            memoryPressure: store.memoryPressure,
            // Before the second sample there is no rate, and an unreadable driver
            // has no rate either. Neither is zero.
            diskRates: diskRates,
            storage: startupVolume)
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(tiles) { tile in
                MetricTileView(tile: tile)
            }
        }
    }

    private var diskRates: DiskRates? {
        guard diskCountersAvailable != false, store.attribution != nil else { return nil }
        return store.diskRates
    }

    // MARK: - Contributors

    @ViewBuilder
    private var contributors: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Using the most CPU now")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if let attribution = store.attribution {
                ForEach(PopoverPresentation.contributorRows(
                    families: store.rankedFamilies,
                    attributedPercentOfOneCore: attribution.attributedPercentOfOneCore,
                    unattributedPercentOfOneCore: attribution.unattributedPercentOfOneCore)
                ) { row in
                    contributorRow(row, explanation: attribution.explanation)
                }

                if showsUnattributedExplanation {
                    Text(attribution.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Taking the first reading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(CPUPresentation.convention())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contributorRow(
        _ row: PopoverPresentation.ContributorRow, explanation: String
    ) -> some View {
        HStack(spacing: 7) {
            icon(for: row)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            // The resolved name, never the kernel's 16-byte command. The store
            // owns naming so this row, the table and the notification cannot
            // disagree.
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.tail)

            if row.processCount > 1 {
                Text("· \(row.processCount) processes")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if row.isPartial {
                // Not decoration: it says the figure is a floor, not a total.
                Text("(partial)")
                    .foregroundStyle(.secondary)
                    .help(PopoverPresentation.partialExplanation)
            }

            if row.kind == .unattributed {
                Button {
                    showsUnattributedExplanation.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(explanation)
                .accessibilityLabel("Why is this activity unattributed?")
            }

            Spacer(minLength: 6)

            Text(CPUPresentation.percentOfOneCore(row.percentOfOneCore))
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(row.kind == .application ? .primary : .secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PopoverPresentation.accessibilityLabel(for: row))
        .accessibilityHint(hint(for: row, explanation: explanation) ?? "")
    }

    private func hint(
        for row: PopoverPresentation.ContributorRow, explanation: String
    ) -> String? {
        switch row.kind {
        case .unattributed: explanation
        case .other: nil
        case .application: row.isPartial ? PopoverPresentation.partialExplanation : nil
        }
    }

    private func icon(for row: PopoverPresentation.ContributorRow) -> some View {
        icon(forKind: row.kind, executablePath: row.executablePath)
    }

    // MARK: - Live incident (design 1b)

    /// The leading application family, which the cause sentence names and the
    /// "Show …" action targets.
    ///
    /// Family-level rather than process-level so that the sentence names what the
    /// share list beneath it ranks. The confidence comes from `IncidentSummarizer`,
    /// which computes it from the leading *process*; a family's share is never
    /// smaller than its largest process's, and the summariser's confidence only
    /// rises with that share, so the figure we show is a floor. Erring low is the
    /// safe direction for a causal claim.
    private var leadingFamily: MonitorStore.FamilyRow? {
        store.rankedFamilies.first { $0.percentOfOneCore > 0 }
    }

    @ViewBuilder
    private func triage(incident: Incident, attribution: CPUAttribution) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            incidentHeadline(incident)

            if let cause = causeConclusion(attribution) {
                causeSentence(cause)
            }

            incidentSparkline(incident)

            shareOfBusyTime(attribution)
        }
    }

    /// Total CPU over the retained window with the incident start marked
    /// (design 1b).
    ///
    /// The points are `MonitorStore.retainedSamples` — the series FR-005 keeps as
    /// evidence — so this popover and the incident report cannot show two different
    /// histories of the same minutes. Nothing is accumulated here.
    ///
    /// The mark is `incident.beganAt`, the detector's own record of when the
    /// condition first breached. It is never inferred from the shape of the curve:
    /// marking "where it looks like it started" would assert a detection we did not
    /// make. When the incident began before anything we still hold, the caption says
    /// so rather than sliding the mark to the left edge.
    ///
    /// Design 1b labels this "last 15 minutes". We label it with the span actually
    /// retained, which early in a run is much less — the app may have been watching
    /// for two minutes.
    @ViewBuilder
    private func incidentSparkline(_ incident: Incident) -> some View {
        let points = SparklinePresentation.totalBusySeries(store.retainedSamples)
        VStack(alignment: .leading, spacing: 4) {
            Text("Total CPU")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HistorySparklineBlock(
                title: "Total CPU",
                points: points,
                markers: [incident.beganAt],
                cadence: store.cadence?.interval ?? MetricsHistory.defaultCadence,
                axisCaption: SparklinePresentation.markerCaption(
                    beganAt: incident.beganAt, points: points))
        }
    }

    private func incidentHeadline(_ incident: Incident) -> some View {
        let headline = PopoverPresentation.incidentHeadline(incident, now: Date())
        // Symbol, headline and severity word together — severity is never carried
        // by colour alone (FR-034).
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(incident.severity.label) slowdown, happening now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .stale(let age) = store.freshness {
                    Text("Last complete reading, \(Int(age.totalSeconds))s ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(incident.severity.label) slowdown, happening now.")
    }

    /// The one causal claim on the screen, and the only one in the popover.
    private func causeConclusion(_ attribution: CPUAttribution) -> Conclusion? {
        guard let leader = leadingFamily,
              // No hypothesis from the summariser means there is nothing we are
              // confident enough to call a cause. Say nothing rather than invent it.
              let confidence = store.currentSummary?.hypotheses.first?.confidence
        else { return nil }
        return PopoverPresentation.cause(
            leaderName: leader.family.displayName,
            leaderPercentOfOneCore: leader.percentOfOneCore,
            totalBusyPercentOfOneCore: attribution.totalBusyPercentOfOneCore,
            unattributedShare: attribution.unattributedShare,
            confidence: confidence)
    }

    private func causeSentence(_ conclusion: Conclusion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // The evidence class and confidence are shown, not implied. `Conclusion`
            // will not let a heuristic exist without one (FR-013, FR-038).
            Text("\(conclusion.evidence.label) · \(conclusion.confidence?.label ?? "")")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(conclusion.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(conclusion.display)
    }

    @ViewBuilder
    private func shareOfBusyTime(_ attribution: CPUAttribution) -> some View {
        let rows = PopoverPresentation.shareRows(
            families: store.rankedFamilies, attribution: attribution)

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(PopoverPresentation.shareHeading)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    // Not decoration: it is the promise that makes the arithmetic
                    // checkable, which is why the rounding is largest-remainder.
                    Text(PopoverPresentation.shareHeadingQualifier)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                ForEach(rows) { row in
                    shareRow(row, explanation: attribution.explanation)
                }

                if showsUnattributedExplanation {
                    Text(attribution.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let leader = leadingFamily {
                    Text(PopoverPresentation.conventionReconciliation(
                        leaderName: leader.family.displayName,
                        leaderPercentOfOneCore: leader.percentOfOneCore))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func shareRow(
        _ row: PopoverPresentation.ShareRow, explanation: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                icon(forKind: row.kind, executablePath: row.executablePath)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)

                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if row.processCount > 1 {
                    Text("· \(row.processCount) processes")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if row.isPartial {
                    Text("(partial)")
                        .foregroundStyle(.secondary)
                        .help(PopoverPresentation.partialExplanation)
                }

                if row.kind == .unattributed {
                    Button { showsUnattributedExplanation.toggle() } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(explanation)
                    .accessibilityLabel("Why is this activity unattributed?")
                }

                Spacer(minLength: 6)

                Text("\(row.percentOfBusy)%").monospacedDigit()
            }
            .font(.callout)

            ProgressView(value: min(max(row.fractionOfBusy, 0), 1))
                .progressViewStyle(.linear)
                .accessibilityHidden(true)
        }
        .foregroundStyle(row.kind == .application ? .primary : .secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shareAccessibilityLabel(row))
        .accessibilityHint(row.kind == .unattributed ? explanation : "")
    }

    private func shareAccessibilityLabel(_ row: PopoverPresentation.ShareRow) -> String {
        var parts = [row.name]
        if row.processCount > 1 { parts.append("\(row.processCount) processes") }
        if row.isPartial { parts.append("partly measured") }
        parts.append("\(row.percentOfBusy)% of the busy time")
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if store.openIncident != nil {
            incidentActions
        } else {
            VStack(spacing: 6) {
                Button("Open MacSlowdown") {
                    openWindow(id: MainWindow.id)
                    ActivationPolicy.mainWindowOpened()
                }
                .keyboardShortcut("o")
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                // Deliberate divergence from design 1a, which shows no Quit. The
                // menu bar item is the primary surface and the app has no Dock icon
                // by default, so without this there is no way to quit.
                Button("Quit MacSlowdown") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The three actions of design 1b. Every one of them observes, brings forward,
    /// or silences our own alerts. None of them touches how another process runs —
    /// there is no code path here that could (FR-037).
    private var incidentActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("See the evidence") {
                    openWindow(id: MainWindow.id)
                    ActivationPolicy.mainWindowOpened()
                }
                .keyboardShortcut("o")
                .buttonStyle(.borderedProminent)

                if let target = showTarget {
                    Button(PopoverPresentation.showActionTitle(for: target.name)) {
                        show(target)
                    }
                }

                Menu("Mute") {
                    ForEach(PopoverPresentation.muteChoices, id: \.self) { minutes in
                        Button(PopoverPresentation.muteChoiceTitle(minutes: minutes)) {
                            store.mute(forMinutes: minutes)
                        }
                    }
                    if PopoverPresentation.muteStatus(store.mute, now: Date()) != nil {
                        Divider()
                        Button("Unmute") { store.clearMute() }
                    }
                }
                .menuStyle(.button)
                .fixedSize()
            }

            if let status = PopoverPresentation.muteStatus(store.mute, now: Date()) {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            // FR-017: what happened, not what was requested.
            if let showOutcome {
                Text(showOutcome)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(PopoverPresentation.controlAssurance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Quit MacSlowdown") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    /// The member of the leading family that "Show …" would bring forward, if the
    /// safety policy permits acting on it at all.
    ///
    /// Withheld actions are absent rather than shown disabled — a protected
    /// process simply has no "Show" button, matching `SafetyPolicy`'s own rule.
    private var showTarget: (name: String, member: FamilyMember)? {
        guard let leader = leadingFamily else { return nil }
        let bundleExecutablePrefix = leader.family.bundlePath.map { $0 + "/Contents/MacOS/" }
        let member = leader.family.members.first {
            guard let prefix = bundleExecutablePrefix,
                  let path = $0.resolved.executablePath else { return false }
            return path.hasPrefix(prefix)
        } ?? leader.family.members.first
        guard let member,
              SafetyPolicy().availability(of: .activate, for: member.record).isAvailable
        else { return nil }
        return (leader.family.displayName, member)
    }

    private func show(_ target: (name: String, member: FamilyMember)) {
        let result = ActionPerformer().perform(
            .activate, on: target.member.record, resolved: target.member.resolved)
        switch result {
        case .succeeded:
            showOutcome = "\(target.name) was brought to the front."
        case .failed(let reason), .withheld(let reason):
            showOutcome = reason
        }
    }

    @ViewBuilder
    private func icon(
        forKind kind: PopoverPresentation.ContributorRow.Kind, executablePath: String?
    ) -> some View {
        switch kind {
        case .application:
            if let icon = store.icon(forExecutablePath: executablePath) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").foregroundStyle(.secondary)
            }
        case .unattributed:
            Image(systemName: "lock").foregroundStyle(.secondary)
        case .other:
            Image(systemName: "square.stack").foregroundStyle(.secondary)
        }
    }
}

/// One cell of the four-up strip.
private struct MetricTileView: View {
    let tile: PopoverPresentation.MetricTile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(tile.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(tile.value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tile.isAvailable ? .primary : .secondary)
                    .lineLimit(1)
            }
            if let fraction = tile.barFraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
        .help(tile.detail)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.label): \(tile.value)")
        .accessibilityHint(tile.detail)
    }
}
