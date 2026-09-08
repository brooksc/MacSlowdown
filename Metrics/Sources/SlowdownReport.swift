import Foundation

/// When the slowdown the user is reporting happened (FR-064, S-7).
///
/// Two cases and no more, because the gesture has to cost nothing. "Now" is the
/// common one; "recently" exists for the case where somebody only thinks to tell us
/// once the machine has come back and they have a moment. There is deliberately no
/// case carrying a severity, a category or a description: asking the person to
/// classify what they are experiencing is the failure mode S-7 names first, and it
/// is the reason the previous attempt at feedback collected nothing.
public enum SlowdownReportTiming: Sendable, Equatable, Codable {
    /// It is slow right now.
    case now
    /// It was slow a few minutes ago, and it is over or nearly over.
    ///
    /// The offset is in seconds and comes from whatever the interface offers — a
    /// couple of fixed choices, not a picker. Stored as given rather than rounded,
    /// so a later reading of the record cannot mistake our rounding for the user's
    /// estimate.
    case recently(secondsAgo: Double)

    /// The moment the report points at.
    public func experiencedAt(reportedAt: Date) -> Date {
        switch self {
        case .now: reportedAt
        case .recently(let secondsAgo): reportedAt.addingTimeInterval(-abs(secondsAgo))
        }
    }

    /// Whether this is a report about the past rather than about the present.
    public var isRetrospective: Bool { self != .now }
}

/// How much evidence a report keeps around the moment it points at.
///
/// Both figures are bounded by what `MetricsHistory` actually retains — 15 minutes
/// by default — so a window wider than that cannot be filled and asking for one
/// would only produce a record that looks complete and is not.
public struct SlowdownReportPolicy: Sendable, Equatable {
    /// How far before the reported moment to keep.
    public var leadIn: Duration
    /// How far after it. Zero for a report made now, because the future has not
    /// been sampled yet; a caller that wants the trailing side must re-open the
    /// report later, which this build does not do.
    public var trailing: Duration
    /// The most samples one report may keep.
    ///
    /// At the FR-031 cadence of one second, three minutes of history is ~180
    /// samples of five contributors each — tens of kilobytes per report. The bound
    /// exists so a person who taps the control repeatedly during a bad afternoon
    /// cannot turn evidence retention into the disk cost FR-030 caps.
    public var maximumSamples: Int

    public init(leadIn: Duration = .seconds(180),
                trailing: Duration = .seconds(60),
                maximumSamples: Int = 180) {
        self.leadIn = leadIn
        self.trailing = trailing
        self.maximumSamples = max(1, maximumSamples)
    }

    public static let `default` = SlowdownReportPolicy()

    /// The evidence window for a report, honest about which side of the moment has
    /// actually been sampled: nothing after "now" has been measured, so a report
    /// made now takes no trailing side.
    public func window(around experiencedAt: Date, reportedAt: Date) -> DateInterval {
        let start = experiencedAt.addingTimeInterval(-leadIn.totalSeconds)
        let end = min(reportedAt, experiencedAt.addingTimeInterval(trailing.totalSeconds))
        return DateInterval(start: start, end: max(start, end))
    }
}

/// Why a report has no metric samples behind it.
///
/// A named reason rather than an empty array, because "we kept nothing" and "there
/// was nothing to keep" are different facts and only one of them is about the
/// machine. FR-002's rule applied to our own evidence: an absent measurement is
/// labelled absent and never rendered as a flat line at zero.
public enum SlowdownSampleCoverage: Sendable, Equatable, Codable {
    /// Samples were retained and kept. The bounds are the first and last kept.
    case retained(from: Date, to: Date)
    /// Monitoring had retained nothing at all — the app had just started, or the
    /// user had deleted recorded history.
    case noHistoryRetained
    /// The window is older than the rolling buffer reaches. The ordinary outcome
    /// for a retrospective report made long after the fact, and not an error.
    case windowOlderThanRetainedHistory
    /// History exists on both sides of the window but not inside it — a gap, which
    /// on this product means monitoring was not running then.
    case noSamplesInWindow

    public var hasSamples: Bool {
        if case .retained = self { return true }
        return false
    }
}

