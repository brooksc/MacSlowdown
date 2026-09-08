import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// FR-063 — a measured resource condition is not a slowdown the user experienced.
///
/// The rule this defends came out of two independent product reviews reaching the
/// same conclusion. We measure resources; we had been reporting them as slowdowns.
/// A capped build and a genuine slowdown produce the same reading, for the same
/// duration, with the same attribution — the only thing separating them is whether
/// the person started the work deliberately, which we cannot observe. So a headline
/// asserting the Mac is slow, heavily loaded or under strain is not merely
/// over-eager: on the most common busy state of a developer's machine it is wrong,
/// and it tells the user we have misread what they are doing.
///
/// These are sweeps rather than exact-string assertions on purpose. The wording is
/// design's to change; the claim is not.

/// Phrases that assert something about the user's experience rather than about a
/// measurement. "Slow" is the whole point. "Heavily loaded", "working hard" and
/// "under strain" are verdicts on the machine's condition dressed as readings.
private let experienceClaims = [
    "slowing", "is slow", "slowdown is", "slowdown in progress",
    "heavily loaded", "working hard", "under strain", "struggling",
    "your mac is", "this mac is working",
]

private func assertStatesAMeasurement(_ text: String, _ comment: Comment) {
    let lowered = text.lowercased()
    for claim in experienceClaims {
        #expect(!lowered.contains(claim),
                Comment(rawValue: "\"\(claim)\" in: \(text) — \(comment)"))
    }
}

private func incident(
    conditions: Set<IncidentCondition> = [.cpuSaturation],
    severity: IncidentSeverity = .high
) -> Incident {
    let began = Date().addingTimeInterval(-600)
    return Incident(
        id: UUID(), beganAt: began, triggeredAt: began.addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: nil,
        conditions: conditions, severity: severity,
        peakCPUBusyFraction: 0.97, peakMemoryPressure: .normal)
}

@MainActor
@Suite("A measurement is never reported as an experience (FR-063)")
struct ConditionNotExperienceTests {
    /// The headline a person sees most often, in every state it has.
    @Test("The Now verdict states a measurement in all three states and during an incident")
    func nowVerdictStatesMeasurements() {
        let attribution = CPUAttribution(
            totalBusyPercentOfOneCore: 760,
            attributedPercentOfOneCore: 400,
            unattributedPercentOfOneCore: 360,
            contributors: [],
            protectedProcesses: [],
            logicalCoreCount: 8)

        for severity in [Severity.normal, .elevated, .severe] {
            for open in [false, true] {
                let verdict = NowPresentation.verdict(
                    severity: severity, attribution: attribution, incidentOpen: open)
                assertStatesAMeasurement(
                    verdict.headline, "Now headline, \(severity), incidentOpen \(open)")
                assertStatesAMeasurement(
                    verdict.detail, "Now detail, \(severity), incidentOpen \(open)")
            }
        }
    }

    @Test("The popover verdict states a measurement in all three states and during an incident")
    func popoverVerdictStatesMeasurements() {
        for severity in [Severity.normal, .elevated, .severe] {
            for open in [false, true] {
                assertStatesAMeasurement(
                    PopoverPresentation.verdict(severity: severity, incidentOpen: open).headline,
                    "popover headline, \(severity), incidentOpen \(open)")
            }
        }
    }

    /// Every combination of conditions, including the empty fallback that used to
    /// read "Your Mac was under sustained load".
    @Test("Incident headlines describe the conditions measured, not their effect")
    func incidentHeadlinesStateConditions() {
        let sets: [Set<IncidentCondition>] = [
            [], [.cpuSaturation], [.memoryPressure], [.thermalPressure], [.lowStorage],
            [.cpuSaturation, .memoryPressure],
        ]
        for conditions in sets {
            let subject = incident(conditions: conditions)
            assertStatesAMeasurement(
                IncidentVerdict.headline(for: subject, duration: "6 minutes"),
                "incident headline for \(conditions)")
            assertStatesAMeasurement(
                PopoverPresentation.incidentHeadline(subject, now: Date()),
                "popover incident headline for \(conditions)")
        }
    }

    /// Severity orders measurements; it does not describe how the machine felt.
    /// This is the distinction that lets a "severe" reading sit under a headline
    /// that claims nothing about the user's afternoon.
    @Test("Severity words never stand in for a claim about the user's experience")
    func severityIsNotImpact() {
        for severity in [IncidentSeverity.moderate, .high, .severe] {
            assertStatesAMeasurement(severity.label, "severity label")
        }
        for severity in [Severity.normal, .elevated, .severe] {
            assertStatesAMeasurement(severity.label, "live severity label")
        }
    }
}
