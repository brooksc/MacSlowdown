import Metrics
import SwiftUI

/// Open and recent incidents, with the pattern across them (FR-011, FR-012).
/// Design reference: 1f.
///
/// The list is the smaller half of this screen. One incident is an event; several
/// sharing a condition is a finding, which is what the summary above the list is
/// for — and it is stated only when the data supports it (see `IncidentHistory`).
struct IncidentsView: View {
    let store: MonitorStore
    @State private var range: IncidentHistory.Range = .week
    @State private var selection: Incident.ID?

    /// Everything recorded, regardless of range, so the empty state can tell
    /// "nothing has happened" apart from "nothing happened this week".
    private var all: [Incident] {
        (store.openIncident.map { [$0] } ?? []) + store.recentIncidents
    }

    private var entries: [IncidentHistory.Entry] {
        IncidentHistory.entries(
            open: store.openIncident,
            recent: store.recentIncidents,
            // Lifecycle findings belong in this list (design 1f, row four).
            //
            // TASK-65.6 built the row and left this empty because nothing published
            // patterns; TASK-66 then wired the real `LifecycleTracker` into the
            // store. Connected here, at the seam between the two.
            //
            // Bounded by the tracker's window, so an app that crashed repeatedly
            // before monitoring started does not appear. That is a limit of what we
            // watched, not a claim the app is healthy.
            relaunches: store.relaunchPatterns,
            range: range)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if all.isEmpty {
                empty
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                Divider()
                list
            }
            Divider()
            footer
        }
        // The fix for the blank pane, and it is not cosmetic. Measured on screen
        // 2026-08-09 with the window at a correct 900x600: the detail column was
        // 900x600 at y=271 and the split view `.inspector` builds inside it was
        // **900x4085 at y=-1445** — 1716 pt above the window and 2369 pt below.
        // Every element was present in the accessibility tree and drawn, just
        // outside the visible slice, with the header at the top of that 4085 pt
        // layout and the footer at the bottom. That is why the title and toolbar
        // appeared (they belong to the window) while even the *unconditional*
        // Divider and footer did not.
        //
        // Same pathology as TASK-75 — caption text under `fixedSize` answers with
        // thousands of points when nothing proposes a width — but the thing that
        // grew here is the inspector's split view, not the window, so TASK-75's
        // bound on `detailPane` in `MainWindowView` did not reach it. `.inspector`
        // has to be attached to content that already knows its own bounds.
        //
        // This also explains why sixteen offscreen configurations drew correctly:
        // an `NSHostingView` supplies the height, so the split view could never
        // demand one.
        .frame(minHeight: 320, idealHeight: 480, maxHeight: .infinity)
        .navigationTitle("Incidents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    ForEach(IncidentHistory.Range.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Time range")
            }
        }
        .inspector(isPresented: inspectorPresented) {
            if let incident = all.first(where: { $0.id == selection }) {
                IncidentDetailView(incident: incident, store: store,
                                   samples: store.retainedSamples(around: incident))
                    .inspectorColumnWidth(min: 380, ideal: 460)
            }
        }
    }

    /// A real two-way binding. `.constant` here would discard SwiftUI's write-back
    /// when the inspector is dismissed, leaving its presentation state and ours
    /// disagreeing about whether a trailing column exists (see TASK-51.1).
    ///
    /// Two things this file must not regain, both removed while chasing TASK-51.1,
    /// where this column rendered its title and nothing else on screen:
    /// the `.constant` binding above, and a `navigationDestination(for:)`
    /// registering `EmptyView()`. A `List(selection:)` whose selection type has a
    /// registered destination is SwiftUI's "selection pushes a screen" pattern, so
    /// selecting a row could replace the whole column with nothing. Nothing in the
    /// app pushes an incident; selection drives the inspector.
    ///
    /// **That either construct caused the blank pane is a hypothesis, not a
    /// measurement.** The blank state could not be reproduced offscreen across 16
    /// configurations. If the pane is still blank when someone looks, this fix is
    /// wrong and the next lead is something only a live scene does.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { presented in if !presented { selection = nil } })
    }

    // MARK: - Summary and strip

    private var pattern: IncidentHistory.Pattern {
        IncidentHistory.pattern(for: entries, range: range)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.headline)
                    .font(.title3).bold()
                if let recurrence = pattern.recurrence {
                    Text(recurrence)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            // Application recurrence, now that incidents record their own
            // attribution (TASK-68). This is the finding design 1f is built around
            // — "Chrome appears in 5 of them" — and until incidents kept an
            // attribution it could not be computed at all, so the line above falls
            // back to recurrence of the *condition*.
            //
            // Shown as a `Conclusion` rather than a sentence so it carries the
            // confidence it was built from. That confidence is the weakest of the
            // records it came from, never an average: two low-confidence
            // attributions must not combine into a confident-looking pattern.
            ForEach(store.recurringApplications) { recurrence in
                ConclusionRow(conclusion: recurrence.conclusion)
            }

            DayStrip(days: IncidentHistory.days(for: entries, range: range))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("Nothing \(range.phrase)", systemImage: "calendar")
            } description: {
                Text("Earlier incidents are still recorded. Widen the range to see them.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries, selection: $selection) { entry in
                row(for: entry)
            }
        }
    }

    /// Selection identifies a resource incident, which is what the inspector can
    /// show. A lifecycle row carries no `Incident.ID`, so it is not tagged and is
    /// not selectable — its detail is a separate screen (TASK-65.15), and tagging
    /// it would open an empty inspector.
    @ViewBuilder
    private func row(for entry: IncidentHistory.Entry) -> some View {
        let content = IncidentRow(entry: entry)
        if case .resource(let incident) = entry.kind {
            content.tag(incident.id)
        } else {
            content
        }
    }

    // MARK: - Empty state and footer

    /// An empty list must say monitoring is running. "No incidents" alone could
    /// equally mean the app is broken.
    private var empty: some View {
        ContentUnavailableView {
            Label("No slowdowns recorded", systemImage: "checkmark.circle")
        } description: {
            Text(store.isRunning
                 ? "MacSlowdown is watching. Anything sustained enough to matter will "
                   + "appear here, with the evidence behind it."
                 : "Monitoring is not running, so nothing is being recorded.")
        }
    }

    /// FR-029: retention and the local-only guarantee, stated where the evidence is.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(IncidentHistory.retentionFooter(limit: MonitorStore.retainedIncidents))
            Text(IncidentHistory.attributionGap)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// When incidents fell across the range. Every column is also spoken, so the shape
