import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// FR-065 — confidence in what was measured, in which application it is attributed
/// to, and in whether the user was affected are three independent things.
///
/// The failure this guards is the most expensive one available. "Sustained memory
/// pressure was measured" and "Xcode is slowing your Mac" differ in three ways, and
/// a product that runs them together will be confidently wrong in the one direction
/// that costs a person their afternoon: sending them to quit useful work. The
/// measurement is usually the certain part; the name is the guess; what any of it
/// did to them we never measured at all.
///
/// Written as sweeps rather than exact-string assertions, in the style of
/// `ConditionNotExperienceTests` and for the same reason: the wording belongs to
/// design, the separation does not.

// MARK: - The third leg, which is held by absence (FR-063, FR-065)

/// Phrases that assert an effect on the person rather than a reading from the
/// machine. FR-063 removed these from the headlines; these are the ones that
/// survived inside sentences that also carry an attribution, where a single
/// confidence label then stood for both claims at once.
private let impactClaims = [
    "feel slower", "feel faster", "felt slow", "feels slow",
    "make everything", "slowing your", "slowing you",
]

private func assertClaimsNoImpact(_ text: String, _ comment: Comment) {
    let lowered = text.lowercased()
    for claim in impactClaims {
        #expect(!lowered.contains(claim),
                Comment(rawValue: "\"\(claim)\" in: \(text) — \(comment)"))
    }
}

// MARK: - Fixtures

private func contributor(
    _ name: String, peak: Double, uncertain: Bool
) -> IncidentContributor {
    IncidentContributor(
        applicationID: "/Applications/\(name).app",
        displayName: name,
        bundleID: "com.example.\(name.lowercased())",
        bundlePath: "/Applications/\(name).app",
        peakPercentOfOneCore: peak,
        hasUncertainMembers: uncertain)
}

/// A sweep in which the measurement is as good as it ever gets: nearly all busy CPU
/// was readable, and one application holds the great majority of it. On the
/// measurement alone this is the `.high` case.
private func cleanSample(uncertainLeader: Bool) -> AttributionSample {
    AttributionSample(
        applications: [contributor("Suspect", peak: 700, uncertain: uncertainLeader),
                       contributor("Other", peak: 50, uncertain: false)],
        totalBusyPercentOfOneCore: 800,
        attributedPercentOfOneCore: 750,
        unattributedPercentOfOneCore: 50,
        logicalCoreCount: 10)
}

@MainActor
@Suite("Measurement, attribution and impact confidence stay separate (FR-065)")
struct ConfidenceSeparationTests {
    // MARK: A measurement never confers its certainty on a name

