import Foundation
import Metrics

/// The copy the report gesture gives back (FR-064, design 5d and 6d).
///
/// **The reply is the feature.** Storing a report and saying nothing is the
/// extractive failure S-7 names: we took data and gave nothing back, and the
/// person stops telling us. So this file's job is to answer, in the case that will
/// be by far the most common — nothing we watch had crossed a line — without
/// telling the user they were mistaken.
///
/// Three sentences are forbidden here and each is forbidden for its own reason:
///
///   - *"Nothing was wrong."* Contradicts them, from measurements that cannot
///     support it. A large share of a busy machine is unattributable to us by uid
///     and most of what makes a Mac feel slow is not a resource reading at all.
///   - *"We couldn't find anything."* Softer, same claim: it still puts the burden
///     on the user having imagined it.
///   - *"Thanks for the feedback."* Extractive. It admits we did nothing with it
///     and moves on.
///
/// What replaces them is an ordering, not a nicer adjective: **the limitation is
/// ours before it is theirs.** We looked, what we watch looked ordinary, and the
/// gap between those two things is our instrument's, which is exactly why the
/// report is worth having (FR-063, FR-038).
///
/// Pure presentation, like `PopoverPresentation`: nothing here samples, and no
/// figure appears that was not measured and passed in.
enum SlowdownReportPresentation {

    // MARK: - The gesture (design 5d, left)

    static let reportNowTitle = "It feels slow right now"
    static let reportEarlierTitle = "It was slow a few minutes ago…"

    /// The promise under the two buttons.
    ///
    /// The span is read from the policy rather than written into the sentence.
    /// Design 5d says "the last 15 minutes of readings", which was true of the
    /// retained history and not of what a report keeps; a caption naming a window
    /// wider than the one actually filed would be a fabricated measurement with a
    /// friendly tone (FR-002).
    static func gestureCaption(policy: SlowdownReportPolicy = .default) -> String {
        "No form and no questions — one click files it with the last "
            + "\(DurationPhrase.phrase(policy.leadIn, .full)) of readings attached."
    }

    static let gestureHelp =
        "Files a report with the readings from the last few minutes attached. "
        + "Nothing leaves this Mac."

    // MARK: - The reply (design 5d, right)

    static func recordedHeadline(
        at date: Date, timeText: (Date) -> String = PopoverPresentation.shortTime
    ) -> String {
        "Recorded, \(timeText(date))"
    }

    /// **The settled sentence**, for the case this feature exists to capture.
    ///
    /// Every clause is load-bearing. "Everything we watch" scopes the claim to our
    /// instruments. "Looked ordinary" describes readings, not their afternoon.
    /// "That doesn't mean nothing was wrong" refuses the inference before the user
    /// can draw it. And the last clause says why the report was worth making, which
    /// is the part that makes the gesture an exchange rather than a collection.
    static let nothingUnusual =
        "Everything we watch looked ordinary in those minutes. That doesn't mean "
        + "nothing was wrong — most of what makes a Mac feel slow isn't something "
        + "we can measure, and this is the only way we find out about those."

    /// The reply when something we watch *had* crossed a line.
    ///
    /// The two claims stay separate, in that order: what we measured, then whose
    /// account of the time is whose. A condition being in force is not a
    /// confirmation that the user was right, because the same reading is produced
    /// by work they started deliberately — FR-063's whole point — so this must not
    /// read as "yes, we saw it too".
    static func conditionsAcknowledgement(_ conditions: Set<IncidentCondition>) -> String {
        "We were recording \(conditionPhrase(conditions)) over those minutes. That "
            + "is what our instruments read, kept beside what you told us and "
            + "marked separately — the reading is ours, the experience is yours."
    }

    static func acknowledgement(_ report: SlowdownReport) -> String {
        report.evidence.conditionsInForce.isEmpty
            ? nothingUnusual
            : conditionsAcknowledgement(report.evidence.conditionsInForce)
    }

    /// What was kept, stated as what was kept.
    ///
    /// Each coverage case gets its own sentence rather than a single hedged one,
    /// because "we kept nothing" and "there was nothing to keep" are different
    /// facts and only one of them is about the machine. A retrospective report
    /// reaching past the rolling buffer is the ordinary outcome, not a failure, and
    /// says so.
    static func keptReadings(
        _ report: SlowdownReport,
        timeText: (Date) -> String = PopoverPresentation.shortTime
    ) -> String {
        switch report.evidence.coverage {
        case .retained(let from, let to):
            let thinned = report.evidence.samplesWereThinned
                ? " \(report.evidence.samples.count) of the "
                    + "\(report.evidence.observedSampleCount) readings in that span were "
                    + "kept, evenly spread."
                : ""
            return "We've kept the readings from \(timeText(from)) to \(timeText(to)) "
                + "so there's something to compare against next time.\(thinned)"
        case .noHistoryRetained:
            return "We had no readings retained at that point, so this is kept as the "
                + "time you gave us and nothing else. It still counts."
        case .windowOlderThanRetainedHistory:
            return "That's further back than the readings we keep reach, so this is "
                + "kept as the time you gave us and nothing else. It still counts."
        case .noSamplesInWindow:
            return "We weren't recording during those minutes, so this is kept as the "
                + "time you gave us and nothing else. It still counts."
        }
    }

