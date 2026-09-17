import Metrics
import SwiftUI

/// Every process on the machine, flat (FR-002, FR-027).
///
/// The peer of the application view. Its whole job is to be honest about the two
/// thirds of the table an application-grouped list cannot show: processes that
/// belong to no application, and processes whose CPU and memory macOS refuses to
/// report to an App Store app.
struct AllProcessesView: View {
    let rows: [AllProcessesRow]
    let census: ProcessCensus
    /// How old the reading is, in words. Shared with the Apps footer so the two
    /// halves of the screen cannot disagree about when we last looked.
    let freshness: String
    @Binding var query: String
    @Binding var showsUnmeasurable: Bool
    @Binding var sortOrder: [KeyPathComparator<AllProcessesRow>]
    let icon: (String?) -> NSImage?

    @State private var selection: AllProcessesRow.ID?
    /// The two sections are damped separately, because they are two ordered lists
    /// (TASK-74). Unmeasurable rows all share one sort key and are held by the name
    /// tie-break, so damping costs them nothing and covers them if that ever changes.
    @State private var measurableOrder = StableOrder<AllProcessesRow>()
    @State private var unmeasurableOrder = StableOrder<AllProcessesRow>()
    @State private var listing = AllProcessesListing(measurable: [], unmeasurable: [])

    /// The ranking, from the newest rows. `listing` is this, settled.
    private var ranked: AllProcessesListing {
        AllProcesses.listing(rows, query: query, by: sortOrder)
    }

    /// Fresh rows every time; only their sequence is held.
    private func refreshListing(userAsked: Bool = false) {
        if userAsked {
            measurableOrder.reset()
            unmeasurableOrder.reset()
        }
        let ranked = ranked
        listing = AllProcessesListing(
            measurable: measurableOrder.settle(ranked.measurable),
            unmeasurable: unmeasurableOrder.settle(ranked.unmeasurable))
    }

