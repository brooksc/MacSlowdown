import Foundation

/// One application an incident was attributed to, as recorded while it was open.
///
/// FR-011 requires an incident to be created with "start time, active conditions,
/// severity **and leading contributors**". Contributors were the missing half: the
/// incident kept its times and severity but nothing about what was busy, so a
/// closed incident could only be re-explained from live state — which by then
/// describes a different machine.
public struct IncidentContributor: Sendable, Equatable, Codable, Identifiable {
    /// Stable across incidents and across PID replacement.
    ///
    /// The application's bundle path where it has one, and its display name where
    /// it does not. Never the PID-derived family id: about 85% of the table is
    /// standalone processes, and a key containing a PID would make every incident
    /// look like a different application (see the PID-recycling rule in CLAUDE.md).
    public let applicationID: String
    public let displayName: String
    /// Metadata only — grouping is by path, because helpers report their own
    /// signed identifier rather than the parent's.
    public let bundleID: String?
    public let bundlePath: String?
    /// The highest CPU this application reached while the incident was open, as a
    /// percentage of one core. A measured maximum over the incident, not a rate at
    /// any single instant.
    public let peakPercentOfOneCore: Double
    /// Whether any member of the family was grouped here on weaker evidence than a
    /// corroborated path (FR-003). Carried so a later screen can qualify the name
    /// rather than presenting an uncertain grouping as settled.
    public let hasUncertainMembers: Bool

    public var id: String { applicationID }

    public init(applicationID: String, displayName: String, bundleID: String? = nil,
                bundlePath: String? = nil, peakPercentOfOneCore: Double,
                hasUncertainMembers: Bool = false) {
        self.applicationID = applicationID
        self.displayName = displayName
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.peakPercentOfOneCore = peakPercentOfOneCore
        self.hasUncertainMembers = hasUncertainMembers
    }
}

/// One sample's worth of application attribution, offered to the detector.
///
/// Kept separate from `CPUAttribution` because that type is per-process and lives
/// only as long as the sample. What an incident has to keep is per-application and
/// has to outlive every process in it.
public struct AttributionSample: Sendable, Equatable {
    public let applications: [IncidentContributor]
    public let totalBusyPercentOfOneCore: Double
    public let attributedPercentOfOneCore: Double
    public let unattributedPercentOfOneCore: Double
    public let logicalCoreCount: Int

    public init(applications: [IncidentContributor], totalBusyPercentOfOneCore: Double,
                attributedPercentOfOneCore: Double, unattributedPercentOfOneCore: Double,
                logicalCoreCount: Int) {
        self.applications = applications
        self.totalBusyPercentOfOneCore = totalBusyPercentOfOneCore
        self.attributedPercentOfOneCore = attributedPercentOfOneCore
        self.unattributedPercentOfOneCore = unattributedPercentOfOneCore
        self.logicalCoreCount = logicalCoreCount
    }

    /// Rolls a per-process attribution up to the applications it belongs to.
    ///
    /// Aggregating to the family is the point: "Chrome" is one answer a user can
    /// act on, where forty renderer helpers are not, and recurrence across
    /// incidents is only meaningful per application.
    public static func from(
        attribution: CPUAttribution,
        families: [ProcessFamily],
        limit: Int = IncidentAttribution.retainedApplications
    ) -> AttributionSample {
        let contributions = Dictionary(
            attribution.contributors.map { ($0.identity, $0.percentOfOneCore) },
            uniquingKeysWith: { first, _ in first })

        let applications = families.compactMap { family -> IncidentContributor? in
            let cpu = family.members.reduce(0.0) {
                $0 + (contributions[$1.record.identity] ?? 0)
            }
            guard cpu > 0 else { return nil }
            return IncidentContributor(
                applicationID: family.bundlePath ?? "name:\(family.displayName)",
                displayName: family.displayName,
                bundleID: family.members.compactMap { $0.resolved.bundleID }.first,
                bundlePath: family.bundlePath,
                peakPercentOfOneCore: cpu,
                hasUncertainMembers: family.hasUncertainMembers)
        }
        .sorted { $0.peakPercentOfOneCore > $1.peakPercentOfOneCore }

        return AttributionSample(
            applications: Array(applications.prefix(limit)),
            totalBusyPercentOfOneCore: attribution.totalBusyPercentOfOneCore,
            attributedPercentOfOneCore: attribution.attributedPercentOfOneCore,
            unattributedPercentOfOneCore: attribution.unattributedPercentOfOneCore,
            logicalCoreCount: attribution.logicalCoreCount)
    }
}

