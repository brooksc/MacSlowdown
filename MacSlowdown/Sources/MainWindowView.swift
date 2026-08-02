import Metrics
import SwiftUI

struct MainWindowView: View {
    let store: MonitorStore
    @State private var selection: Section = .now

    enum Section: String, CaseIterable, Identifiable {
        case now = "Now"
        case apps = "Apps & Processes"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .now: "gauge.with.dots.needle.33percent"
            case .apps: "square.grid.2x2"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .now: NowView(store: store)
            case .apps: ProcessInventoryView(store: store)
            }
        }
        .onAppear { ActivationPolicy.mainWindowOpened() }
        .onDisappear { ActivationPolicy.mainWindowClosed() }
    }
}

/// Current condition at a glance, with the numbers underneath.
struct NowView: View {
    let store: MonitorStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let explanation = store.enumeration.explanation {
                    enumerationBanner(explanation)
                }
                if case .stale(let age) = store.freshness {
                    staleBanner(age: age)
                }

                if let attribution = store.attribution {
                    condition(attribution)
                    figures(attribution)
                    Text(attribution.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ContentUnavailableView(
                        "Taking the first reading",
                        systemImage: "gauge.with.dots.needle.33percent",
                        description: Text("CPU is measured between two samples, so the first "
                                          + "figure appears after one interval."))
                }

                machineFooter
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Now")
    }

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

    private func condition(_ attribution: CPUAttribution) -> some View {
        HStack(spacing: 10) {
            Image(systemName: store.severity.symbolName).imageScale(.large)
            VStack(alignment: .leading) {
                Text(store.severity.label).font(.title2).bold()
                Text(CPUPresentation.machineRelative(attribution.totalBusyPercentOfOneCore))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Every figure with its evidence class, so a calculated remainder is never
    /// shown as though it were read from a counter (FR-038).
    private func figures(_ attribution: CPUAttribution) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(attribution.figures.enumerated()), id: \.offset) { _, figure in
                GridRow {
                    Text(figure.label)
                    Text(CPUPresentation.percentOfOneCore(figure.percentOfOneCore))
                        .monospacedDigit()
                    Text(figure.evidence.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Read as one sentence including the evidence class, so a
                // VoiceOver user gets the same caveat a sighted user sees.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(figure.label): "
                    + "\(CPUPresentation.percentOfOneCore(figure.percentOfOneCore)) of one core, "
                    + "\(figure.evidence.rawValue)")
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var machineFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(store.machine.hardwareModel) · \(store.machine.architecture) · "
                 + "\(store.machine.logicalCores) cores · "
                 + String(format: "%.0f GB", store.machine.physicalMemoryGB))
            Text(store.machine.osVersion)
            Text(CPUPresentation.convention())
            if let note = CPUPresentation.topologyNote() {
                Text(note).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