    var body: some View {
        Table(of: AllProcessesRow.self, selection: $selection, sortOrder: $sortOrder) {
            // **Every column states its width, and that is load-bearing.** With no
            // widths declared, SwiftUI divided the table evenly: a three-character
            // CPU reading got as much room as the process name, names truncated at
            // about twenty characters (TASK-65.22), and below roughly 560 pt the
            // table stopped drawing altogether — no headers, no rows, no footer,
            // no error (TASK-117). Measured, not guessed: 720, 640 and 580 pt drew;
            // 540 and 504 pt came back blank, at a window whose minimum is 480 pt.
            //
            // The minimums below sum to less than that 480 pt minimum so the blank
            // state is unreachable, and the name column takes all the slack because
            // it is the column carrying the content.
            TableColumn("Process", value: \.name) { row in
                nameCell(row)
            }
            .width(min: 140, ideal: 220)
            // The numeric columns are sized by "Not measurable", not by their
            // numbers: an other-uid process has no CPU or memory reading and says
            // so in words rather than showing a zero that would be a fabricated
            // measurement (FR-002, FR-038). That phrase is what sets these floors.
            TableColumn("CPU", value: \.cpuSortKey) { row in
                measurement(row.cpuText, isMeasurable: row.isMeasurable)
            }
            .width(min: 100, ideal: 104, max: 120)
            TableColumn("Resident memory", value: \.memorySortKey) { row in
                measurement(row.memoryText, isMeasurable: row.isMeasurable)
            }
            .width(min: 100, ideal: 112, max: 150)
            TableColumn("PID", value: \.pidSortKey) { row in
                Text("\(row.pid)").monospacedDigit()
            }
            .width(min: 50, ideal: 58, max: 80)
            TableColumn("Started", value: \.startedSortKey) { row in
                Text(row.startedAt, format: .dateTime.hour().minute()).monospacedDigit()
            }
            .width(min: 58, ideal: 64, max: 90)
        } rows: {
            ForEach(listing.measurable) { TableRow($0) }

            if showsUnmeasurable && !listing.unmeasurable.isEmpty {
                Section {
                    ForEach(listing.unmeasurable) { TableRow($0) }
                } header: {
                    unmeasurableHeader(listing)
                }
            }
        }
        .overlay {
            // The same rule as the application scope: an empty list must say what
            // was searched and over how much, never just stop.
            if listing.measurable.isEmpty && listing.unmeasurable.isEmpty && !query.isEmpty {
                ContentUnavailableView {
                    Label("Nothing matches “\(query)”", systemImage: "magnifyingglass")
                } description: {
                    Text("None of the \(census.total) processes running matches — including "
                         + "the \(census.notMeasurable) whose CPU and memory macOS does not "
                         + "report to us. They were searched by name.")
                }
                .background(.background)
            } else if !showsUnmeasurable && listing.measurable.isEmpty
                        && !listing.unmeasurable.isEmpty {
                ContentUnavailableView {
                    Label("Only unmeasurable processes match", systemImage: "lock")
                } description: {
                    Text("\(listing.unmeasurable.count) matching "
                         + "\(listing.unmeasurable.count == 1 ? "process is" : "processes are") "
                         + "hidden. Turn on Show unmeasurable to see them.")
                }
                .background(.background)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .onAppear { refreshListing(userAsked: true) }
        // `rows` is rebuilt from the newest sample by the parent, so a change in it
        // is a new sample. Comparing it is how this view learns that without
        // reaching into the store.
        .onChange(of: rows) { _, _ in refreshListing() }
        .onChange(of: sortOrder) { _, _ in refreshListing(userAsked: true) }
        .onChange(of: query) { _, _ in refreshListing(userAsked: true) }
    }

    /// The rule stated on the screen, where the user meets it, rather than in a
    /// help article they will not read.
    private func unmeasurableHeader(_ listing: AllProcessesListing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(listing.unmeasurableHeading).font(.headline)
            Text(AllProcessesListing.unmeasurableRule)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(listing.unmeasurableHeading). \(AllProcessesListing.unmeasurableRule)")
    }

    @ViewBuilder
    private func nameCell(_ row: AllProcessesRow) -> some View {
        HStack(spacing: 6) {
            if row.isMeasurable, let image = icon(row.executablePath) {
                // Decoration only: the name carries the meaning, so VoiceOver
                // ignores it (FR-034).
                Image(nsImage: image)
                    .resizable().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else if !row.isMeasurable {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(row))
    }

    private func accessibilityLabel(_ row: AllProcessesRow) -> String {
        var parts = [row.name]
        // The ellipsis in `row.name` is silent to VoiceOver, so the cut is said in
        // words instead (FR-002, FR-034).
        if row.nameIsShortened { parts.append(ProcessNaming.truncationNote) }
        if let subtitle = row.subtitle { parts.append(subtitle) }
        parts.append(row.isMeasurable
            ? "\(row.cpuText) of one core, \(row.memoryText) resident"
            : "CPU and memory not measurable")
        parts.append("PID \(row.pid)")
        return parts.joined(separator: ", ")
    }

    /// FR-002: a value we were refused reads as refused, never as a number and
    /// never as a blank cell a user could take for zero.
    @ViewBuilder
    private func measurement(_ text: String, isMeasurable: Bool) -> some View {
        if isMeasurable {
            Text(text).monospacedDigit()
        } else {
            Text(text)
                .foregroundStyle(.secondary)
                .help("macOS does not report this process's CPU or memory to App Store apps. "
                      + "The limit is process ownership, not the sandbox.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(census.summary).bold()
                Text(freshness)
            }
            .accessibilityElement(children: .combine)
            Text("Resident memory. Activity Monitor's Memory column shows a different "
                 + "measure (footprint), so the numbers will not match exactly.")
            Text(OrderStability.explanation)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}

/// The empty state for a search of the applications that found nothing (FR-027).
///
/// Never "No results". It says why the list is empty in terms of how processes are
/// grouped, reports what the same search finds among all processes, and offers to
/// go there with the term intact.
struct InventorySearchEmptyView: View {
    let outcome: InventorySearchOutcome
    let switchScope: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(outcome.title, systemImage: "magnifyingglass")
            } description: {
                Text(outcome.message)
            } actions: {
                if let actionTitle = outcome.actionTitle {
                    Button(actionTitle, action: switchScope)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(outcome.countSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(outcome.accessibilityDescription)
    }
}
