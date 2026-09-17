import Foundation
import Metrics

/// The rules behind the opening view (TASK-113, designs 5a/5b/5c/6c).
///
/// Kept out of the view for the reason `NowPresentation` is: these are the
/// sentences that can be wrong, and a sentence inside a `body` is a sentence no
/// test can reach.
///
/// The screen answers two questions at once — *is it still happening?* and *what
/// happened earlier?* — and a third that nothing in this product could previously
/// answer at all: **were we even watching?** That third one governs the other two.
/// A headline saying nothing crossed a line is a claim about a period, and a claim
/// about a period is worthless without knowing how much of the period we saw. So
/// coverage is not a badge on this screen; it is a qualifier on every sentence.
///
/// Three rules run through everything here:
///
/// - **Never say the Mac is fine.** We can say nothing crossed a line, over a
///   stated window, while we were watching. The absolute claim is not ours to make
///   (FR-063, S-6).
/// - **A gap makes no claim in either direction.** Not "probably fine", not
///   "possibly bad". Nothing (design 5c).
/// - **Nothing here rewards a second look.** No streak, no score, no figure that
///   grows while you watch it. A person who opens this ten minutes later should
///   find the same answer, which is the point of it.
enum OverviewPresentation {
    // MARK: - The window

    /// The time scale the screen is showing.
    ///
    /// Two, not a slider. "Today" is the question a person actually asks — *was it
    /// slow this afternoon?* — and "30 days" is where a pattern becomes visible
    /// that no live reading could ever show (design 6c). Anything between them
    /// would be a control to fiddle with rather than a question to answer.
    enum Scale: String, CaseIterable, Identifiable {
        case today = "Today"
        case thirtyDays = "30 days"

        var id: String { rawValue }

        /// How far back the window reaches from `now`.
        ///
        /// Today runs from local midnight rather than from 24 hours ago, because
        /// "since midnight" is a boundary a person recognises and "the last 24
        /// hours" is one they have to compute.
        func start(now: Date, calendar: Calendar = .current) -> Date {
            switch self {
            case .today: calendar.startOfDay(for: now)
            case .thirtyDays:
                calendar.date(byAdding: .day, value: -29,
                              to: calendar.startOfDay(for: now)) ?? now
            }
        }

        /// How the window is named inside a sentence about a period.
        var sinceClause: String {
            switch self {
            case .today: "since midnight"
            case .thirtyDays: "in the last 30 days"
            }
        }

        /// The window as a noun, for a sentence that needs to name it rather than
        /// date from it — "nothing recorded for today" against "nothing since
        /// midnight". Two forms because one of them reads as nonsense in the other's
        /// sentence.
        var noun: String {
            switch self {
            case .today: "today"
            case .thirtyDays: "the last 30 days"
            }
        }
    }

    /// A span in words, with days where days are the readable unit.
    ///
    /// `DurationPhrase` stops at hours, which is right for an incident and wrong
    /// for a month: "718 hr 4 min" is not a figure anybody reads. Handled here
    /// rather than by widening `DurationPhrase`, because that would change the
    /// wording of every duration in the product that happens to exceed a day, and
    /// none of them wanted it.
    static func spanPhrase(_ duration: Duration) -> String {
        let seconds = max(0, duration.totalSeconds)
        guard seconds >= 48 * 3600 else { return DurationPhrase.phrase(seconds, .compact) }
        let days = Int(seconds / 86_400)
        let hours = Int((seconds - Double(days) * 86_400) / 3600)
        return hours > 0 ? "\(days) days \(hours) hr" : "\(days) days"
    }

    // MARK: - Coverage

    /// The line at the top right of the strip: how much of the window we watched.
    ///
    /// Both figures, always. "Watched 6 hr 14 min" alone is a number with nothing to
    /// judge it against, and "coverage 44%" is a percentage the reader has to turn
    /// back into hours before it means anything.
    static func coverageSummary(
        log: CoverageLog, scale: Scale, now: Date, calendar: Calendar = .current
    ) -> String {
        let from = scale.start(now: now, calendar: calendar)
        let watched = log.watched(from: from, to: now)
        let total = Duration.seconds(now.timeIntervalSince(from))
        if log.gaps(from: from, to: now).isEmpty, watched.totalSeconds > 0 {
            return "Watched all of it"
        }
        return "Watched \(spanPhrase(watched)) of the \(spanPhrase(total)) \(scale.sinceClause)"
    }

