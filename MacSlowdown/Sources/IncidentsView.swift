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
            // Lifecycle findings belong in this list (design 1f, row four) and the
            // row below renders them. Nothing publishes them yet: `MonitorStore`
            // does not run a `LifecycleTracker`, so today this is always empty.
            // Recorded in the task notes rather than faked here.
            relaunches: [],
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
                IncidentDetailView(incident: incident, store: store)
                    .inspectorColumnWidth(min: 380, ideal: 460)
            }
        }
    }

    /// A real two-way binding. `.constant` here would discard SwiftUI's write-back
    /// when the inspector is dismissed, leaving its presentation state and ours
    /// disagreeing about whether a trailing column exists (see TASK-51.1).
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
        let content = IncidentRow(
            entry: entry, leadingContributor: leadingContributor(for: entry))
        if case .resource(let incident) = entry.kind {
            content.tag(incident.id)
        } else {
            content
        }
    }

    /// Only an open incident can name an application, and only as the largest
    /// contributor we can measure *right now* — the incident record itself stores
    /// no attribution. Labelled as a heuristic in the row (FR-013, FR-038).
    private func leadingContributor(for entry: IncidentHistory.Entry) -> String? {
        guard entry.isOpen else { return nil }
        return store.attribution?.contributors.first?.label
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
    /// Present only for an open incident, and only as a measured-now leader.
    var leadingContributor: String?

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
            if let leadingContributor { return "\(conditions) — \(leadingContributor)" }
            return conditions
        case .repeatedQuits(let pattern):
            return "\(pattern.command) quit unexpectedly, repeatedly"
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
        case .resource:
            guard let leadingContributor else { return nil }
            return "\(leadingContributor) is the largest contributor we can measure right "
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
        return prefix + title + ". " + subtitle + (caveat.map { " \($0)" } ?? "")
    }
}
