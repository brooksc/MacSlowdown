import Metrics
import SwiftUI

/// Open and recent incidents (FR-011, FR-012). Design reference: 1f.
struct IncidentsView: View {
    let store: MonitorStore
    @State private var selection: Incident.ID?

    private var all: [Incident] {
        (store.openIncident.map { [$0] } ?? []) + store.recentIncidents
    }

    /// True when a row is selected. Written as a real binding rather than
    /// `.constant`: `inspector(isPresented:)` writes back through it when the
    /// inspector is dismissed, and a constant binding silently swallows that
    /// write, leaving SwiftUI's presentation state and ours disagreeing about
    /// whether a column exists.
    ///
    /// Changed while chasing TASK-51.1, where this column rendered nothing on
    /// screen. That it *caused* the blank pane is a hypothesis, not a
    /// measurement: the blank state could not be reproduced offscreen. What is
    /// established is that this was the only unsupported construct here, and
    /// that a hidden inspector column is one of the few things that can leave a
    /// detail column with its title and no body.
    private var inspectorShown: Binding<Bool> {
        Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })
    }

    var body: some View {
        Group {
            if all.isEmpty {
                empty
            } else {
                // No `navigationDestination(for: Incident.ID.self)` here. It used
                // to register `EmptyView()` on the detail column's stack, and a
                // `List(selection:)` whose selection type has a registered
                // destination is SwiftUI's "selection pushes a screen" pattern —
                // so selecting a row could replace the whole column with nothing
                // instead of opening the inspector. Selection drives the
                // inspector, and nothing in the app pushes an incident.
                List(all, selection: $selection) { incident in
                    IncidentRow(incident: incident)
                        .tag(incident.id)
                }
            }
        }
        .navigationTitle("Incidents")
        .inspector(isPresented: inspectorShown) {
            if let incident = all.first(where: { $0.id == selection }) {
                IncidentDetailView(incident: incident, store: store)
                    .inspectorColumnWidth(min: 380, ideal: 460)
            }
        }
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
                Text(incident.conditions.map(\.label).sorted().joined(separator: " and "))
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .accessibilityLabel("\(incident.severity.label) incident: "
                            + "\(incident.conditions.map(\.label).sorted().joined(separator: " and ")). "
                            + subtitle)
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
        return incident.isOpen
            ? "\(started) · still going · \(length) so far"
            : "\(started) · \(length) · recovered"
    }
}
