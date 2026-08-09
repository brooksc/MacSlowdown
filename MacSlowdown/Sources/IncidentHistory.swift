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
    /// `.suppressedByRule` is derivable as of TASK-76: the incident carries the
    /// suppressions the notification gate recorded against it, and `Entry` reads
    /// them. `.recoveredAfterAction` still is not — nothing produces an
    /// `ActionVerification`, which is FR-050's open seam (TASK-78).
    ///
    /// Neither is ever inferred from timing. An incident that ended shortly after
    /// the user did something is not evidence that they made it end (FR-050,
    /// FR-038).
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
    ///   - suppression: a recorded suppression for this incident. `Entry` supplies
    ///     the incident's own last one; a caller may override it.
    ///   - action: a recorded, successful action taken while the incident was
    ///     open. Nothing produces one yet — `ActionVerifier` has no caller — so in
    ///     practice this is still nil (TASK-78).
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
                // TASK-76: the incident now records its own suppressions, so the
                // caller no longer has to supply evidence the incident already
                // holds. Settings tells the user that a suppressed slowdown still
                // appears here marked "not alerted", and until this line that
                // sentence was false. An explicit argument still wins, and nothing
                // is inferred from timing.
                for: incident,
                suppression: suppression ?? incident.suppressions.last,
                action: action ?? incident.actions.last)
        }

        init(_ pattern: RelaunchPattern) {
            kind = .repeatedQuits(pattern)
            id = "relaunch:\(pattern.command):\(pattern.firstAt.timeIntervalSince1970)"
            at = pattern.firstAt
            conditionLabels = [Entry.repeatedQuitsLabel]
            outcome = .recoveredNoActionRecorded
        }

        let outcome: Outcome

        /// Taken from the condition rather than written out, so a lifecycle row and
        /// a lifecycle incident count as the same thing in the recurrence summary
        /// instead of as two differently-spelled findings.
        static let repeatedQuitsLabel = IncidentCondition.repeatedApplicationQuits.label

        /// Which application the row is about (TASK-82).
        ///
        /// The rule lives here, not in the view, because the view already got it
        /// wrong once by asking a simpler question: it read
        /// `incident.attribution?.leadingApplication`, the largest *CPU*
        /// contributor, for every row. Observed on screen 2026-08-09, the list said
        /// "Repeated unexpected quits — Xcode" while the detail for that same row
        /// said `yes` had quit thirty times. Both were reporting a real
        /// measurement; only one of them was about the incident.
        ///
        /// So: a lifecycle episode is about the process that kept exiting, and a
        /// resource episode is about what was busy. `Incident.narrative` decides
        /// which, and it is the same rule the summariser and the detail view use.
        var subject: Subject? {
            switch kind {
            case .repeatedQuits(let pattern):
                return Subject(command: pattern.command, applicationName: nil)
            case .resource(let incident):
                if let quitting = incident.lifecycleSubject, !incident.narrative
                    .narratesResourceAttribution {
                    return Subject(command: quitting.command, applicationName: nil)
                }
                guard let leader = incident.attribution?.leadingApplication else { return nil }
                return Subject(command: nil, applicationName: leader.displayName)
            }
        }

        /// A row's subject, named the way FR-002 requires.
        ///
        /// Two things it will not do. It will not present a `p_comm` fragment as
        /// though it were the application's name — the row that read
        /// "BackgroundShortc…" gave no indication that the name was cut off by the
        /// kernel rather than by us. And it will not drop a bare command into the
        /// head of a sentence, where `yes` reads as a word.
        struct Subject: Equatable {
            /// The kernel's command, when that is all we have.
            let command: String?
            /// A resolved application name, which needs no scaffolding.
            let applicationName: String?

            /// For a row's title, where the subject stands on its own.
            var text: String {
                if let applicationName { return applicationName }
                guard let command else { return "" }
                return ProcessNaming.labelled(command: command)
            }

            /// For a sentence, where a bare command must be introduced as one.
            var sentenceText: String {
                ProcessNaming.sentenceSubject(
                    command: command ?? "", applicationName: applicationName)
            }

            /// The same, beginning a sentence.
            var sentenceTextAtStart: String {
                ProcessNaming.sentenceSubject(
                    command: command ?? "", applicationName: applicationName, capitalized: true)
            }

            /// Spoken form: an ellipsis conveys nothing to VoiceOver, so truncation
            /// is said in words (FR-034), exactly as the two inventory tables do.
            var accessibilityText: String {
                if let applicationName { return applicationName }
                guard let command else { return "" }
                return ProcessNaming.accessibilityLabel(command: command)
            }

            /// True when what is shown is the kernel's shortened command rather
            /// than a name (FR-002). `ProcessNaming.nameIsTruncatedCommand` asks
            /// the same question of a resolved identity; here the identity is gone
            /// and only the command survived on the pattern, so the two halves —
            /// no friendly name, and a command at the 16-byte limit — are tested
            /// directly.
            ///
            /// A resolved `applicationName` is taken at face value. Grouping may
            /// itself have fallen back to a labelled command to produce it, and by
            /// the time it reaches here the evidence for that is gone — so this
            /// under-reports rather than guessing from the shape of a string.
            var isShortenedCommand: Bool {
                guard applicationName == nil, let command else { return false }
                return ProcessNaming.isTruncated(command)
            }
        }

        var isOpen: Bool {
            if case .resource(let incident) = kind { return incident.isOpen }
            return false
        }
    }

    /// Everything in range, open incidents first, then most recent first.
    ///
    /// A relaunch pattern already carried by an incident is dropped from
    /// `relaunches` rather than listed twice. See `isAlreadyAnIncident`.
    static func entries(
        open: Incident?,
        recent: [Incident],
        relaunches: [RelaunchPattern] = [],
        range: Range,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Entry] {
        let start = range.start(from: now, calendar: calendar)
        let incidents = (open.map { [$0] } ?? []) + recent
        let standalone = relaunches.filter { !isAlreadyAnIncident($0, in: incidents) }
        let all = incidents.map { Entry($0) } + standalone.map { Entry($0) }
        return all
            .filter { $0.at >= start }
            .sorted { first, second in
                if first.isOpen != second.isOpen { return first.isOpen }
                return first.at > second.at
            }
    }

    /// Whether an incident already represents this repeated-quit pattern (TASK-71).
    ///
    /// Until TASK-71 a relaunch pattern could only ever be a standalone row, because
    /// nothing opened an incident for one. Now that `repeatedApplicationQuits` is a
    /// condition, the same episode arrives from two directions — as the live pattern
    /// the tracker still holds, and as the incident that pattern opened — and
    /// listing both would show a user two findings where there was one event, and
    /// would count it twice in "3 incidents in the last 7 days".
    ///
    /// The **incident** wins, deliberately. It is selectable, it opens the detail
    /// with the evidence attached, and it survives a restart; the live pattern is
    /// none of those things. A pattern the tracker holds that no incident covers —
    /// one below the quiet period, or seen before this build started recording them
    /// — still gets its own row, so nothing observed disappears.
    ///
    /// Matched on the command, not on times: an episode's window grows as it goes,
    /// so a time-equality test would stop matching the moment another exit landed
    /// and the row would reappear beside its own incident.
    static func isAlreadyAnIncident(_ pattern: RelaunchPattern, in incidents: [Incident]) -> Bool {
        incidents.contains { incident in
            incident.lifecycleFindings.contains { $0.command == pattern.command }
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

    /// What is actually true of our storage, which is what FR-029 requires the
    /// screen to say.
    ///
    /// **Both bounds, because there are two** (TASK-72). History is kept for the
    /// period the user chose *and* capped at `limit` records; a footer naming only
    /// the period would promise 30 days of a busy fortnight that we do not keep.
    /// Whichever bites first is what is on disk.
    ///
    /// The period is read from the setting rather than written into the sentence,
    /// so changing the picker changes this line — the interface cannot state a
    /// retention the store is not applying.
    ///
    /// Nothing here says "encrypted". See `StoredData.containerStatement`.
    @MainActor
    static func retentionFooter(
        limit: Int,
        retention: PrivacySettings.Retention = AlertSettings.shared.retention
    ) -> String {
        "Incidents are kept for \(retention.label) on this Mac, and no more than the "
            + "\(limit) most recent — whichever comes first. They are saved "
            + "\(StoredData.containerStatement), and nothing about them leaves this "
            + "Mac unless you export a report."
    }

    /// Why a closed row names no application. Stated once, on screen, rather than
    /// leaving the reader to notice the inconsistency (FR-002, FR-038).
    static let attributionGap =
        "A closed incident does not record which application was involved, so only "
        + "an incident that is still going can name one."
}