/// Where a report's attribution came from.
///
/// The two are not interchangeable and a surface must not describe one as the
/// other. An incident's attribution is a maximum accumulated across the whole
/// episode; a sample taken at the moment of the report is one instant, and an
/// instant is not an episode (FR-038, FR-065).
public enum SlowdownAttributionOrigin: String, Sendable, Equatable, Codable {
    /// Frozen on the coincident incident while it was open.
    case recordedIncident
    /// Rolled up from the sample taken when the report was made.
    case sampledAtReport
}

/// The evidence kept around a reported slowdown (FR-064).
///
/// Everything here was recorded at the time and is never re-derived when the report
/// is read back, for the same reason `Incident` freezes its attribution: live state
/// describes the machine now, not the machine the user was complaining about.
public struct SlowdownReportEvidence: Sendable, Equatable, Codable {
    /// The window the evidence was gathered over.
    public let window: DateInterval
    /// Retained metric samples spanning the window, oldest first. Empty whenever
    /// `coverage` is not `.retained`, and the coverage is what says why.
    ///
    /// Each `ContributorSummary` inside carries `(pid, startTime)`, so a contributor
    /// in a report stays distinguishable from a later process that inherited its
    /// PID — recycling is routine on this platform, not theoretical.
    public let samples: [HistorySample]
    public let coverage: SlowdownSampleCoverage
    /// How many retained samples actually fell in the window, before the bound in
    /// `SlowdownReportPolicy.maximumSamples` was applied.
    ///
    /// Kept so a thinned series can say it is thinned. Every sample retained is a
    /// real reading — nothing is averaged into a synthetic one — but a reader
    /// drawing them as a continuous line deserves to know some were dropped.
    public let observedSampleCount: Int
    /// What was busy, where anything was.
    ///
    /// `nil` means nothing was recorded, never "nothing was running" and never "we
    /// could not decide". A large share of a busy machine is unattributable to us
    /// by uid (FR-055), so an absent attribution is an ordinary outcome.
    public let attribution: IncidentAttribution?
    public let attributionOrigin: SlowdownAttributionOrigin?
    /// The conditions the detector held to be in force when the report was made.
    ///
    /// Empty is the case this whole feature exists for: a slowdown the user
    /// experienced while nothing we watch had crossed a line. It is a first-class
    /// result and the most informative kind we can record.
    public let conditionsInForce: Set<IncidentCondition>
    /// The incident this report coincides with, where one exists.
    ///
    /// Stored as an id rather than a copy so the incident stays single-sourced: it
    /// may still be open when the report is made, and it will keep changing until
    /// it closes. A reader resolves it against `IncidentHistoryStore`, and gets
    /// nothing if the incident has since aged out — which is correct, because the
    /// two stores share one retention setting and expire together.
    public let incidentID: UUID?

    public init(window: DateInterval,
                samples: [HistorySample],
                coverage: SlowdownSampleCoverage,
                observedSampleCount: Int,
                attribution: IncidentAttribution? = nil,
                attributionOrigin: SlowdownAttributionOrigin? = nil,
                conditionsInForce: Set<IncidentCondition> = [],
                incidentID: UUID? = nil) {
        self.window = window
        self.samples = samples
        self.coverage = coverage
        self.observedSampleCount = observedSampleCount
        self.attribution = attribution
        self.attributionOrigin = attributionOrigin
        self.conditionsInForce = conditionsInForce
        self.incidentID = incidentID
    }

    /// Whether samples were dropped to stay inside the bound.
    public var samplesWereThinned: Bool { observedSampleCount > samples.count }
}

