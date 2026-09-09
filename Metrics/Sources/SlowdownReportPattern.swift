import Foundation

/// Something two or more reports have in common (FR-064, S-7).
///
/// **A coincidence, never an explanation.** Each case is a fact about *timing* —
/// what was running, when in the day, whether anything we watch had crossed a line
/// — and none of them is a claim that the thing named cost the user anything. We
/// cannot measure that: a large share of a busy machine is unattributable to us by
/// uid, and even a process we can see being busy at the same moment is not evidence
/// it was responsible (FR-013, FR-063).
///
/// The value of saying it at all is that it answers the question the user actually
/// has after the second report — "what was different those times" — with something
/// they can check themselves. Which is why the wording that renders these must
/// stay at the level of "here is what these have in common", and why there is no
/// case here that could only be produced by guessing.
public enum SlowdownReportPattern: Sendable, Equatable {
    /// One application was among the contributors recorded for every report.
    ///
    /// `reports` is how many reports agreed, which is always all of them: a pattern
    /// that holds for two of three is not a pattern, it is a coincidence of a
    /// coincidence.
    case sharedApplication(name: String, reports: Int)
    /// Every report fell in the same part of the day, on more than one day.
    ///
    /// The hours are the earliest and latest clock hour reported in, so a caller can
    /// name the band rather than a single time that only one of them matched.
    case sameTimeOfDay(earliestHour: Int, latestHour: Int, reports: Int, days: Int)
    /// Nothing we watch had crossed a line for any of them.
    ///
    /// **The most important one and the least impressive-looking.** It is the shape
    /// of the failure this whole instrument exists to find: repeated slowdowns that
    /// our detection is silent about. It is stated last because it is the weakest
    /// *comparison*, not because it is the least significant finding.
    case noneCoincidedWithDetection(reports: Int)
}

/// Finds what a person's reports have in common, or nothing (FR-064).
///
/// Deliberately returns at most one pattern. Three coincidences listed together
/// read as a case being built, and we are not entitled to build one; the user
/// asked what these had in common, and the most specific true answer is the whole
/// of what we can honestly offer.
public enum SlowdownReportPatterns {
    /// One report has nothing to be compared against, so nothing is said until the
    /// second. S-7's failure mode is a gesture that gives nothing back — not a
    /// gesture that waits until it has something true to say.
    public static let minimumReports = 2

    /// The widest span of clock hours still describable as "the same part of the
    /// day". Two hours: 2 PM and 3 PM is a pattern a person can act on, 2 PM and
    /// 6 PM is not.
    static let timeOfDayBandHours = 1

    /// The strongest coincidence these reports share, or nil.
    ///
    /// Order is specificity, not importance: an application present every time is
    /// something the user can go and look at; a time of day is something they can
    /// watch for; "none of these coincided with anything we watch" is true of most
    /// sets of reports and so says least about *these* ones.
    public static func pattern(
        in reports: [SlowdownReport], calendar: Calendar = .current
    ) -> SlowdownReportPattern? {
        guard reports.count >= minimumReports else { return nil }
        return sharedApplication(in: reports)
            ?? sameTimeOfDay(in: reports, calendar: calendar)
            ?? noneCoincidedWithDetection(in: reports)
    }

    /// An application recorded as a contributor in every single report.
    ///
    /// Matched on `applicationID` rather than on the display name, because that is
    /// the key that survives PID replacement and two applications sharing a name
    /// (see `IncidentContributor`). The name shown is the most recent one recorded
    /// for that id, since a renamed or updated application should be called what it
    /// is called now.
    ///
    /// A report with no attribution at all disqualifies the whole comparison rather
    /// than being skipped over. "All three had Chrome running" must not mean "the
    /// two we had readings for did".
    static func sharedApplication(in reports: [SlowdownReport]) -> SlowdownReportPattern? {
        var shared: Set<String>?
        for report in reports {
            let applications = report.evidence.attribution?.applications ?? []
            guard !applications.isEmpty else { return nil }
            let ids = Set(applications.map(\.applicationID))
            shared = shared.map { $0.intersection(ids) } ?? ids
            if shared?.isEmpty == true { return nil }
        }
        guard let shared, !shared.isEmpty else { return nil }

        // Among several shared applications, the one that was busiest at its worst
        // across these reports — the largest measured figure, not a guess at which
        // matters most.
        let contributors = reports
            .flatMap { $0.evidence.attribution?.applications ?? [] }
            .filter { shared.contains($0.applicationID) }
        guard let leader = contributors.max(by: {
            $0.peakPercentOfOneCore < $1.peakPercentOfOneCore
        }) else { return nil }
        let mostRecentName = reports
            .sorted { $0.reportedAt > $1.reportedAt }
            .lazy
            .flatMap { $0.evidence.attribution?.applications ?? [] }
            .first { $0.applicationID == leader.applicationID }?
            .displayName
        return .sharedApplication(
            name: mostRecentName ?? leader.displayName, reports: reports.count)
    }

    /// Every report inside the same short band of clock hours, on at least two
    /// different days.
    ///
    /// The two-day requirement is what makes this a pattern rather than an
    /// arithmetic restatement of "these were all this afternoon". A band spanning
    /// midnight is not reported: the hours would have to wrap, and "between 11 PM
    /// and 1 AM" is not a claim this simple comparison is equipped to make.
    static func sameTimeOfDay(
        in reports: [SlowdownReport], calendar: Calendar
    ) -> SlowdownReportPattern? {
        let hours = reports.map { calendar.component(.hour, from: $0.experiencedAt) }
        guard let earliest = hours.min(), let latest = hours.max(),
              latest - earliest <= timeOfDayBandHours
        else { return nil }
        let days = Set(reports.map { calendar.startOfDay(for: $0.experiencedAt) })
        guard days.count >= 2 else { return nil }
        return .sameTimeOfDay(
            earliestHour: earliest, latestHour: latest,
            reports: reports.count, days: days.count)
    }

    static func noneCoincidedWithDetection(
        in reports: [SlowdownReport]
    ) -> SlowdownReportPattern? {
        guard reports.allSatisfy({ !$0.coincidedWithDetection }) else { return nil }
        return .noneCoincidedWithDetection(reports: reports.count)
    }
}
