#if DEBUG
import Metrics
import SwiftUI

/// Previews for the contributor table that Now and Overview share.
///
/// **Why this file exists.** The table is a hand-built `HStack` grid rather than a
/// `Table`, and the row that broke — "System processes", carrying a count and a
/// badge beside its name — only appears on a machine with other-uid processes to
/// aggregate. No unit test constructs it, and the previews written so far covered
/// `AllProcessesView`, so the first time anybody saw it was a VM screenshot on
/// 2026-09-16, where it had rendered its subtitle and badge at roughly one
/// character per line (`TASK-118`).
///
/// The rows below are placeholders in their numbers and deliberate in their
/// shapes: the system aggregate with the longest badge the product can produce, a
/// family with children, a name long enough to have to truncate somewhere, and a
/// row with nothing retained, which must read as "no readings" and never as zero.
///
/// A preview answers layout and only layout. It cannot answer what the running
/// app does under `LSUIElement`, and a render here must never be offered as
/// evidence for that.

private func usage(mean: Double, peak: Double, samples: Int = 58) -> TrailingUsage {
    TrailingUsage(meanPercentOfOneCore: mean, peakPercentOfOneCore: peak,
                  sampleCount: samples, span: .seconds(60))
}

/// The system aggregate, built exactly as `InventoryRow.tree` builds it —
/// `isMeasurable: true` and `residentBytes: 0`, because FR-055's total is a
/// measured difference between host busy and everything we could read, while no
/// memory figure exists for it at all.
@MainActor private let systemProcesses = InventoryRow(
    id: "system",
    trailing: usage(mean: 5.6, peak: 11.2),
    name: "System processes",
    executablePath: nil,
    kind: .systemProcesses,
    percentOfOneCore: 4.9,
    residentBytes: 0,
    isMeasurable: true,
    // The real count from a sandboxed sweep, not an invented one.
    processCount: 286,
    qualification: nil,
    children: [])

/// The worst name cell the product can produce: a count *and* two badges, which
/// is what a row gets when it is both the system aggregate and unreadable. It is
/// reachable only if FR-055's total ever became unavailable, so this is a
/// stress case rather than the ordinary one — kept because it is where the name
/// cell runs out of room first.
@MainActor private let systemProcessesUnreadable = InventoryRow(
    id: "system-unreadable",
    trailing: nil,
    name: "System processes",
    executablePath: nil,
    kind: .systemProcesses,
    percentOfOneCore: 0,
    residentBytes: 0,
    isMeasurable: false,
    processCount: 286,
    qualification: nil,
    children: [])

@MainActor private let ours = InventoryRow(
    id: "macslowdown",
    trailing: usage(mean: 9.0, peak: 14.1),
    name: "MacSlowdown",
    executablePath: "/Applications/MacSlowdown.app/Contents/MacOS/MacSlowdown",
    kind: .application,
    percentOfOneCore: 9.0,
    residentBytes: 128 * 1024 * 1024,
    isMeasurable: true,
    processCount: 1,
    qualification: nil,
    children: [])

/// A family with children and a long name — the two things that squeeze the name
/// cell at once.
@MainActor private let browser = InventoryRow(
    id: "brave",
    trailing: usage(mean: 62.4, peak: 140.8),
    name: "Brave Browser",
    executablePath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    kind: .application,
    percentOfOneCore: 38.2,
    residentBytes: 2_400 * 1024 * 1024,
    isMeasurable: true,
    processCount: 27,
    qualification: nil,
    children: [
        InventoryRow(
            id: "brave-renderer",
            trailing: nil,
            name: "Brave Browser Helper (Renderer)",
            executablePath: nil,
            kind: .member,
            percentOfOneCore: 22.1,
            residentBytes: 620 * 1024 * 1024,
            isMeasurable: true,
            processCount: 1,
            qualification: "Grouped by guess",
            children: []),
    ])

/// Nothing retained for it yet — an em dash, never a zero (FR-002).
@MainActor private let fresh = InventoryRow(
    id: "just-launched",
    trailing: nil,
    name: "com.apple.WebKit.WebContent.Development",
    executablePath: nil,
    kind: .application,
    percentOfOneCore: 3.4,
    residentBytes: 958 * 1024 * 1024,
    isMeasurable: true,
    processCount: 4,
    qualification: nil,
    children: [])

/// The table as Now and Overview draw it, header included, so the columns can be
/// checked against their headings.
///
/// Every preview below pins the frame's alignment to `.leading`, because the app
/// does: the table sits in a `VStack` inside a scroll view, pinned leading. A
/// centred preview frame clips an oversized row on *both* sides and reads as a
/// defect in the table when it is an artefact of the preview.
@MainActor private struct ContributorTablePreview: View {
    var rows: [InventoryRow] = [browser, ours, systemProcesses, fresh]
    var age: String?
    @State private var expanded: Set<String> = []

    private let store = MonitorStore(
        policies: PolicyStore(),
        storage: StorageScreenModel(history: StorageHistory()),
        // Never the real container: a preview must not read or write the running
        // user's recorded incidents.
        incidentHistory: IncidentHistoryStore(url: nil),
        evidenceDirectory: nil)

    var body: some View {
        // Wrapped exactly as Now and Overview wrap it, or a preview would be
        // measuring a layout the app does not use.
        VStack(alignment: .leading, spacing: 0) {
            ContributorHeader()
            Divider()
            ForEach(rows) { row in
                ContributorRow(
                    row: row, store: store,
                    isExpanded: expanded.contains(row.id),
                    toggle: {
                        if expanded.contains(row.id) { expanded.remove(row.id) }
                        else { expanded.insert(row.id) }
                    },
                    age: age)
                if expanded.contains(row.id) {
                    ForEach(row.children) { child in
                        ContributorRow(row: child, store: store, isExpanded: false,
                                       toggle: {}, isChild: true, age: age)
                    }
                }
                Divider()
            }
        }
    }
}

/// The default width, and the one to read for `TASK-118`: the "System processes"
/// row's name, its "286 processes" count and its "Can't be broken down" badge must
/// each sit on one line, and the row must be the height of an ordinary row.
#Preview("Now table — default width") {
    ContributorTablePreview()
        .frame(width: 900, height: 320, alignment: .leading)
}

/// `TASK-118` AC#4. The window's minimum is 480 pt and the sidebar takes some of
/// it, so this is narrower than the table can ever actually be asked to be.
#Preview("Now table — 480 pt, the window minimum") {
    ContributorTablePreview()
        .frame(width: 480, height: 320, alignment: .leading)
}

#Preview("Now table — 620 pt") {
    ContributorTablePreview()
        .frame(width: 620, height: 320, alignment: .leading)
}

/// Expanded, so a child row's indent and its "Not retained" cell can be read.
#Preview("Now table — a family expanded") {
    ContributorTablePreview(rows: [browser, systemProcesses])
        .frame(width: 900, height: 260, alignment: .leading)
}

/// While readings are late. The age column is reserved unconditionally, so this
/// must not shift any other column relative to its heading (TASK-96 finding 14).
#Preview("Now table — readings are late") {
    ContributorTablePreview(age: "12 s ago")
        .frame(width: 900, height: 320, alignment: .leading)
}

/// The name cell at its worst: a count and two badges on one row. Nothing may
/// wrap here either — truncation is a legible way to run out of room, vertical
/// text is not.
#Preview("Now table — a row with count and two badges") {
    ContributorTablePreview(rows: [systemProcessesUnreadable, ours])
        .frame(width: 900, height: 200, alignment: .leading)
}
#endif