    /// The sentence under the strip, naming the gaps.
    ///
    /// Nil when there are none — an explicit "no gaps" line under a solid strip is
    /// the manufactured interest S-6 warns about. The strip already says it.
    static func gapNote(log: CoverageLog, scale: Scale, now: Date,
                        calendar: Calendar = .current) -> String? {
        let from = scale.start(now: now, calendar: calendar)
        let gaps = log.gaps(from: from, to: now)
        guard let largest = gaps.first else { return nil }
        let reason = largest.state.reason ?? .noReadings
        if gaps.count == 1 {
            return "The hatched stretch is \(clockRange(largest, calendar: calendar)) — "
                + "\(reason.sentence.lowercasedFirst) We can't answer for it, and it "
                + "stays on the strip for as long as this window is on screen."
        }
        let total = gaps.reduce(0.0) { $0 + $1.duration.totalSeconds }
        return "\(gaps.count) hatched stretches, \(spanPhrase(.seconds(total))) in all. "
            + "The longest is \(clockRange(largest, calendar: calendar)) — "
            + "\(reason.sentence.lowercasedFirst) We can't answer for any of them."
    }

    /// The gap design 5c's button files a report against, or nil when the window
    /// has none (TASK-120).
    ///
    /// The largest, which is the same gap `gapNote` names — "the hatched stretch"
    /// when there is one, "the longest" when there are several. A button that
    /// filed against a different gap from the sentence above it would be the class
    /// of defect FR-060 exists to prevent, so both read the same first element and
    /// neither picks its own.
    static func reportableGap(
        log: CoverageLog, scale: Scale, now: Date, calendar: Calendar = .current
    ) -> CoverageSpan? {
        log.gaps(from: scale.start(now: now, calendar: calendar), to: now).first
    }

    /// How far back the middle of a gap is from `now`, which is what
    /// `SlowdownReportTiming.recently(secondsAgo:)` takes.
    ///
    /// The **midpoint**, not the start or the end: a report is a point in time and
    /// the evidence policy builds a window around it, so aiming at either edge
    /// would centre that window half outside the stretch the user is pointing at.
    /// Never negative — a gap that somehow ends in the future is clamped to now
    /// rather than filed as a report about the future.
    static func secondsAgo(ofMiddleOf gap: CoverageSpan, now: Date) -> Double {
        let middle = gap.from.addingTimeInterval(gap.duration.totalSeconds / 2)
        return max(0, now.timeIntervalSince(middle))
    }

    /// Where our record itself begins, when the window reaches back past it.
    ///
    /// Nil when the record covers the whole window, because then there is nothing to
    /// say. When it is not nil it is the difference between "we watched none of that
    /// morning" and "that morning is outside what we keep" — two facts a strip full
    /// of hatching cannot tell apart on its own (design 5c's retention boundary).
    static func recordBeginsNote(
        log: CoverageLog, scale: Scale, now: Date, calendar: Calendar = .current
    ) -> String? {
        guard let earliest = log.earliestRecord,
              earliest > scale.start(now: now, calendar: calendar)
        else { return nil }
        let latest = log.latestObservation.map {
            // The right-hand edge of the strip is the last reading, not this instant.
            // Saying "now" over a stretch we have not sampled would claim coverage of
            // the seconds since (FR-002).
            " The last reading was \(clock($0))."
        } ?? ""
        return "Our record begins \(day(earliest)) \(clock(earliest)); anything before "
            + "that is outside the period we keep.\(latest)"
    }

    /// A gap as a clock range: "1:40 to 2:25 this afternoon".
    static func clockRange(_ span: CoverageSpan, calendar: Calendar = .current) -> String {
        let sameDay = calendar.isDate(span.from, inSameDayAs: span.to)
        let from = clock(span.from)
        let to = clock(span.to)
        guard sameDay else { return "\(day(span.from)) \(from) to \(day(span.to)) \(to)" }
        return "\(from) to \(to)\(partOfDayClause(span.to, calendar: calendar))"
    }

    /// "this morning", "this afternoon" — nil unless the moment is today, because
    /// "this afternoon" about a fortnight ago would be a lie about which afternoon.
    static func partOfDayClause(_ date: Date, now: Date = Date(),
                                calendar: Calendar = .current) -> String {
        guard calendar.isDate(date, inSameDayAs: now) else { return "" }
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case ..<12: return " this morning"
        case ..<18: return " this afternoon"
        default: return " this evening"
        }
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The three-state legend (design 5c). One grammar for the whole screen, and it
    /// is stated on the screen rather than left to be inferred from the hatching.
    static let legend: [(label: String, detail: String)] = [
        ("Watched, nothing crossed",
         "A real result — the headline may say so."),
        ("Watched, something crossed",
         "The condition is marked on the strip."),
        ("Not watched",
         "No claim is made, in either direction."),
    ]