    // MARK: - What was kept, line by line

    /// One line of "What you told us".
    ///
    /// The evidence class is not styling and is not a boolean. FR-038 requires a
    /// user-provided fact to be distinguishable from a measured one wherever the
    /// two appear together, and this panel is the one place in the product where
    /// they sit in the same list — with a third kind between them, since a recorded
    /// attribution is a heuristic and says so. Each row's class comes from the
    /// model that produced it (`SlowdownReport.evidenceClass`,
    /// `IncidentAttribution.evidence`), never from a literal written here.
    struct EvidenceRow: Identifiable, Equatable {
        let id: Int
        let time: String
        let text: String
        let evidence: Evidence

        var isYours: Bool { evidence == .userProvided }
    }

    static let evidenceHeading = "What you told us"
    static let evidenceQualifier = "kept alongside the measurements, marked as yours"

    /// The user's line first, then ours.
    ///
    /// - Parameter allReports: every retained report including this one, used only
    ///   to count how many times this week. Counted rather than claimed: "third
    ///   time this week" is arithmetic over the record, and a report that has aged
    ///   out is not in it.
    static func evidenceRows(
        for report: SlowdownReport,
        allReports: [SlowdownReport],
        calendar: Calendar = .current,
        timeText: (Date) -> String = PopoverPresentation.shortTime
    ) -> [EvidenceRow] {
        var rows: [EvidenceRow] = []
        rows.append(EvidenceRow(
            id: rows.count,
            time: timeText(report.experiencedAt),
            text: yoursLine(for: report, allReports: allReports, calendar: calendar),
            evidence: report.evidenceClass))

        if let readings = readingsLine(for: report, timeText: timeText) {
            rows.append(EvidenceRow(
                id: rows.count,
                time: spanText(report.evidence.coverage, timeText: timeText) ?? "",
                text: readings,
                evidence: .measured))
        }

        if !report.evidence.conditionsInForce.isEmpty {
            rows.append(EvidenceRow(
                id: rows.count,
                time: timeText(report.experiencedAt),
                text: "Recorded at the time: "
                    + "\(conditionPhrase(report.evidence.conditionsInForce))",
                evidence: .measured))
        }

        // The leading application, where one was recorded. Named without a verb
        // that would make it a cause: it was busy at the same time, which is all
        // an instant of attribution can say (FR-013, FR-065).
        if let attribution = report.evidence.attribution,
           let leader = attribution.leadingApplication {
            rows.append(EvidenceRow(
                id: rows.count,
                time: timeText(report.reportedAt),
                text: "\(leader.displayName) was the busiest we could see, at "
                    + "\(CPUPresentation.percentOfOneCore(leader.peakPercentOfOneCore)) "
                    + "of one core",
                // The attribution's own class: what was busy at one instant is an
                // interpretation, and `IncidentAttribution.evidence` will not let
                // it be anything else.
                evidence: attribution.evidence))
        }
        return rows
    }

    static func yoursLine(
        for report: SlowdownReport, allReports: [SlowdownReport], calendar: Calendar
    ) -> String {
        let base = report.timing.isRetrospective
            ? "You reported it had felt slow"
            : "You reported it felt slow"
        guard let ordinal = ordinalThisWeek(
            for: report, in: allReports, calendar: calendar)
        else { return base }
        return "\(base) — \(ordinal) time this week"
    }

    /// Where this report falls among the last seven days of reports, or nil when
    /// it is the only one and there is nothing to count.
    static func ordinalThisWeek(
        for report: SlowdownReport, in allReports: [SlowdownReport], calendar: Calendar
    ) -> String? {
        let cutoff = calendar.date(
            byAdding: .day, value: -7, to: report.reportedAt) ?? report.reportedAt
        let thisWeek = allReports.filter {
            $0.reportedAt > cutoff && $0.reportedAt <= report.reportedAt
        }
        // The report itself may not have reached the passed-in list yet.
        let count = thisWeek.contains(where: { $0.id == report.id })
            ? thisWeek.count
            : thisWeek.count + 1
        guard count >= 2 else { return nil }
        return ordinal(count)
    }