/// What an incident was attributed to, recorded while it was happening.
///
/// **This is a heuristic and it stays one.** `evidence` is `.heuristic` by
/// construction and there is no initialiser that can make it anything else, so a
/// screen that shows a recorded application cannot show it without the confidence
/// it was recorded with (FR-013, FR-038).
///
/// Two different aggregations live here on purpose:
///   - `applications` are per-application **maxima across the incident**. Each is a
///     measured figure for that application, and the largest is the one a user
///     would call the culprit.
///   - the three totals and the confidence come from the **single busiest sample**
///     observed, kept as one coherent set. Taking each total's maximum
///     independently would produce a triple that never existed and would not sum.
public struct IncidentAttribution: Sendable, Equatable, Codable {
    /// Bounded, as FR-005 and FR-012 require of retained evidence.
    public static let retainedApplications = 5

    public let firstRecordedAt: Date
    public private(set) var lastUpdatedAt: Date
    /// Largest first.
    public private(set) var applications: [IncidentContributor]
    public private(set) var peakTotalBusyPercentOfOneCore: Double
    public private(set) var attributedPercentOfOneCoreAtPeak: Double
    public private(set) var unattributedPercentOfOneCoreAtPeak: Double
    /// FR-004: a percentage of one core means nothing without the core count, and
    /// the count has to travel with the incident for a report to be interpretable
    /// later (FR-049).
    public private(set) var logicalCoreCount: Int
    /// The confidence this attribution carried at the busiest moment observed.
    /// Stored rather than recomputed, so history shows what was believed at the
    /// time instead of what the current machine would suggest.
    public private(set) var confidence: Confidence

    /// Always. A recorded attribution is an interpretation of measurements, never
    /// a proven cause.
    public var evidence: Evidence { .heuristic }

    public init(sample: AttributionSample, at date: Date) {
        firstRecordedAt = date
        lastUpdatedAt = date
        applications = sample.applications
        peakTotalBusyPercentOfOneCore = sample.totalBusyPercentOfOneCore
        attributedPercentOfOneCoreAtPeak = sample.attributedPercentOfOneCore
        unattributedPercentOfOneCoreAtPeak = sample.unattributedPercentOfOneCore
        logicalCoreCount = sample.logicalCoreCount
        confidence = Self.confidence(for: sample)
    }

    /// Folds another sample in while the incident is still open.
    ///
    /// Merging stops when the incident closes simply because nothing calls this
    /// afterwards — the recorded attribution then freezes with the incident, which
    /// is what makes it evidence rather than a live reading.
    public mutating func merge(_ sample: AttributionSample, at date: Date) {
        lastUpdatedAt = date

        var peaks: [String: IncidentContributor] = [:]
        for contributor in applications + sample.applications {
            if let existing = peaks[contributor.applicationID],
               existing.peakPercentOfOneCore >= contributor.peakPercentOfOneCore {
                continue
            }
            peaks[contributor.applicationID] = contributor
        }
        applications = Array(
            peaks.values
                .sorted {
                    $0.peakPercentOfOneCore == $1.peakPercentOfOneCore
                        ? $0.displayName < $1.displayName
                        : $0.peakPercentOfOneCore > $1.peakPercentOfOneCore
                }
                .prefix(Self.retainedApplications))

        guard sample.totalBusyPercentOfOneCore > peakTotalBusyPercentOfOneCore else { return }
        peakTotalBusyPercentOfOneCore = sample.totalBusyPercentOfOneCore
        attributedPercentOfOneCoreAtPeak = sample.attributedPercentOfOneCore
        unattributedPercentOfOneCoreAtPeak = sample.unattributedPercentOfOneCore
        logicalCoreCount = sample.logicalCoreCount
        confidence = Self.confidence(for: sample)
    }

    /// The application the incident was attributed to, if any.
    public var leadingApplication: IncidentContributor? { applications.first }

    public var unattributedShare: Double {
        guard peakTotalBusyPercentOfOneCore > 0 else { return 0 }
        return unattributedPercentOfOneCoreAtPeak / peakTotalBusyPercentOfOneCore
    }

    /// The recorded figures, each with its evidence class, so a screen showing the
    /// working of a closed incident shows numbers that sum (FR-055).
    public var figures: [AttributedFigure] {
        [
            AttributedFigure(label: "Peak total CPU",
                             percentOfOneCore: peakTotalBusyPercentOfOneCore,
                             evidence: .measured),
            AttributedFigure(label: "Attributed to applications",
                             percentOfOneCore: attributedPercentOfOneCoreAtPeak,
                             evidence: .measured),
            AttributedFigure(label: "Unattributed system activity",
                             percentOfOneCore: unattributedPercentOfOneCoreAtPeak,
                             evidence: .calculated),
        ]
    }

