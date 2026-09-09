import Foundation

/// When monitoring was actually running, so "nothing happened" can be told apart
/// from "we were not looking" (TASK-113, S-2, S-6, FR-002).
///
/// This is the one piece of evidence the product had no record of. Every other
/// surface answers a question about the machine; this answers a question about
/// *us*, and without it a reassurance is worthless: a screen that says nothing
/// crossed a line looks identical whether we watched all morning or stopped an
/// hour ago. FR-002's rule — an absent measurement is labelled absent, never
/// rendered as a zero — applied to the act of measuring itself.
///
/// The model is deliberately small. A coverage record is a list of intervals we
/// observed, and everything else is derived: a gap is the complement of an
/// interval, watched time is the sum of intervals clipped to a window, and no gap
/// ever heals, because a gap is not a state we recover from but a stretch of time
/// we have nothing to say about.

/// Why we were not watching.
///
/// Four cases, and the distinctions between them are ones we can actually
/// establish. `systemAsleep` is only ever set from an observed sleep
/// notification, `appNotRunning` only from the fact that the recorder's first
/// observation of a launch follows the gap, and `noReadings` is the honest
/// fallback for a lapse we cannot explain — it states what is true of every gap
/// (no readings arrived) without claiming to know why.
///
/// There is deliberately no `.crashed`, `.updated` or `.throttled`: design 5c's
/// "relaunched at 2:25 after an update" is a fact about the user's afternoon that
/// no public API tells us, and inventing it would be exactly the fabricated
/// measurement FR-002 forbids.
public enum CoverageGapReason: String, Sendable, Codable, Equatable, CaseIterable {
    /// MacSlowdown was not running, or was running and not monitoring. Established
    /// by the recorder's first observation after a launch.
    case appNotRunning
    /// The Mac was asleep. Set only from an observed sleep notification.
    case systemAsleep
    /// We have no readings for this stretch and cannot say why. The neutral case.
    case noReadings
    /// Before the record itself begins — a first run, the retention boundary, or
    /// history the user deleted. Not a failure to watch; a limit on what we keep.
    case beyondRecord

    /// A phrase to sit on the strip, short enough to fit a segment's label.
    public var shortLabel: String {
        switch self {
        case .appNotRunning: "MacSlowdown wasn't running"
        case .systemAsleep: "Mac asleep"
        case .noReadings: "No readings"
        case .beyondRecord: "Before our record"
        }
    }

    /// The same fact as a sentence, for a headline or a spoken label.
    public var sentence: String {
        switch self {
        case .appNotRunning: "MacSlowdown wasn't running."
        case .systemAsleep: "The Mac was asleep."
        case .noReadings: "No readings arrived, and we can't say why."
        case .beyondRecord: "This is before the period we keep a record for."
        }
    }
}

/// One stretch we observed, from the first reading to the last.
///
/// `lastObserved` is a *reading*, not a promise: the interval claims coverage up
/// to the moment a sample actually arrived and no further. That is why the strip
/// under-claims rather than over-claims after a crash — the tail between the last
/// flush and the crash becomes a gap, which is the safe direction to be wrong in.
public struct CoverageInterval: Sendable, Codable, Equatable {
    public let began: Date
    public private(set) var lastObserved: Date
    /// Why we were not watching immediately before this interval began. Carried on
    /// the interval rather than on a separate gap record because the gap is derived
    /// and the reason is not: the reason is established at the moment we resume,
    /// and this is where it survives a restart.
    public let precededBy: CoverageGapReason

    public init(began: Date, lastObserved: Date, precededBy: CoverageGapReason) {
        self.began = began
        self.lastObserved = max(began, lastObserved)
        self.precededBy = precededBy
    }

    public var duration: Duration { .seconds(lastObserved.timeIntervalSince(began)) }

    fileprivate mutating func extend(to date: Date) {
        guard date > lastObserved else { return }
        lastObserved = date
    }