    static func ordinal(_ count: Int) -> String {
        switch count {
        case 2: "second"
        case 3: "third"
        case 4: "fourth"
        case 5: "fifth"
        case 6: "sixth"
        case 7: "seventh"
        case 8: "eighth"
        case 9: "ninth"
        case 10: "tenth"
        default: "\(count)th"
        }
    }

    /// The CPU range over the kept readings, with the count behind it.
    ///
    /// A range and a sample count rather than a single figure, because a single
    /// figure from a fifteen-minute window would be a statistic with no stated
    /// interval — the defect FR-057 exists to forbid. Nil when nothing was kept:
    /// there is no range, and a zero would be a fabricated one.
    static func readingsLine(
        for report: SlowdownReport,
        timeText: (Date) -> String = PopoverPresentation.shortTime
    ) -> String? {
        let values = report.evidence.samples.map(\.totalBusyPercentOfOneCore)
        guard let low = values.min(), let high = values.max() else { return nil }
        let range = low == high
            ? CPUPresentation.percentOfOneCore(low)
            : "\(CPUPresentation.percentOfOneCore(low))–"
                + "\(CPUPresentation.percentOfOneCore(high))"
        let readings = values.count == 1 ? "1 reading" : "\(values.count) readings"
        return "Total CPU \(range) of one core, across \(readings)"
    }

    static func spanText(
        _ coverage: SlowdownSampleCoverage, timeText: (Date) -> String
    ) -> String? {
        guard case .retained(let from, let to) = coverage else { return nil }
        return "\(timeText(from))–\(timeText(to))"
    }

    // MARK: - What the reports have in common (design 5d, the blue card)

    /// The heading over a comparison, or nil when there is nothing to compare.
    static func patternHeading(_ pattern: SlowdownReportPattern) -> String {
        switch pattern {
        case .sharedApplication(_, let reports),
             .sameTimeOfDay(_, _, let reports, _),
             .noneCoincidedWithDetection(let reports):
            "The \(count(reports)) you've reported have something in common"
        }
    }

    /// The comparison itself.
    ///
    /// **Every one of these says "we can see the timing, not the cost."** That is
    /// not hedging: no public API gives us per-process disk or network use, and a
    /// large share of a busy machine is another user's and unreadable, so an
    /// application appearing every time is genuinely a coincidence of timing and
    /// nothing more. Saying so is what stops the card being read as a diagnosis
    /// (FR-013, FR-038, FR-063).
    static func patternDetail(_ pattern: SlowdownReportPattern) -> String {
        switch pattern {
        case .sharedApplication(let name, let reports):
            return "All \(reports) had \(name) among the busiest processes we could "
                + "see — which is the kind of thing we can see the timing of but "
                + "never the cost of. Worth watching for the next one."
        case .sameTimeOfDay(let earliest, let latest, let reports, let days):
            let band = earliest == latest
                ? "in the \(hour(earliest)) hour"
                : "between \(hour(earliest)) and \(hour(latest + 1))"
            return "All \(reports) were \(band), across \(count(days, singular: "day", plural: "days")). "
                + "That is timing we can see; what runs then is something you may "
                + "recognise sooner than we can."
        case .noneCoincidedWithDetection(let reports):
            return "None of the \(reports) coincided with anything we watch crossing "
                + "a line. That is a fact about our instruments, and it is the reason "
                + "these reports are worth keeping."
        }
    }