    /// The naming statement, with its confidence inseparable from it.
    ///
    /// `nil` when nothing measurable was attributed — an honest omission rather
    /// than a sentence naming whatever happened to be top of an empty list.
    public var conclusion: Conclusion? {
        guard let leader = leadingApplication else { return nil }
        var text = "\(leader.displayName) was the largest measurable contributor while this "
        text += "was happening, peaking at "
        text += "\(Int(leader.peakPercentOfOneCore.rounded()))% of one core."
        if unattributedShare > 0.3 {
            text += " A large share of activity could not be attributed to any process we are "
            text += "permitted to measure, so it may not have been the largest contributor "
            text += "overall — only the largest we could see."
        }
        if leader.hasUncertainMembers {
            text += " Some processes were grouped under this application on the strength of "
            text += "their location alone."
        }
        return Conclusion(text, evidence: .heuristic, confidence: confidence)
    }

    /// Confidence falls as the unattributable share rises, on the same calibration
    /// the live summariser uses, so an incident does not change its story
    /// depending on which screen is asking.
    static func confidence(for sample: AttributionSample) -> Confidence {
        let total = sample.totalBusyPercentOfOneCore
        let leaderShare = total > 0
            ? (sample.applications.first?.peakPercentOfOneCore ?? 0) / total
            : 0
        let unattributedShare = total > 0 ? sample.unattributedPercentOfOneCore / total : 0
        return IncidentSummarizer.confidence(
            leaderShare: leaderShare, unattributedShare: unattributedShare)
    }
}

/// How often one application led the attribution across recent incidents (FR-013).
///
/// The claim this supports — "Chrome was the largest measurable contributor in 5 of
/// them" — is a heuristic over heuristics, so it carries the **weakest** confidence
/// of the incidents it counts. Averaging would let two low-confidence records
/// combine into a confident-looking pattern.
public struct ApplicationRecurrence: Sendable, Equatable, Identifiable {
    public let applicationID: String
    public let displayName: String
    /// Incidents in which this application led.
    public let incidentCount: Int
    /// Incidents that carried a recorded attribution at all. Not the total number
    /// of incidents: one with nothing attributable is not evidence either way, and
    /// counting it in the denominator would understate a real pattern.
    public let attributedIncidentCount: Int
    public let confidence: Confidence

    public var id: String { applicationID }

    public var conclusion: Conclusion {
        Conclusion(
            "\(displayName) was the largest measurable contributor in \(incidentCount) of "
                + "the \(attributedIncidentCount) recent slowdowns we could attribute.",
            evidence: .heuristic, confidence: confidence)
    }
}

public enum IncidentRecurrence {
    /// Applications that led the attribution in several recent incidents.
    ///
    /// Gated so a pattern is not claimed from too little: by default at least three
    /// attributable incidents must exist and an application must lead in at least
    /// three of them.
    public static func leadingApplications(
        in incidents: [Incident],
        minimumAttributedIncidents: Int = 3,
        minimumOccurrences: Int = 3
    ) -> [ApplicationRecurrence] {
        let leaders = incidents.compactMap { incident -> (IncidentContributor, Confidence)? in
            guard let attribution = incident.attribution,
                  let leader = attribution.leadingApplication else { return nil }
            return (leader, attribution.confidence)
        }
        guard leaders.count >= minimumAttributedIncidents else { return [] }

        var counts: [String: (contributor: IncidentContributor, count: Int, weakest: Confidence)] = [:]
        for (leader, confidence) in leaders {
            if var existing = counts[leader.applicationID] {
                existing.count += 1
                existing.weakest = min(existing.weakest, confidence)
                counts[leader.applicationID] = existing
            } else {
                counts[leader.applicationID] = (leader, 1, confidence)
            }
        }

        return counts.values
            .filter { $0.count >= minimumOccurrences }
            .map {
                ApplicationRecurrence(
                    applicationID: $0.contributor.applicationID,
                    displayName: $0.contributor.displayName,
                    incidentCount: $0.count,
                    attributedIncidentCount: leaders.count,
                    confidence: $0.weakest)
            }
            .sorted {
                $0.incidentCount == $1.incidentCount
                    ? $0.displayName < $1.displayName
                    : $0.incidentCount > $1.incidentCount
            }
    }
}

extension Confidence: Comparable {
    private var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}