/// A slowdown the user reported, with the evidence that surrounded it (FR-064).
///
/// **This is the only instrument in the product that can measure what we miss.**
/// Judging our own alerts measures precision over the events we detected; it can say
/// nothing about the afternoons somebody lost while we recorded nothing unusual. A
/// report is a sample of the population that matters, and a report matching no
/// detected condition is therefore the most informative kind — never an error, never
/// something to answer with an assurance that the machine was fine.
///
/// It carries no severity, no category and no free text, by requirement. What the
/// user supplied is the fact of the report and its timing; everything else here is
/// our own measurement, and the two are kept separable (FR-038, FR-065).
///
/// `Codable` for the same reason `Incident` is: reports persist across a restart,
/// under the same retention and privacy rules, and nothing about one ever leaves the
/// machine.
public struct SlowdownReport: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    /// When the gesture was made.
    public let reportedAt: Date
    public let timing: SlowdownReportTiming
    /// The moment the report points at — equal to `reportedAt` for a report made
    /// now, earlier for a retrospective one. Stored rather than recomputed so a
    /// change to how a timing is interpreted cannot silently re-date records that
    /// were written under the old interpretation.
    public let experiencedAt: Date
    public let evidence: SlowdownReportEvidence

    public init(id: UUID = UUID(),
                reportedAt: Date,
                timing: SlowdownReportTiming,
                experiencedAt: Date,
                evidence: SlowdownReportEvidence) {
        self.id = id
        self.reportedAt = reportedAt
        self.timing = timing
        self.experiencedAt = experiencedAt
        self.evidence = evidence
    }

    /// The fact of the report is user-provided, always (FR-038).
    ///
    /// A constant rather than a stored field: there is no path by which a report
    /// becomes a measurement of anything. What we measured around it carries its own
    /// evidence classes, on the attribution and on the samples.
    public var evidenceClass: Evidence { .userProvided }

    /// Whether anything we watch had crossed a line when this was reported.
    ///
    /// False is the interesting case and must never be presented as a failed
    /// report. It says only that no condition was in force and no incident was
    /// open — a fact about our instruments, not about the user's afternoon.
    public var coincidedWithDetection: Bool {
        evidence.incidentID != nil || !evidence.conditionsInForce.isEmpty
    }

    /// The date retention is measured from.
    public var retentionDate: Date { reportedAt }
}

// MARK: - Assembling a report

