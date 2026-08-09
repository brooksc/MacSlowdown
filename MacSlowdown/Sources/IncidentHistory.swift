import Foundation
import Metrics

/// The presentation logic behind the Incidents screen (design reference 1f).
///
/// Kept out of the view so every rule here — what counts as a pattern, what
/// outcome the evidence supports, which day an incident falls on — is testable
/// without putting anything on screen.
enum IncidentHistory {
    // MARK: - Range

    /// How far back the list looks (design 1f: 7 days / 30 days).
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30

        var id: Int { rawValue }
        var days: Int { rawValue }

        /// For the picker.
        var label: String {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            }
        }

        /// For a sentence: "9 incidents in the last 7 days".
        var phrase: String {
            switch self {
            case .week: "in the last 7 days"
            case .month: "in the last 30 days"
            }
        }

        func start(from now: Date, calendar: Calendar = .current) -> Date {
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        }
    }

    // MARK: - Outcome

    /// How an incident ended, in the distinct vocabulary the design calls for.
    ///
    /// **Only two of these four are derivable from what we store today.** Nothing
    /// records that the user acted during an incident, and no suppression record
    /// is linked to an incident, so `.recoveredAfterAction` and `.suppressedByRule`
    /// are produced only when a caller supplies that evidence explicitly. They are
    /// never inferred from timing — an incident that ended shortly after the user
    /// did something is not evidence that they made it end (FR-050, FR-038).
    enum Outcome: Equatable {
        case stillOpen
        /// Conditions cleared, and we hold no record of a user action. We do not
        /// claim the machine healed itself; we state what we observed.
        case recoveredNoActionRecorded
        /// Conditions cleared after an action the user took, which we recorded.
        case recoveredAfterAction
        /// A user rule stopped the alert. The incident was still recorded (FR-016).
        case suppressedByRule(application: String, classification: PolicyClassification)

        var label: String {
            switch self {
            case .stillOpen:
                "still going"
            case .recoveredNoActionRecorded:
                "recovered — no action was recorded"
            case .recoveredAfterAction:
                "recovered after you acted"
            case .suppressedByRule(let application, let classification):
                "Not alerted — you marked \(application) as "
                    + "\(IncidentHistory.shortWord(for: classification))"
            }
        }
    }

    /// The short form of a classification, for the outcome sentence. The stored
    /// `label` is a full phrase ("Heavy load is expected") which does not read as
    /// part of a sentence.
    static func shortWord(for classification: PolicyClassification) -> String {
        switch classification {
        case .expected: "expected"
        case .ignored: "ignored"
        case .watched: "watched"
        }
    }

    /// Derives the outcome from evidence, never from coincidence.
    ///
    /// - Parameters:
    ///   - suppression: a recorded suppression for this incident, if the caller
    ///     holds one. Today nothing links a `SuppressedDetection` to an incident,
    ///     so the app passes nil.
    ///   - action: a recorded, successful action taken while the incident was
    ///     open. Today nothing links an `ActionVerification` to an incident, so
    ///     the app passes nil.
    static func outcome(
        for incident: Incident,
        suppression: SuppressedDetection? = nil,
        action: ActionVerification? = nil
    ) -> Outcome {
        if let suppression {
            return .suppressedByRule(
                application: suppression.application,
                classification: suppression.classification)
        }
        if incident.isOpen { return .stillOpen }
        if let action, action.result.didRun,
           action.requestedAt >= incident.beganAt,
           let closedAt = incident.closedAt, action.requestedAt <= closedAt {
            return .recoveredAfterAction
        }
        return .recoveredNoActionRecorded
    }

    // MARK: - Entries

    /// One row of the list. Lifecycle findings sit in the same list as resource
    /// incidents, because to a user "my machine got slow" and "this app keeps
    /// quitting" are the same kind of event (design 1f, row four).
    struct Entry: Identifiable {
        enum Kind {
            case resource(Incident)
            /// Repeated unexpected quits (FR-046 as narrowed: exits and restarts
            /// are observable, hangs are not).
            case repeatedQuits(RelaunchPattern)
        }

        let kind: Kind
        let id: String
        let at: Date
        /// What the row is about, for the pattern summary to count.
        let conditionLabels: [String]

        init(_ incident: Incident, suppression: SuppressedDetection? = nil,
             action: ActionVerification? = nil) {
            kind = .resource(incident)
            id = incident.id.uuidString
            at = incident.beganAt
            conditionLabels = incident.conditions.map(\.label).sorted()
            outcome = IncidentHistory.outcome(
                for: incident, suppression: suppression, action: action)
        }

        init(_ pattern: RelaunchPattern) {
            kind = .repeatedQuits(pattern)
            id = "relaunch:\(pattern.command):\(pattern.firstAt.timeIntervalSince1970)"
            at = pattern.firstAt
            conditionLabels = [Entry.repeatedQuitsLabel]
            outcome = .recoveredNoActionRecorded
        }

        let outcome: Outcome

        static let repeatedQuitsLabel = "Repeated unexpected quits"

        var isOpen: Bool {
            if case .resource(let incident) = kind { return incident.isOpen }
            return false
        }
    }

    /// Everything in range, open incidents first, then most recent first.
    static func entries(
        open: Incident?,
        recent: [Incident],
        relaunches: [RelaunchPattern] = [],
        range: Range,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Entry] {
        let start = range.start(from: now, calendar: calendar)
        let all = (open.map { [Entry($0)] } ?? [])
            + recent.map { Entry($0) }
            + relaunches.map { Entry($0) }
        return all
            .filter { $0.at >= start }
            .sorted { first, second in
                if first.isOpen != second.isOpen { return first.isOpen }
                return first.at > second.at
            }
    }

    // MARK: - Pattern summary

    /// "9 incidents in the last 7 days", and — only when the data supports it —
    /// what recurs across them.
    struct Pattern {
        let headline: String
        /// Nil unless a recurrence is actually established. One incident is an
        /// event; two are not yet a pattern.
        let recurrence: String?
    }

    /// A recurrence claim needs this many incidents in range before it is made at
    /// all, and the recurring thing must appear in at least this many of them.
    /// Below it, the honest statement is the count on its own.
    static let minimumForPattern = 3

    static func pattern(for entries: [Entry], range: Range) -> Pattern {
        let count = entries.count
        let headline = count == 0
            ? "No incidents \(range.phrase)"
            : "\(count) incident\(count == 1 ? "" : "s") \(range.phrase)"

        guard count >= minimumForPattern else {
            return Pattern(headline: headline, recurrence: nil)
        }

        var counts: [String: Int] = [:]
        for entry in entries {
            for label in Set(entry.conditionLabels) { counts[label, default: 0] += 1 }
        }
        // Ties broken by name so the sentence is stable between refreshes.
        let leader = counts
            .filter { $0.value >= minimumForPattern }
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .first

        guard let leader else { return Pattern(headline: headline, recurrence: nil) }
        return Pattern(
            headline: headline,
            recurrence: "\(leader.key) in \(leader.value) of them")
    }

    // MARK: - Day strip

    /// One column of the strip below the summary.
    struct Day: Identifiable {
        let date: Date
        let count: Int
        /// "M", "T"… for a week; a day number for a month.
        let label: String
        /// Spoken form, so the strip is not shape-only (FR-034).
        let accessibilityLabel: String

        var id: Date { date }
    }

    static func days(
        for entries: [Entry],
        range: Range,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]
        for entry in entries {
            counts[calendar.startOfDay(for: entry.at), default: 0] += 1
        }

        let narrow = DateFormatter()
        narrow.calendar = calendar
        narrow.setLocalizedDateFormatFromTemplate("EEEEE")
        let dayNumber = DateFormatter()
        dayNumber.calendar = calendar
        dayNumber.setLocalizedDateFormatFromTemplate("d")

        return (0..<range.days).reversed().compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let count = counts[date] ?? 0
            let spoken = date.formatted(date: .abbreviated, time: .omitted)
            return Day(
                date: date,
                count: count,
                label: range == .week ? narrow.string(from: date) : dayNumber.string(from: date),
                accessibilityLabel: "\(spoken): \(count) incident\(count == 1 ? "" : "s")")
        }
    }

    // MARK: - Retention

    /// What is actually true of our storage today, rather than what the design
    /// mock says (FR-029).
    ///
    /// The design's footer reads "kept for 30 days on this Mac". We do not keep
    /// them for 30 days: `MonitorStore` holds the most recent
    /// `MonitorStore.retainedIncidents` in memory and nothing persists them across
    /// a restart. Saying otherwise would be a claim we cannot support.
    static func retentionFooter(limit: Int) -> String {
        "The \(limit) most recent incidents are kept in memory while MacSlowdown is "
            + "running, on this Mac only. They are not saved across a restart, and "
            + "nothing about them leaves this Mac unless you export a report."
    }

    /// Why a closed row names no application. Stated once, on screen, rather than
    /// leaving the reader to notice the inconsistency (FR-002, FR-038).
    static let attributionGap =
        "A closed incident does not record which application was involved, so only "
        + "an incident that is still going can name one."
}
