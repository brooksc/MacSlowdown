import Metrics
import SwiftUI

/// Current inventory of applications and processes (FR-002), with search (FR-027).
struct ProcessInventoryView: View {
    let store: MonitorStore
    @State private var query = ""
    /// Selection is keyed by family id (bundle path, or pid+start time for a
    /// standalone process), not by row index. Rows reorder every sample as usage
    /// changes, so an index-based selection would jump to a different application
    /// on each refresh (FR-027).
    @State private var selection: ProcessFamily.ID?
    /// Column sort order (FR-027). Held here rather than in the store because it
    /// is a view preference, not a measurement — changing it must not touch
    /// sampling.
    @State private var sortOrder = Presentation.defaultSortOrder

    private var rows: [MonitorStore.FamilyRow] {
        let ranked = store.rankedFamilies
        let matching = query.isEmpty ? ranked : ranked.filter {
            $0.family.displayName.localizedCaseInsensitiveContains(query)
        }
        return Presentation.sorted(matching, by: sortOrder)
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
                table
            }
        }
        .navigationTitle("Apps & Processes")
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Application", value: \.family.displayName) { row in
                HStack(spacing: 6) {
                    // Decoration only: the name carries the meaning, so a missing
                    // icon costs nothing and VoiceOver ignores it (FR-034).
                    if let icon = store.icon(for: row.family) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                    Text(row.family.displayName)
                    if row.family.hasUncertainMembers {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .help("Some processes are grouped here by path but their code "
                                  + "signature does not confirm it.")
                            .accessibilityLabel("Contains uncertain groupings")
                    }
                    if row.family.notMeasurableCount > 0 {
                        Text("\(row.family.notMeasurableCount) not measurable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("CPU", value: \.percentOfOneCore) { row in
                Text(CPUPresentation.percentOfOneCore(row.percentOfOneCore))
                    .monospacedDigit()
                    .accessibilityLabel(
                        "\(row.family.displayName): "
                        + "\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core")
            }
            TableColumn("Resident memory", value: \.residentBytes) { row in
                Text(row.residentBytes == 0
                     ? "—"
                     : ByteCountFormatStyle().format(Int64(row.residentBytes)))
                    .monospacedDigit()
            }
            TableColumn("Processes", value: \.processCount) { row in
                Text("\(row.family.members.count)").monospacedDigit()
            }
        }
        .searchable(text: $query, prompt: "Search applications")
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(CPUPresentation.convention())
            if let note = CPUPresentation.topologyNote() {
                Text(note)
            }
            Text("Resident memory. Activity Monitor's Memory column shows a different "
                 + "measure (footprint), so the numbers will not match exactly.")
            Text("Per-app disk activity is not available to App Store apps.")
            Text("Click a column heading to sort. Sorting changes the order only — "
                 + "no application is hidden by it.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}
