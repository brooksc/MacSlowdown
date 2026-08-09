import Foundation
import Metrics
import Observation

/// What the user says an incident was (FR-039).
///
/// The case for this exists precisely where our own measurement stops. When most
/// of a slowdown is unattributable, the user is often the only one who knows what
/// it was — they were watching the backup indicator, or they had just started an
/// import. Recording that is worth more than another heuristic, and it is the one
/// kind of statement on the screen that comes with certainty attached to a person
/// rather than to us.
///
/// Three properties FR-039's acceptance criteria require, all held here:
///
/// - **Reversible.** `clear(for:)` removes a label completely; setting an empty
///   string does the same. There is no state a user can reach and not leave.
/// - **Raw evidence untouched.** Nothing in this type can write to an `Incident`,
///   to `MetricsHistory`, or to a recorded attribution — it holds a dictionary of
///   strings keyed by incident id, and that is the whole of it. A label changes
///   what we *say*, never what was *measured*.
/// - **Local.** `UserDefaults`, in our own container. Nothing here has a network
///   path, and the label is deliberately not added to the export document: a
///   user's own note about their machine is not something to hand out by default
///   (FR-029).
@Observable
final class IncidentLabels {
    /// Bounded like every other retained thing (FR-005). Oldest written first out.
    static let maximumLabels = 100
    static let maximumLength = 120

    private enum Key {
        static let labels = "incidentLabels"
        static let order = "incidentLabelOrder"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var labels: [String: String]
    /// Insertion order, so pruning drops the oldest rather than an arbitrary one.
    private var order: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        labels = defaults.dictionary(forKey: Key.labels) as? [String: String] ?? [:]
        order = defaults.stringArray(forKey: Key.order) ?? []
    }

    func label(for id: UUID) -> String? { labels[id.uuidString] }

    /// Records a label, or removes it when the text is empty.
    ///
    /// Trimming, then treating empty as removal, is what makes the field its own
    /// undo: a user who clears the box and saves has taken the label off, not
    /// stored a blank one that reads as "the user said nothing" while occupying
    /// the same space as a claim.
    func set(_ text: String, for id: UUID) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maximumLength))
        guard !trimmed.isEmpty else { return clear(for: id) }

        let key = id.uuidString
        labels[key] = trimmed
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.maximumLabels, let oldest = order.first {
            order.removeFirst()
            labels.removeValue(forKey: oldest)
        }
        save()
    }

    func clear(for id: UUID) {
        let key = id.uuidString
        guard labels.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
        save()
    }

    /// Every label, keyed the way the recurrence finder wants them.
    var byIncident: [UUID: String] {
        labels.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.key) { result[id] = entry.value }
        }
    }

    private func save() {
        defaults.set(labels, forKey: Key.labels)
        defaults.set(order, forKey: Key.order)
    }

    // MARK: - Copy

    static let prompt = "I know what this was…"
    static let fieldPrompt = "What was it?"

    /// The promise made at the moment the choice is made, not in a footnote.
    static let promise =
        "Stored only on this Mac, and only in this app. Labelling an incident never "
        + "changes what was measured — the readings and the process list stay exactly "
        + "as recorded, and you can remove the label at any time."

    static let recallPromise =
        "We will show this again beside slowdowns that follow the same pattern."

    /// Suggestions drawn from what was actually running, so the common case is one
    /// click rather than a sentence.
    ///
    /// Only processes we genuinely saw, and only ones with a published role — a
    /// suggestion is a prompt, and prompting a user towards a name we invented
    /// would put our guess in their mouth and then read it back as their evidence.
    static func suggestions(from roster: SystemProcessRoster.Roster) -> [String] {
        var seen = Set<String>()
        return roster.running
            .compactMap(\.role)
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }

    /// The label as a statement, carrying its evidence class: the user said it, so
    /// it is `.userProvided` and never becomes a measurement of ours (FR-038).
    static func conclusion(for label: String) -> Conclusion {
        Conclusion("You labelled this \"\(label)\".", evidence: .userProvided)
    }
}