    /// The defect this test exists for: both inputs to the attribution confidence —
    /// the leader's share and the unattributable remainder — describe how well we
    /// *measured*, and neither says whether the processes we added together are one
    /// application. A clean, concentrated sweep therefore returned "high confidence"
    /// for a family held together by nothing better than a shared directory.
    @Test("An uncertain grouping caps confidence even when the measurement is perfect")
    func uncertainGroupingIsNotRescuedByAGoodMeasurement() {
        #expect(IncidentAttribution.confidence(for: cleanSample(uncertainLeader: false))
                == .high,
                "the measurement half of the calibration must be unchanged")
        #expect(IncidentAttribution.confidence(for: cleanSample(uncertainLeader: true))
                <= .moderate,
                "a certain measurement handed its certainty to an uncertain name")
    }

    /// Capped, not fixed — the same shape as `RelaunchPattern.causeConfidence`. Weak
    /// grouping does not make an attribution worthless; it makes it unable to be the
    /// strongest thing we say. A sweep that was already low must not be *raised* to
    /// moderate by adding uncertainty to it.
    @Test("The grouping cap lowers confidence and never raises it")
    func capLowersOnly() {
        let mostlyUnreadable = AttributionSample(
            applications: [contributor("Suspect", peak: 90, uncertain: true)],
            totalBusyPercentOfOneCore: 900,
            attributedPercentOfOneCore: 90,
            unattributedPercentOfOneCore: 810,
            logicalCoreCount: 10)
        #expect(IncidentAttribution.confidence(for: mostlyUnreadable) == .low)
    }

    /// The label a step lower is not by itself an explanation, so the prose still
    /// says what is uncertain and why (FR-065's fourth criterion).
    @Test("An uncertain grouping is also stated in words, not only in the label")
    func uncertaintyIsStatedInWords() {
        let recorded = IncidentAttribution(
            sample: cleanSample(uncertainLeader: true), at: Date())
        #expect(recorded.conclusion?.text.lowercased().contains("grouped under this application")
                == true,
                "the reason confidence is capped must be readable, not inferred from a word")
    }

    // MARK: One label, one question

    /// A bare "moderate confidence" under a headline naming an application does not
    /// say which of the three confidences is being qualified, and a reader will take
    /// it for the finding entire — including the CPU figure in the same sentence,
    /// which is a measurement and is not in doubt.
    @Test("Every qualifier that accompanies a name says which question it answers")
    func qualifiersNameTheirSubject() {
        for confidence in Confidence.allCases {
            let qualifier = NowPresentation.attributionQualifier(confidence)
            #expect(qualifier.contains("which application"),
                    "\(qualifier) does not say what it is confidence in")
            #expect(qualifier.contains(confidence.label))
        }
    }

    /// Both surfaces that put a name in front of a person — the Now banner and the
    /// popover's live incident headline — carry the same subject-naming qualifier,
    /// because a name shown without it is the stronger claim of the two.
    @Test("The banner names its subject whenever it names an application")
    func bannerQualifierNamesItsSubject() {
        let began = Date().addingTimeInterval(-600)
        var incident = Incident(
            id: UUID(), beganAt: began, triggeredAt: began.addingTimeInterval(180),
            recoveryStartedAt: nil, closedAt: nil,
            conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.97, peakMemoryPressure: .normal)
        incident.attribution = IncidentAttribution(
            sample: cleanSample(uncertainLeader: false), at: began)

        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: "CPU was near capacity for 10 minutes")
        #expect(headline.text.contains("Suspect"), "this fixture is meant to name an application")
        #expect(headline.qualifier?.contains("which application") == true)
    }

    /// The condition-only headline names no application, so there is no attribution
    /// to be confident about and no qualifier to show. Silence is the right answer:
    /// a label here would imply a claim the sentence does not make.
    @Test("A headline that states only a measurement carries no confidence label")
    func measurementOnlyHeadlineHasNoQualifier() {
        let began = Date().addingTimeInterval(-600)
        let incident = Incident(
            id: UUID(), beganAt: began, triggeredAt: began.addingTimeInterval(180),
            recoveryStartedAt: nil, closedAt: nil,
            conditions: [.memoryPressure], severity: .high,
            peakCPUBusyFraction: 0.4, peakMemoryPressure: .critical)
        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: "Memory pressure was critical for 10 minutes")
        #expect(headline.qualifier == nil)
    }

    // MARK: No numerical score, in any state

    /// FR-065 forbids a number, everywhere, in every state. Withholding it is
    /// deliberate: a percentage hands our problem to someone who has no way to
    /// resolve it. The distinction lives in the wording instead, which is what the
    /// tests above hold.
    @Test("No confidence is ever expressed as a number")
    func noNumericalScores() {
        var strings: [String] = []
        for confidence in Confidence.allCases {
            strings.append(confidence.label)
            strings.append(NowPresentation.attributionQualifier(confidence))
            strings.append(PopoverPresentation.cause(
                leaderName: "Suspect",
                leaderPercentOfOneCore: 700,
                totalBusyPercentOfOneCore: 800,
                unattributedShare: 0.06,
                confidence: confidence).display)
        }
        for evidence in Evidence.allCases { strings.append(evidence.label) }

        for text in strings {
            // A CPU figure is a measurement and may of course be a number. What must
            // never be a number is the confidence, so the check runs on the part of
            // each string that talks about confidence.
            for fragment in text.components(separatedBy: " ")
            where fragment.lowercased().contains("confiden") {
                #expect(fragment.rangeOfCharacter(from: .decimalDigits) == nil,
                        Comment(rawValue: "numeric confidence in: \(text)"))
            }
            #expect(!text.contains("% confiden"),
                    Comment(rawValue: "numeric confidence in: \(text)"))
        }
    }

    // MARK: Impact is not folded into an attribution

    /// The popover's causal sentence used to close with "While that continues, other
    /// apps are likely to feel slower" — an attribution and an impact claim under one
    /// confidence label, so a reader who accepted the first inherited the second.
    @Test("The one causal sentence claims an attribution and nothing about impact")
    func causeSentenceMakesNoImpactClaim() {
        for share in [0.2, 0.6, 0.9] {
            for unattributed in [0.05, 0.5] {
                for confidence in Confidence.allCases {
                    let conclusion = PopoverPresentation.cause(
                        leaderName: "Suspect",
                        leaderPercentOfOneCore: 800 * share,
                        totalBusyPercentOfOneCore: 800,
                        unattributedShare: unattributed,
                        confidence: confidence)
                    assertClaimsNoImpact(
                        conclusion.text,
                        "cause, share \(share), unattributed \(unattributed)")
                }
            }
        }
    }

    /// A kernel pressure level says macOS is compressing and swapping. It does not
    /// say whether the person noticed, and the explanation must not either.
    @Test("A memory-pressure level explains what was measured, not how it felt")
    func memoryPressureExplanationsClaimNoImpact() {
        for level in MemoryPressureLevel.allCases {
            assertClaimsNoImpact(level.explanation, "pressure explanation, \(level.label)")
        }
    }

    /// The incident narrative, swept whole: the summariser's statements and the
    /// recorded attribution's sentence are where an impact claim would most easily
    /// reappear, because they are the ones that read like an account of an event.
    @Test("Nothing in an incident summary claims an effect on the user")
    func incidentSummaryClaimsNoImpact() {
        let began = Date().addingTimeInterval(-900)
        var incident = Incident(
            id: UUID(), beganAt: began, triggeredAt: began.addingTimeInterval(180),
            recoveryStartedAt: nil, closedAt: began.addingTimeInterval(800),
            conditions: [.cpuSaturation], severity: .severe,
            peakCPUBusyFraction: 0.98, peakMemoryPressure: .critical)
        incident.attribution = IncidentAttribution(
            sample: cleanSample(uncertainLeader: true), at: began)

        let summary = IncidentSummarizer.summarize(incident: incident, attribution: nil)
        #expect(summary.isWellFormed)
        assertClaimsNoImpact(summary.headline, "summary headline")
        for conclusion in summary.conclusions + summary.ruledOut {
            assertClaimsNoImpact(conclusion.display, "summary conclusion")
        }
    }
}