    // MARK: - The headline

    /// Which of the three states the screen is in.
    ///
    /// Ordered by what the reader most needs to know. A condition happening *now*
    /// beats everything, because that is the question they opened the window with.
    /// A coverage gap beats a quiet screen, because a quiet screen that does not
    /// mention the gap is the screen implying an answer we do not have — which is
    /// the failure 5c exists to prevent.
    enum Lead: Equatable {
        case conditionPresent
        case coverageGap
        case nothingCrossed
    }

    struct Headline: Equatable {
        let text: String
        /// The paragraph under it. Always states what was measured and over what
        /// interval; never what the machine felt like (FR-063).
        let detail: String
        /// Present only where a condition is being recorded right now.
        let chip: String?
        let symbolName: String
        let spoken: String
    }

    /// Everything the headline is derived from, gathered so the rule is one
    /// function of one value rather than eight parameters that can be passed in the
    /// wrong order.
    struct Inputs {
        var log: CoverageLog
        var scale: Scale = .today
        var now: Date = Date()
        var calendar: Calendar = .current
        /// The condition being recorded right now, if any.
        var openIncident: Incident?
        /// Its headline, from the summariser — this file never writes a second
        /// wording of what a condition is (FR-060).
        var openHeadline: String?
        /// Closed incidents, most recent first.
        var recentIncidents: [Incident] = []
        /// Whether the open incident's conditions are ones we record rather than
        /// announce, which is what licenses "we didn't interrupt you for it".
        var wasNotAnnounced = false
        /// Slowdown reports the user filed inside the window (FR-064).
        var reportCount = 0
    }

    static func lead(_ inputs: Inputs) -> Lead {
        if inputs.openIncident != nil { return .conditionPresent }
        let from = inputs.scale.start(now: inputs.now, calendar: inputs.calendar)
        return inputs.log.gaps(from: from, to: inputs.now).isEmpty
            ? .nothingCrossed : .coverageGap
    }

    static func headline(_ inputs: Inputs) -> Headline {
        switch lead(inputs) {
        case .conditionPresent: conditionHeadline(inputs)
        case .coverageGap: gapHeadline(inputs)
        case .nothingCrossed: quietHeadline(inputs)
        }
    }

    /// Design 5b. The condition, its duration, and then the sentence that is the
    /// whole reason FR-063 exists.
    private static func conditionHeadline(_ inputs: Inputs) -> Headline {
        let incident = inputs.openIncident
        let text = inputs.openHeadline ?? "A sustained condition is being recorded"
        var detail = ""
        if let incident {
            detail = "Since \(clock(incident.beganAt)) — "
                + "\(DurationPhrase.phrase(incident.duration, .full)) so far. "
        }
        // The sentence the product now turns on. A build and a slowdown are the same
        // measurement; the difference is in the person's head, and the honest move is
        // to hand them the judgement rather than make it for them.
        detail += "Whether this is a problem depends on what you're doing — a build "
            + "looks exactly like this."
        if inputs.wasNotAnnounced {
            // Only where it is true. Claiming not to have interrupted somebody we
            // did interrupt would be a worse failure than the interruption.
            detail += " We didn't interrupt you for it."
        }
        let chip = incident.map { "\($0.severity.label) · \(DurationPhrase.phrase($0.duration))" }
        return Headline(
            text: text, detail: detail, chip: chip,
            symbolName: "clock.badge.exclamationmark",
            spoken: "\(text). \(chip.map { "\($0). " } ?? "")\(detail)")
    }

