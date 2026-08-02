import Metrics
import SwiftUI

/// Current inventory of applications and processes (FR-002), with search (FR-027).
struct ProcessInventoryView: View {
    let store: MonitorStore
    @State private var query = ""

    private var rows: [MonitorStore.FamilyRow] {
        let ranked = store.rankedFamilies
        guard !query.isEmpty else { return ranked }
        return ranked.filter {
            $0.family.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Application") { row in
                HStack(spacing: 6) {
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
            TableColumn("CPU") { row in
                Text(CPUPresentation.percentOfOneCore(row.percentOfOneCore))
                    .monospacedDigit()
            }
            TableColumn("Resident memory") { row in
                Text(row.residentBytes == 0
                     ? "—"
                     : ByteCountFormatStyle().format(Int64(row.residentBytes)))
                    .monospacedDigit()
            }
            TableColumn("Processes") { row in
                Text("\(row.family.members.count)").monospacedDigit()
            }
        }
        .searchable(text: $query, prompt: "Search applications")
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Apps & Processes")
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
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}