    /// Clipped to a window, or nil where the overlap has no duration.
    ///
    /// A single reading is an interval of zero length, and it is deliberately not
    /// drawn: one sample establishes that we were alive at an instant, not that we
    /// covered a stretch, and painting a width for it would be claiming coverage we
    /// did not measure. The consequence is that the record **under**-claims for the
    /// one sample at the start of a session, which is the direction this particular
    /// record has to be wrong in.
    fileprivate func clipped(from: Date, to: Date) -> CoverageInterval? {
        let start = max(began, from)
        let end = min(lastObserved, to)
        guard end > start else { return nil }
        return CoverageInterval(began: start, lastObserved: end, precededBy: precededBy)
    }
}

/// One stretch of the timeline in one state.
public struct CoverageSpan: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case watched
        case notWatched(CoverageGapReason)

        public var isWatched: Bool { self == .watched }
        public var reason: CoverageGapReason? {
            if case .notWatched(let reason) = self { return reason }
            return nil
        }
    }

    public let from: Date
    public let to: Date
    public let state: State

    public init(from: Date, to: Date, state: State) {
        self.from = from
        self.to = to
        self.state = state
    }

    public var id: Date { from }
    public var duration: Duration { .seconds(to.timeIntervalSince(from)) }
}

/// The coverage record.
///
/// A value type, so the recorder that owns it can hand a snapshot to a view
/// without the view being able to write to the evidence — the same rule as
/// `MonitorStore.retainedSamples`.
public struct CoverageLog: Sendable, Codable, Equatable {
    /// Ordered, disjoint, oldest first.
    public private(set) var intervals: [CoverageInterval]

    public init(intervals: [CoverageInterval] = []) {
        self.intervals = intervals.sorted { $0.began < $1.began }
    }

    /// How late a reading may be and still count as continuous coverage.
    ///
    /// Not zero, and not the cadence either. The sampling loop runs at 1–5 s
    /// (FR-031) and is allowed to be late — that is what `Freshness.stale`
    /// describes — so a reading that arrives a beat behind is still a reading, and
    /// treating every hiccup as a hole in the record would fill the strip with
    /// hatching that means nothing. Beyond this, though, we genuinely have no
    /// measurement for the intervening time and must not claim one.
    ///
    /// Scaled from the cadence in force so an investigation cadence and a relaxed
    /// one are judged by the same rule rather than by the same number of seconds.
    public static func tolerance(cadence: Duration) -> Duration {
        max(cadence * 4, .seconds(20))
    }

    /// Records a reading, extending the current interval or opening a new one.
    ///
    /// Returns true when a new interval was opened — that is, when this observation
    /// followed a gap. The caller decides the reason, because only the caller knows
    /// whether it has just launched or has just been woken.
    @discardableResult
    public mutating func observe(
        at date: Date,
        tolerance: Duration = CoverageLog.tolerance(cadence: .seconds(1)),
        resumingAfter reason: CoverageGapReason
    ) -> Bool {
        guard var last = intervals.last else {
            intervals.append(
                CoverageInterval(began: date, lastObserved: date, precededBy: reason))
            return true
        }
        // A clock that has gone backwards (an NTP correction, a user changing the
        // date) must not silently shorten the record. Ignored rather than trusted:
        // the interval already claims coverage up to `lastObserved`, and rewriting
        // it from an earlier stamp would erase observations that did happen.
        if date <= last.lastObserved { return false }
        if date.timeIntervalSince(last.lastObserved) <= tolerance.totalSeconds {
            last.extend(to: date)
            intervals[intervals.count - 1] = last
            return false
        }
        intervals.append(
            CoverageInterval(began: date, lastObserved: date, precededBy: reason))
        return true
    }

    /// The earliest moment the record reaches. Nil when nothing has been recorded.
    public var earliestRecord: Date? { intervals.first?.began }

    /// The latest reading recorded.
    public var latestObservation: Date? { intervals.last?.lastObserved }