/// is never the only carrier (FR-034).
struct DayStrip: View {
    let days: [IncidentHistory.Day]

    private var peak: Int { max(1, days.map(\.count).max() ?? 0) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 3) {
                    // A zero day still draws a baseline, so the strip reads as a
                    // calendar with nothing in it rather than as missing data.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.count == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint))
                        .frame(height: day.count == 0
                               ? 2
                               : max(4, 28 * Double(day.count) / Double(peak)))
                    Text(day.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.accessibilityLabel)
            }
        }
        .frame(height: 44, alignment: .bottom)
    }
}

struct IncidentRow: View {
    let entry: IncidentHistory.Entry

    /// Which application the row is about. Derived by `IncidentHistory.Entry`, not
    /// here: this view used to name the largest CPU contributor for every row,
    /// which is the wrong subject for a repeated-quit episode and disagreed with
    /// the detail inspector about the same incident (TASK-82).
    private var subject: IncidentHistory.Entry.Subject? { entry.subject }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Symbol and word together — severity is never colour alone (FR-034).
            Image(systemName: symbol)
                .imageScale(.large)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let caveat {
                    Text(caveat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let severity {
                Text(severity)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Copy

    /// Condition and application together, as the design states it — but the
    /// application appears only where one is actually known.
    private var title: String {
        switch entry.kind {
        case .resource(let incident):
            let conditions = incident.conditions.map(\.label).sorted().joined(separator: " and ")
            if let subject { return "\(conditions) — \(subject.text)" }
            return conditions
        case .repeatedQuits:
            // Sentence form, because this is a sentence: a bare "yes quit
            // repeatedly" reads as the English word (TASK-82). The verb comes from
            // `RepeatedQuitWording`, which is also where "unexpectedly" was removed
            // from — we cannot read an exit status, so we never claimed one
            // (TASK-84, FR-002).
            return RepeatedQuitWording.repeatedly(
                subject: subject?.sentenceTextAtStart ?? "A process")
        }
    }

    private var subtitle: String {
        switch entry.kind {
        case .resource(let incident):
            let started = incident.beganAt.formatted(date: .abbreviated, time: .shortened)
            let length = DateComponentsFormatter.incidentDuration
                .string(from: incident.duration.totalSeconds) ?? ""
            let elapsed = incident.isOpen ? "\(length) so far" : length
            return "\(started) · \(elapsed) · \(entry.outcome.label)"
        case .repeatedQuits(let pattern):
            let started = pattern.firstAt.formatted(date: .abbreviated, time: .shortened)
            return "\(started) · \(pattern.summary)"
        }
    }

    /// The caveat that cannot be separated from the claim (FR-013).
    private var caveat: String? {
        switch entry.kind {
        case .resource(let incident):
            // A lifecycle-only incident names the process that kept exiting, which
            // is a measured fact and not a contributor claim. Reusing the
            // contributor caveat there would attach "largest contributor" to a
            // process we never said was busy (TASK-82).
            guard let subject else { return nil }
            guard incident.narrative.narratesResourceAttribution else {
                return "We can see that it exited and started again, not why."
            }
            // Tense follows the incident, not the reader's clock. The subject comes
            // from `incident.attribution` — a figure recorded while the incident was
            // running — so saying "right now" about a slowdown that ended last
            // Tuesday claims a measurement of the present that we never took, and
            // about an application that may not even be running (FR-002, FR-038).
            // The past-tense wording matches `IncidentAttribution.conclusion`.
            guard incident.isOpen else {
                return "\(subject.text) was the largest measurable contributor while "
                    + "this was happening — heuristic, not a cause."
            }
            return "\(subject.text) is the largest contributor we can measure right "
                + "now — heuristic, not a cause."
        case .repeatedQuits(let pattern):
            return "We can see that it exited and started again, not why — "
                + "\(pattern.confidence.label)."
        }
    }

    private var severity: String? {
        if case .resource(let incident) = entry.kind { return incident.severity.label }
        return nil
    }

    private var symbol: String {
        switch entry.kind {
        case .resource(let incident):
            switch incident.severity {
            case .moderate: "exclamationmark.circle"
            case .high: "exclamationmark.triangle"
            case .severe: "exclamationmark.octagon"
            }
        case .repeatedQuits:
            "arrow.counterclockwise.circle"
        }
    }

    private var accessibilityLabel: String {
        let prefix = severity.map { "\($0) incident: " } ?? ""
        // An ellipsis conveys nothing to VoiceOver, so a name the kernel shortened
        // is said to be shortened — the same treatment `AllProcessesView` and
        // `ProcessInventoryView` already give it (FR-002, FR-034, TASK-81).
        var spoken = prefix + title + ". " + subtitle + (caveat.map { " \($0)" } ?? "")
        if let subject, subject.isShortenedCommand {
            spoken += " \(subject.accessibilityText), \(ProcessNaming.truncationNote)."
        }
        return spoken
    }
}