    /// Design 5c. The gap leads, and the rest of the screen is explicitly held back
    /// from implying anything about it.
    private static func gapHeadline(_ inputs: Inputs) -> Headline {
        let from = inputs.scale.start(now: inputs.now, calendar: inputs.calendar)
        let gaps = inputs.log.gaps(from: from, to: inputs.now)
        let largest = gaps[0]
        let reason = largest.state.reason ?? .noReadings
        let text = "We can't answer for \(clockRange(largest, calendar: inputs.calendar))"

        var detail = "\(reason.sentence) "
        detail += "That's \(spanPhrase(largest.duration)) we have no readings for. "
        let crossings = conditions(in: inputs)
        detail += crossings.isEmpty
            ? "Nothing crossed a line in the time we did watch, but if something "
                + "happened in that window we have no record of it — and we'd rather "
                + "say so than let the rest of this screen imply otherwise."
            : "The rest of the window is on the strip below, including "
                + "\(countPhrase(crossings.count, "condition")) we did record."
        return Headline(
            text: text, detail: detail, chip: nil,
            symbolName: "exclamationmark.triangle",
            spoken: "\(text). \(detail)")
    }

    /// Design 5a — the ordinary visit, and the one nothing in this product had ever
    /// been designed for.
    ///
    /// The headline dates the claim from the later of two moments: when the last
    /// recorded condition ended, and when our record of this window begins. Dating
    /// it from the start of the window alone would claim coverage we do not have;
    /// dating it from the last condition alone would say "nothing since Tuesday" on
    /// a machine we watched for six minutes.
    private static func quietHeadline(_ inputs: Inputs) -> Headline {
        let from = inputs.scale.start(now: inputs.now, calendar: inputs.calendar)
        let watchedFrom = inputs.log.spans(from: from, to: inputs.now)
            .first(where: { $0.state.isWatched })?.from
        let lastCondition = conditions(in: inputs).first?.closedAt

        let since = [watchedFrom, lastCondition].compactMap { $0 }.max()
        let text: String
        if let since {
            text = "Nothing has crossed a line since "
                + "\(clock(since))\(partOfDayClause(since, now: inputs.now, calendar: inputs.calendar))"
        } else {
            // No watched span in the window at all. Not a quiet machine — an unwatched
            // one, and the headline must not read as the first.
            text = "We have nothing recorded for \(inputs.scale.noun)"
        }

        var detail = ""
        if let lastCondition, let latest = conditions(in: inputs).first {
            detail += "\(countPhrase(conditions(in: inputs).count, "condition")) recorded "
                + "\(inputs.scale.sinceClause), the last of them ending "
                + "\(clock(lastCondition)) — \(latest.severity.label.lowercased()). "
        }
        detail += "That is what we measured while we were watching, which was "
            + "\(spanPhrase(inputs.log.watched(from: from, to: inputs.now))) of the "
            + "\(spanPhrase(.seconds(inputs.now.timeIntervalSince(from)))) "
            + "\(inputs.scale.sinceClause). "
        // The standing caveat, in every state, because it is the thing that separates
        // this screen from a green light.
        detail += "It isn't a claim that the Mac was fine — only that nothing we watch "
            + "stayed over a line long enough to be recorded."
        if inputs.reportCount > 0 {
            // The user's own reports are a separate claim from ours, and are kept
            // separately labelled wherever both appear (FR-063, FR-064).
            detail += " You reported \(countPhrase(inputs.reportCount, "slowdown")) "
                + "\(inputs.scale.sinceClause) that we recorded no condition for."
        }
        return Headline(
            text: text, detail: detail, chip: nil,
            symbolName: "checkmark.circle",
            spoken: "\(text). \(detail)")
    }

    /// Closed incidents inside the window, most recent first.
    static func conditions(in inputs: Inputs) -> [Incident] {
        let from = inputs.scale.start(now: inputs.now, calendar: inputs.calendar)
        return inputs.recentIncidents
            .filter { ($0.closedAt ?? $0.beganAt) >= from }
            .sorted { ($0.closedAt ?? $0.beganAt) > ($1.closedAt ?? $1.beganAt) }
    }