extension SlowdownReport {
    /// Builds a report from what the app already has in hand.
    ///
    /// Deliberately a pure function over supplied evidence rather than something
    /// that reaches for live state. The gesture has to be recordable from whatever
    /// surface the design settles on, and nothing about assembling the record should
    /// depend on which one that is — nor should a test have to run a sampler to
    /// exercise it.
    ///
    /// - Parameters:
    ///   - retainedSamples: `MetricsHistory.samples`, ascending. Anything outside
    ///     the window is ignored; nothing is interpolated to fill a gap.
    ///   - incidents: incidents to look for a coincidence in — the open one and the
    ///     recently closed ones. Order does not matter.
    ///   - conditionsInForce: conditions the detector holds to be breaching now.
    ///     Pass the empty set when none are, which is the ordinary case and the one
    ///     the feature exists to capture.
    ///   - liveAttribution: attribution rolled up at the moment of the report, used
    ///     only when no coincident incident carries one of its own.
    public static func make(
        timing: SlowdownReportTiming,
        reportedAt: Date = Date(),
        policy: SlowdownReportPolicy = .default,
        retainedSamples: [HistorySample] = [],
        incidents: [Incident] = [],
        conditionsInForce: Set<IncidentCondition> = [],
        liveAttribution: AttributionSample? = nil,
        id: UUID = UUID()
    ) -> SlowdownReport {
        let experiencedAt = timing.experiencedAt(reportedAt: reportedAt)
        let window = policy.window(around: experiencedAt, reportedAt: reportedAt)

        let inWindow = retainedSamples
            .filter { window.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
        let kept = thinned(inWindow, to: policy.maximumSamples)
        let coverage = coverage(for: kept, retained: retainedSamples, window: window)

        // The incident that covers the reported moment wins over one that merely
        // overlaps the window: a report made two minutes after an episode closed is
        // a weaker coincidence than one made inside it, and the record should not
        // present them as the same claim. Most recent first among equals.
        let coincident = incidents
            .filter { $0.covers(experiencedAt) }
            .sorted { $0.beganAt > $1.beganAt }
            .first
            ?? incidents
                .filter { overlaps($0, window) }
                .sorted { $0.beganAt > $1.beganAt }
                .first

        let attribution: IncidentAttribution?
        let origin: SlowdownAttributionOrigin?
        if let recorded = coincident?.attribution {
            attribution = recorded
            origin = .recordedIncident
        } else if let liveAttribution {
            attribution = IncidentAttribution(sample: liveAttribution, at: reportedAt)
            origin = .sampledAtReport
        } else {
            attribution = nil
            origin = nil
        }

        return SlowdownReport(
            id: id,
            reportedAt: reportedAt,
            timing: timing,
            experiencedAt: experiencedAt,
            evidence: SlowdownReportEvidence(
                window: window,
                samples: kept,
                coverage: coverage,
                observedSampleCount: inWindow.count,
                attribution: attribution,
                attributionOrigin: origin,
                conditionsInForce: conditionsInForce,
                incidentID: coincident?.id))
    }

    /// Whether an incident's span meets the window at all. An open incident is
    /// unbounded at its end, the same convention `Incident.covers` uses.
    static func overlaps(_ incident: Incident, _ window: DateInterval) -> Bool {
        incident.beganAt <= window.end && (incident.closedAt ?? .distantFuture) >= window.start
    }

    /// Keeps at most `limit` of the supplied samples, evenly spread, always keeping
    /// the first and the last.
    ///
    /// Every kept sample is a reading that was actually taken. Nothing here averages
    /// or resamples, because a synthesised point in an evidence series is a
    /// fabricated measurement however plausible it looks (FR-002). What is lost is
    /// resolution, and `observedSampleCount` records that it was lost.
    static func thinned(_ samples: [HistorySample], to limit: Int) -> [HistorySample] {
        guard samples.count > limit, limit > 0 else { return samples }
        guard limit > 1 else { return [samples[samples.count - 1]] }
        let stride = Double(samples.count - 1) / Double(limit - 1)
        var kept: [HistorySample] = []
        kept.reserveCapacity(limit)
        var lastIndex = -1
        for step in 0..<limit {
            let index = min(samples.count - 1, Int((Double(step) * stride).rounded()))
            guard index != lastIndex else { continue }
            kept.append(samples[index])
            lastIndex = index
        }
        return kept
    }

    static func coverage(for kept: [HistorySample], retained: [HistorySample],
                         window: DateInterval) -> SlowdownSampleCoverage {
        if let first = kept.first, let last = kept.last {
            return .retained(from: first.timestamp, to: last.timestamp)
        }
        guard let earliest = retained.map(\.timestamp).min(),
              let latest = retained.map(\.timestamp).max()
        else { return .noHistoryRetained }
        if window.end < earliest { return .windowOlderThanRetainedHistory }
        if window.start > latest { return .windowOlderThanRetainedHistory }
        return .noSamplesInWindow
    }
}

// MARK: - Retention

extension RetentionPolicy {
    /// Reports still within the retention window (FR-029).
    ///
    /// The same setting and the same arithmetic as incidents, on purpose: FR-064
    /// requires a report be kept under the rules an incident is kept under, and two
    /// retention implementations would drift into two answers.
    public static func retained(
        _ reports: [SlowdownReport],
        settings: PrivacySettings,
        now: Date = Date()
    ) -> [SlowdownReport] {
        let cutoff = now.addingTimeInterval(-settings.retention.duration.totalSeconds)
        return reports.filter { $0.retentionDate >= cutoff }
    }

    /// Reports that have aged out and should be removed.
    public static func expired(
        _ reports: [SlowdownReport],
        settings: PrivacySettings,
        now: Date = Date()
    ) -> [SlowdownReport] {
        let kept = Set(retained(reports, settings: settings, now: now).map(\.id))
        return reports.filter { !kept.contains($0.id) }
    }
}

// MARK: - What the reports say about our detection

/// Reported slowdowns counted against what the detector saw (FR-064, TASK-114).
///
/// Counts only. There is deliberately no rate, no score and no word for the ratio:
/// the denominator is reports a person happened to make, not slowdowns that
/// occurred, so anything phrased as a recall figure would be a measurement of our
/// instruments dressed up as a measurement of the machine.
public struct SlowdownDetectionOverlap: Sendable, Equatable {
    public let reports: Int
    /// Reports made while a condition was in force or an incident was open.
    public let coincidingWithDetection: Int
    /// Reports made while nothing we watch had crossed a line. **The reason the
    /// instrument exists**: these are slowdowns the product did not detect.
    public let withoutDetection: Int

    public init(reports: [SlowdownReport]) {
        self.reports = reports.count
        coincidingWithDetection = reports.count(where: \.coincidedWithDetection)
        withoutDetection = reports.count - coincidingWithDetection
    }
}