    /// The timeline over a window, as alternating watched and not-watched spans.
    ///
    /// Every moment in the window is accounted for by exactly one span. That is the
    /// property the whole device rests on: a strip that only drew the failures it
    /// could explain would be honest about those and silent about the rest, and a
    /// reader would have no way to tell an unexplained gap from a covered stretch.
    public func spans(from: Date, to: Date) -> [CoverageSpan] {
        guard to > from else { return [] }
        let clipped = intervals.compactMap { $0.clipped(from: from, to: to) }

        var spans: [CoverageSpan] = []
        var cursor = from
        for interval in clipped {
            if interval.began > cursor {
                // The reason recorded when we resumed. It describes why we were not
                // watching at the moment the gap ended, which is the best account
                // we have of the whole stretch — and it is the *only* account we
                // have, so the alternative is to say nothing about a gap we are
                // drawing anyway.
                //
                // The retention boundary is covered by the same field rather than by
                // a special case here: `prune` stamps the truncated interval with
                // `.beyondRecord`, so the leading gap on a 30-day view reads as the
                // limit of what we keep and not as a fortnight we failed to watch.
                spans.append(CoverageSpan(
                    from: cursor, to: interval.began,
                    state: .notWatched(interval.precededBy)))
            }
            spans.append(CoverageSpan(from: interval.began, to: interval.lastObserved,
                                      state: .watched))
            cursor = interval.lastObserved
        }
        if cursor < to {
            // The trailing complement. `noReadings` rather than a guess: monitoring
            // may have stopped, the app may have been quit, or this window may
            // simply extend past the last reading — and we cannot tell which from
            // the record alone.
            //
            // Two cases we *can* name. If an interval begins after this gap — the
            // window ends before we resumed, or the only reading in it is a single
            // instant that claims no duration — then the reason recorded when we
            // resumed describes this stretch, and it is better than a shrug. And an
            // empty log has never recorded anything, so the window is beyond our
            // record rather than a stretch we failed to watch.
            let reason: CoverageGapReason = intervals.first { $0.began >= cursor }?.precededBy
                ?? (intervals.isEmpty ? .beyondRecord : .noReadings)
            spans.append(CoverageSpan(from: cursor, to: to, state: .notWatched(reason)))
        }
        return spans
    }

    /// How much of a window we actually watched.
    public func watched(from: Date, to: Date) -> Duration {
        .seconds(spans(from: from, to: to)
            .filter { $0.state.isWatched }
            .reduce(0) { $0 + $1.to.timeIntervalSince($1.from) })
    }

    /// The gaps in a window, longest first, ignoring those below `minimum`.
    ///
    /// The minimum governs what is *listed*, never what is counted: a run of
    /// half-minute lapses still subtracts from the watched total above, so the two
    /// figures cannot disagree. A threshold on the total would be the quiet
    /// rounding-away FR-002 exists to prevent.
    public func gaps(from: Date, to: Date, minimum: Duration = .seconds(60)) -> [CoverageSpan] {
        spans(from: from, to: to)
            .filter { !$0.state.isWatched && $0.duration.totalSeconds >= minimum.totalSeconds }
            .sorted { $0.duration.totalSeconds > $1.duration.totalSeconds }
    }

    /// Whether the window is completely covered.
    public func isComplete(from: Date, to: Date, minimum: Duration = .seconds(60)) -> Bool {
        gaps(from: from, to: to, minimum: minimum).isEmpty
    }

    /// Drops everything older than `date`, truncating the interval that straddles
    /// it. Returns whether anything changed.
    ///
    /// Truncation rather than removal for the straddling interval, so the strip
    /// stops at the retention boundary instead of the record appearing to begin at
    /// whatever quiet moment happened to fall just inside it (design 5c).
    @discardableResult
    public mutating func prune(before date: Date) -> Bool {
        let kept = intervals.compactMap { interval -> CoverageInterval? in
            guard interval.lastObserved > date else { return nil }
            guard interval.began < date else { return interval }
            return CoverageInterval(began: date, lastObserved: interval.lastObserved,
                                    precededBy: .beyondRecord)
        }
        guard kept != intervals else { return false }
        intervals = kept
        return true
    }

    /// Forgets the record, keeping only the fact that we are watching from now.
    ///
    /// What "delete all history" does to coverage. The alternative — leaving the
    /// record intact — would let a screen claim we watched a stretch whose evidence
    /// the user has just deleted; clearing it outright would make the strip deny we
    /// are watching *now*, which is also untrue. So the record restarts, and
    /// everything before it reads as beyond our record, which is exactly what it is.
    public mutating func forgetting(at date: Date) {
        intervals = [CoverageInterval(began: date, lastObserved: date,
                                      precededBy: .beyondRecord)]
    }
}