    static func countPhrase(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: - The retained trace

    /// Why the strip covers the whole window and the curve does not.
    ///
    /// The design draws a CPU trace from midnight to now. We do not have one:
    /// `MetricsHistory` retains about fifteen minutes and the series is deliberately
    /// not persisted, so a day-long curve could only be drawn by inventing most of
    /// it. Stating the limit is the same rule the sparklines already follow — a gap
    /// is not a zero, and a line we never measured is not a flat one (FR-002,
    /// FR-057).
    ///
    /// The coverage strip is not affected: coverage is a handful of timestamps per
    /// day and is kept for the full retention period, which is exactly why it can
    /// answer for a window the readings cannot.
    static func traceScopeNote(retained: Duration) -> String {
        guard retained.totalSeconds >= 60 else {
            return "No metric series is retained yet, so there is no curve to draw. "
                + "The strip above still says when we were watching."
        }
        return "The curve covers the \(DurationPhrase.phrase(retained, .full)) of readings "
            + "we retain. The strip above covers the whole window — coverage is kept "
            + "for the full retention period, the readings themselves are not."
    }

    // MARK: - The 30-day scale (design 6c)

    /// One day, as the long scale draws it.
    ///
    /// A day is too coarse to be honest about a 45-minute gap, so a hatched cell
    /// means *part* of the day is missing and the day view says so in words. The
    /// day scale marks which days to distrust; the day view shows exactly when.
    struct DayCell: Identifiable, Equatable {
        let date: Date
        let isWatchedThroughout: Bool
        let conditionCount: Int
        /// How much of the day we watched, for the spoken label.
        let watched: Duration
        let total: Duration

        var id: Date { date }
        var hasCondition: Bool { conditionCount > 0 }

        var spoken: String {
            let day = OverviewPresentation.day(date)
            let coverage = isWatchedThroughout
                ? "watched all day"
                : "watched \(OverviewPresentation.spanPhrase(watched)) of "
                    + "\(OverviewPresentation.spanPhrase(total))"
            guard conditionCount > 0 else { return "\(day), \(coverage), nothing crossed a line" }
            return "\(day), \(coverage), "
                + "\(OverviewPresentation.countPhrase(conditionCount, "condition")) recorded"
        }
    }

    static func dayCells(
        log: CoverageLog, incidents: [Incident], now: Date, calendar: Calendar = .current,
        days: Int = 30
    ) -> [DayCell] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset -> DayCell? in
            guard let start = calendar.date(byAdding: .day, value: offset - (days - 1), to: today)
            else { return nil }
            let end = min(calendar.date(byAdding: .day, value: 1, to: start) ?? now, now)
            guard end > start else { return nil }
            let count = incidents.filter {
                let at = $0.beganAt
                return at >= start && at < end
            }.count
            return DayCell(
                date: start,
                isWatchedThroughout: log.isComplete(from: start, to: end),
                conditionCount: count,
                watched: log.watched(from: start, to: end),
                total: .seconds(end.timeIntervalSince(start)))
        }
    }

    /// The paragraph under the 30-day strip (design 6c).
    static func dayScaleNote(_ cells: [DayCell]) -> String {
        let complete = cells.filter(\.isWatchedThroughout).count
        var note = "Complete coverage on \(complete) of \(cells.count) days, one day per cell. "
        note += "A hatched cell means part of that day is missing, not all of it — a day "
            + "is too coarse to be honest about a 45-minute gap, so this scale marks "
            + "which days to distrust and Today shows exactly when."
        return note
    }

    // MARK: - The last condition recorded (design 5a)

    /// The card's own heading, which has to state *when* rather than imply recency.
    static func lastConditionAge(_ incident: Incident, now: Date = Date()) -> String {
        let at = incident.closedAt ?? incident.beganAt
        let elapsed = now.timeIntervalSince(at)
        if elapsed < 3600 { return DurationPhrase.phrase(elapsed, .full) + " ago" }
        if elapsed < 86_400 { return "\(clock(at)) today" }
        let days = Int(elapsed / 86_400)
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    /// When the condition happened and how long it lasted, in the same wording the
    /// Incidents list uses — the same date style and the same duration formatter, so
    /// the summary and the detail behind it cannot state the episode differently
    /// (FR-060).
    static func conditionWindow(_ incident: Incident) -> String {
        let started = incident.beganAt.formatted(date: .abbreviated, time: .shortened)
        let length = DateComponentsFormatter.incidentDuration
            .string(from: incident.duration.totalSeconds) ?? "under a minute"
        return "\(started) · \(incident.isOpen ? "\(length) so far" : length)"
    }

    /// What is said where no condition has ever been recorded.
    ///
    /// **Not "you have no incidents"**, which reads as a clean bill of health. The
    /// sentence says what is true: we have recorded none, over the period we have
    /// been watching, and that period is stated.
    static func noConditionsNote(watched: Duration) -> String {
        guard watched.totalSeconds >= 60 else {
            return "Nothing recorded yet. We have only just started watching, so that "
                + "is a statement about us rather than about the Mac."
        }
        return "No condition has been recorded in the \(spanPhrase(watched)) we have "
            + "watched. That is not the same as nothing having happened."
    }
}

private extension String {
    /// For a reason sentence that has to continue a clause it did not start.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
