import Metrics
import SwiftUI

/// Compact persistent status surface (FR-001). Design reference: 1a.
///
/// Reassurance first, numbers second. The popover answers "is my Mac all right?"
/// in a sentence, proves that monitoring is actually running, and only then shows
/// figures — a severity word over a table answers a question nobody asked.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            verdict

            Divider()

            metricStrip

            contributors

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

    @ViewBuilder
    private func icon(for row: PopoverPresentation.ContributorRow) -> some View {
        switch row.kind {
        case .application:
            // Nil means "no icon", never a generic placeholder standing in for one.
            if let icon = store.icon(forExecutablePath: row.executablePath) {
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

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 6) {
            Button("Open MacSlowdown") {
                openWindow(id: MainWindow.id)
                ActivationPolicy.mainWindowOpened()
            }
            .keyboardShortcut("o")
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            // Deliberate divergence from design 1a, which shows no Quit. The menu
            // bar item is the primary surface and the app has no Dock icon by
            // default, so without this there is no way to quit.
            Button("Quit MacSlowdown") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .frame(maxWidth: .infinity)
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