    static func count(_ value: Int, singular: String = "report",
                      plural: String = "reports") -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    static func hour(_ value: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = value % 24
        components.minute = 0
        guard let date = calendar.date(from: components) else { return "\(value)" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func conditionPhrase(_ conditions: Set<IncidentCondition>) -> String {
        let labels = conditions.map(\.label).sorted().map { $0.lowercased() }
        switch labels.count {
        case 0: return "nothing"
        case 1: return labels[0]
        case 2: return "\(labels[0]) and \(labels[1])"
        default:
            return labels.dropLast().joined(separator: ", ") + " and \(labels[labels.count - 1])"
        }
    }

    // MARK: - The retrospective picker (design 6d, left)

    static let pickerTitle = "When was it slow?"
    static let pickerSubtitle = "Roughly is fine — we'll keep a window around it."
    static let pickerFooter =
        "Each option shows the window it will keep, so the record is never vaguer "
        + "than the button that made it."

    /// One bucket of the picker.
    ///
    /// `window` is computed by the same `SlowdownReportPolicy` that will file the
    /// report, not written alongside it. That is the whole of 6d's footer: a button
    /// promising a window the record does not contain would be the friendly
    /// fabrication FR-002 forbids.
    struct RetrospectiveChoice: Identifiable, Equatable {
        let id: Int
        let title: String
        let window: String
        let secondsAgo: Double
    }

    /// The two fixed buckets, and the hours of today behind them.
    ///
    /// Three buckets and no free picker: `SlowdownReportTiming.recently` accepts any
    /// offset, so the coarseness here is a design choice rather than a limitation.
    /// Someone who has just lost twenty minutes is not going to set a time.
    static func retrospectiveChoices(
        now: Date = Date(),
        policy: SlowdownReportPolicy = .default,
        timeText: (Date) -> String = PopoverPresentation.shortTime
    ) -> [RetrospectiveChoice] {
        [(0, "In the last few minutes", 300.0), (1, "About half an hour ago", 1800.0)]
            .map { id, title, secondsAgo in
                RetrospectiveChoice(
                    id: id, title: title,
                    window: windowText(secondsAgo: secondsAgo, now: now,
                                       policy: policy, timeText: timeText),
                    secondsAgo: secondsAgo)
            }
    }

    static let earlierTodayTitle = "Earlier today"
    static let earlierTodayHint = "pick an hour"

    /// The whole hours that have already passed today, most recent first.
    ///
    /// Empty just after midnight, and the row is then not offered at all rather
    /// than offered empty — an action shown must be one that can succeed (FR-062).
    /// The moment recorded is the middle of the chosen hour, because "some time in
    /// the 2 o'clock hour" is what the user actually said and the window is drawn
    /// around it.
    static func earlierTodayChoices(
        now: Date = Date(),
        policy: SlowdownReportPolicy = .default,
        calendar: Calendar = .current,
        timeText: (Date) -> String = PopoverPresentation.shortTime
    ) -> [RetrospectiveChoice] {
        let currentHour = calendar.component(.hour, from: now)
        guard currentHour > 0 else { return [] }
        return (0..<currentHour).reversed().map { hourOfDay in
            let start = calendar.startOfDay(for: now)
                .addingTimeInterval(Double(hourOfDay) * 3600)
            let middle = start.addingTimeInterval(1800)
            let secondsAgo = now.timeIntervalSince(middle)
            return RetrospectiveChoice(
                id: hourOfDay,
                title: hour(hourOfDay, calendar: calendar),
                window: windowText(secondsAgo: secondsAgo, now: now,
                                   policy: policy, timeText: timeText),
                secondsAgo: secondsAgo)
        }
    }

    static func windowText(
        secondsAgo: Double, now: Date, policy: SlowdownReportPolicy,
        timeText: (Date) -> String
    ) -> String {
        let moment = SlowdownReportTiming.recently(secondsAgo: secondsAgo)
            .experiencedAt(reportedAt: now)
        let window = policy.window(around: moment, reportedAt: now)
        return "\(timeText(window.start))–\(timeText(window.end))"
    }

    // MARK: - Seeing them afterwards (design 5d and 6d)

    static func listTitle(_ reports: Int) -> String {
        reports == 1 ? "The slowdown you've reported" : "The slowdowns you've reported"
    }

    static func seeAllTitle(_ reports: Int) -> String {
        reports <= 1 ? "See all reports" : "See all \(reports) reports"
    }

    static let emptyList =
        "You haven't reported one yet. When your Mac feels slow, the button in the "
        + "menu bar files what we were reading at the time."

    /// One row of the list: when, and whether anything we watch had crossed a line.
    ///
    /// The second half is the useful part of the row, and it is phrased as a fact
    /// about our detection rather than about the machine.
    static func listRow(
        _ report: SlowdownReport,
        dateText: (Date) -> String = Self.dayAndTime
    ) -> String {
        let detection = report.coincidedWithDetection
            ? conditionSummary(report)
            : "nothing we watch had crossed a line"
        return "\(dateText(report.experiencedAt)) · \(detection)"
    }

    static func conditionSummary(_ report: SlowdownReport) -> String {
        report.evidence.conditionsInForce.isEmpty
            ? "a condition was already being recorded"
            : "recorded alongside \(conditionPhrase(report.evidence.conditionsInForce))"
    }

    static func dayAndTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Where the reports live, in the words FR-029 and this repo settled on.
    ///
    /// Never "encrypted" — the container is not, and claiming it would be a
    /// security promise we cannot keep.
    static let storageAssurance =
        "Your reports sit in MacSlowdown's own container, which no other app can "
        + "read. Nothing is uploaded and there is no account."

    static let retentionNote =
        "They are kept under the same retention as the rest of the recorded "
        + "evidence, and you can delete any of them here."

    static let deleteTitle = "Delete this report"
    static let keepTitle = "Keep and close"
}
