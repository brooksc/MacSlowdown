import Metrics
import SwiftUI

/// Current inventory of applications and processes (FR-002), with search (FR-027)
/// and per-family expansion (FR-003).
///
/// Collapsed by default. The question a user has is "which application is using
/// the most", and a flat list of 800 processes buries that under helpers. The
/// aggregate answers it; the expansion explains it.
struct ProcessInventoryView: View {
    let store: MonitorStore
    @State private var query = ""
    /// Selection and expansion are both keyed on row identity, never row index.
    /// Rows reorder on every sample, so anything index-based would act on a
    /// different application after each refresh (FR-027).
    @State private var selection: InventoryRow.ID?
    @State private var expanded: Set<InventoryRow.ID> = []
    @State private var sortOrder = Presentation.defaultInventorySort


    private var rows: [InventoryRow] {
        let all = store.inventory
        let matching = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.children.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return Presentation.sortedInventory(matching, by: sortOrder)
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

    private func expansion(for id: InventoryRow.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            })
    }

    private var table: some View {
        Table(of: InventoryRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Application", value: \.name) { row in
                nameCell(row)
            }
            TableColumn("CPU", value: \.cpuSortKey) { row in
                measurement(row) {
                    CPUPresentation.percentOfOneCore(row.percentOfOneCore)
                }
            }
            TableColumn("Resident memory", value: \.memorySortKey) { row in
                measurement(row) {
                    row.residentBytes == 0
                        ? "—" : ByteCountFormatStyle().format(Int64(row.residentBytes))
                }
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
        .searchable(text: $query, prompt: "Search applications")
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

            if let qualification = row.qualification {
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
        if let qualification = row.qualification { parts.append(qualification) }
        if row.kind != .member { parts.append("\(row.processCount) processes") }
        parts.append(row.isMeasurable
            ? "\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core"
            : "usage unavailable")
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
            Text(CPUPresentation.convention())
            if let note = CPUPresentation.topologyNote() {
                Text(note)
            }
            Text("Resident memory. Activity Monitor's Memory column shows a different "
                 + "measure (footprint), so the numbers will not match exactly.")
            Text("Per-app disk activity is not available to App Store apps.")
            Text("Click a column heading to sort, or a triangle to see the individual "
                 + "processes an application is running.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}
