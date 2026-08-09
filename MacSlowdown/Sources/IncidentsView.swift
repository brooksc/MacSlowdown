import Metrics
import SwiftUI

/// Open and recent incidents (FR-011, FR-012). Design reference: 1f.
struct IncidentsView: View {
    let store: MonitorStore
    @State private var selection: Incident.ID?

    private var all: [Incident] {
        (store.openIncident.map { [$0] } ?? []) + store.recentIncidents
    }

    var body: some View {
        Group {
            if all.isEmpty {
                empty
            } else {
                List(selection: $selection) {
                    ForEach(all) { incident in
                        IncidentRow(incident: incident)
                            .tag(incident.id)
                    }
                    if !store.recurringApplications.isEmpty {
                        Section("What keeps coming up") {
                            ForEach(store.recurringApplications) { recurrence in
                                ConclusionRow(conclusion: recurrence.conclusion)
                            }
                        }
                    }
                    Section { retentionFooter }
                }
                .navigationDestination(for: Incident.ID.self) { _ in EmptyView() }
            }
        }
        .navigationTitle("Incidents")
        .inspector(isPresented: .constant(selection != nil)) {
            if let incident = all.first(where: { $0.id == selection }) {
                IncidentDetailView(incident: incident, store: store)
                    .inspectorColumnWidth(min: 380, ideal: 460)
            }
        }
    }

    /// The real retention behaviour, stated rather than implied (FR-005).
    ///
    /// History is 20 incidents held in memory. Whether incidents should persist
    /// across restarts, and for how long, is an open product decision — so this
    /// describes what the app does today and claims no retention period it does
    /// not keep.
    private var retentionFooter: some View {
        Text("The last \(MonitorStore.retainedIncidents) slowdowns are kept, in memory only. "
             + "They are not saved to disk, so quitting MacSlowdown clears them.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

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
}

struct IncidentRow: View {
    let incident: Incident

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
                // The name above is a heuristic, and the label saying so travels
                // with it rather than living in a footnote (FR-013, FR-038).
                if let attributed {
                    Text("\(Evidence.heuristic.label) · \(attributed.confidence.label) — "
                         + "largest measurable contributor, not a proven cause")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(incident.outcome.statement.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(incident.severity.label)
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The recorded attribution, which exists for closed incidents as much as open
    /// ones because it was captured while the incident was happening. Nothing here
    /// reads live state.
    private var attributed: IncidentAttribution? { incident.attribution }

    private var conditions: String {
        incident.conditions.map(\.label).sorted().joined(separator: " and ")
    }

    /// The design's "CPU maxed out — Xcode", now derivable after the fact. The name
    /// is omitted rather than guessed when nothing measurable was attributed.
    private var title: String {
        guard let application = attributed?.leadingApplication else { return conditions }
        return "\(conditions) — \(application.displayName)"
    }

    private var accessibilityLabel: String {
        var label = "\(incident.severity.label) incident: \(conditions). \(subtitle)."
        if let attributed, let application = attributed.leadingApplication {
            label += " \(application.displayName) was the largest measurable contributor, "
            label += "\(attributed.confidence.label), not a proven cause."
        }
        label += " \(incident.outcome.statement.text)"
        return label
    }

    private var symbol: String {
        switch incident.severity {
        case .moderate: "exclamationmark.circle"
        case .high: "exclamationmark.triangle"
        case .severe: "exclamationmark.octagon"
        }
    }

    private var subtitle: String {
        let started = incident.beganAt.formatted(date: .abbreviated, time: .shortened)
        let length = DateComponentsFormatter.incidentDuration
            .string(from: incident.duration.totalSeconds) ?? ""
        // How it ended is stated once, by `outcome`, rather than here as well —
        // the two disagreed as soon as an action could be recorded against an
        // incident.
        return incident.isOpen ? "\(started) · \(length) so far" : "\(started) · \(length)"
    }
}
