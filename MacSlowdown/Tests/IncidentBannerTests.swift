import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

// MARK: - Fixtures

private func bannerIncident(
    conditions: Set<IncidentCondition> = [.cpuSaturation],
    severity: IncidentSeverity = .high,
    attribution: IncidentAttribution? = nil,
    lifecycle: [RelaunchPattern] = []
) -> Incident {
    let began = Date(timeIntervalSince1970: 1_000_000)
    var incident = Incident(
        id: UUID(), beganAt: began, triggeredAt: began,
        recoveryStartedAt: nil, closedAt: began.addingTimeInterval(360),
        conditions: conditions, severity: severity,
        peakCPUBusyFraction: 0.94, peakMemoryPressure: .normal)
    incident.attribution = attribution
    incident.lifecycleFindings = lifecycle
    return incident
}

private func recordedAttribution(
    leader: String, leaderPercent: Double, total: Double, unattributed: Double = 0
) -> IncidentAttribution {
    IncidentAttribution(
        sample: AttributionSample(
            applications: [IncidentContributor(
                applicationID: leader, displayName: leader,
                bundleID: "com.example.\(leader)", bundlePath: "/Applications/\(leader).app",
                peakPercentOfOneCore: leaderPercent)],
            totalBusyPercentOfOneCore: total,
            attributedPercentOfOneCore: total - unattributed,
            unattributedPercentOfOneCore: unattributed,
            logicalCoreCount: 8),
        at: Date(timeIntervalSince1970: 1_000_000))
}

private func quitPattern(
    _ command: String, exits: Int, confidence: Confidence = .moderate
) -> RelaunchPattern {
    let first = Date(timeIntervalSince1970: 1_000_000)
    return RelaunchPattern(
        command: command, exits: exits, firstAt: first,
        lastAt: first.addingTimeInterval(180), confidence: confidence)
}

extension IncidentSeverity {
    fileprivate static let allSeverities: [IncidentSeverity] = [.moderate, .high, .severe]
}

// MARK: - Severity treatment

/// FR-034. The design draws the banner on an amber field. The requirement is that
/// deleting every colour from it loses nothing, because the severity word is in the
/// chip and the glyph's shape differs at each level.
@Suite("The incident banner's severity treatment")
struct IncidentBannerTreatmentTests {
    @Test("Colour is applied by default")
    func defaultTreatment() {
        let treatment = NowPresentation.BannerTreatment.resolve(
            increaseContrast: false, reduceTransparency: false)
        #expect(treatment == NowPresentation.BannerTreatment(usesTint: true, field: .tintedFill))
    }

    /// Increase Contrast is a request for foreground on background, so the tint goes
    /// entirely. Nothing is lost: the chip still reads "High".
    @Test("Increase Contrast removes the tint altogether")
    func increasedContrast() {
        let treatment = NowPresentation.BannerTreatment.resolve(
            increaseContrast: true, reduceTransparency: false)
        #expect(!treatment.usesTint)
        #expect(treatment.field == .plain)
        // With both settings on, contrast still wins: a tinted border would be
        // conveying by hue, which is what the contrast setting asked us not to do.
        #expect(NowPresentation.BannerTreatment.resolve(
            increaseContrast: true, reduceTransparency: true) == treatment)
    }

    /// Reduce Transparency is a request not to be shown a wash, so severity moves
    /// from a translucent fill into a solid border rather than disappearing.
    @Test("Reduce Transparency replaces the wash with a solid border")
    func reducedTransparency() {
        let treatment = NowPresentation.BannerTreatment.resolve(
            increaseContrast: false, reduceTransparency: true)
        #expect(treatment.usesTint)
        #expect(treatment.field == .tintedBorder)
    }

    /// The FR-034 rule in its strongest form: the three levels are distinguishable
    /// with the hue deleted, because each has its own glyph and its own word.
    @Test("Severity is carried by shape and word, not only by hue")
    func severityIsNotColourAlone() {
        let symbols = IncidentSeverity.allSeverities.map(NowPresentation.symbolName(for:))
        #expect(Set(symbols).count == IncidentSeverity.allSeverities.count)
        let tints = IncidentSeverity.allSeverities.map(NowPresentation.tint(for:))
        #expect(Set(tints).count == IncidentSeverity.allSeverities.count)
        for severity in IncidentSeverity.allSeverities {
            let incident = bannerIncident(severity: severity)
            #expect(NowPresentation.incidentChip(incident).contains(severity.label))
        }
    }
}

// MARK: - Headline

/// FR-013, FR-038. Design 1c's headline names an application. Naming one is a
/// heuristic claim, so the confidence recorded at the time has to survive into the
/// headline — otherwise the banner states a cause outright.
@Suite("The incident banner's headline")
struct IncidentBannerHeadlineTests {
    @Test("It names the application and keeps the recorded confidence")
    func namesTheApplication() {
        let incident = bannerIncident(
            attribution: recordedAttribution(
                leader: "Xcode", leaderPercent: 380, total: 500, unattributed: 40))
        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: "CPU saturation for 6 minutes")
        #expect(headline.text == "Xcode is using most of the CPU")
        #expect(headline.qualifier == "Likely · high confidence")
        #expect(headline.spoken.contains("high confidence"))
    }

    /// "Most of the CPU" is a claim about a majority. Where the recorded figures do
    /// not support one, the sentence still leads with the application but says only
    /// what was established.
    @Test("A minority contributor is not described as using most of the CPU")
    func minorityContributor() {
        let incident = bannerIncident(
            attribution: recordedAttribution(
                leader: "Xcode", leaderPercent: 120, total: 500, unattributed: 200))
        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: "CPU saturation for 6 minutes")
        #expect(headline.text == "Xcode is the largest measurable use of the CPU")
        #expect(headline.qualifier?.contains("confidence") == true)
    }

    /// A measured statement carries no confidence, and an incident that attributed
    /// itself to nothing must not acquire a subject from anywhere else.
    @Test("With nothing attributed the condition headline stands, unqualified")
    func fallsBackToTheCondition() {
        let headline = NowPresentation.bannerHeadline(
            incident: bannerIncident(),
            conditionHeadline: "CPU saturation for 6 minutes")
        #expect(headline.text == "CPU saturation for 6 minutes")
        #expect(headline.qualifier == nil)
        #expect(headline.spoken == "CPU saturation for 6 minutes")
    }

    /// TASK-82: a repeated-quit episode is about the command that kept exiting, even
    /// when something else was the largest CPU contributor at the time.
    @Test("A repeated-quit incident is headlined by what quit, not by what was busy")
    func repeatedQuitsWin() {
        let incident = bannerIncident(
            conditions: [.cpuSaturation, .repeatedApplicationQuits],
            attribution: recordedAttribution(
                leader: "Xcode", leaderPercent: 380, total: 500),
            lifecycle: [quitPattern("BackgroundShortc", exits: 4)])
        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: "Repeated unexpected quits for 3 minutes")
        #expect(headline.text.hasPrefix("BackgroundShortc"))
        #expect(!headline.text.contains("Xcode"))
        #expect(headline.text.contains("keeps quitting and reopening"))
        #expect(headline.qualifier == "Likely · moderate confidence")
    }

    /// FR-002: `p_comm` is 16 bytes, so a name that reached the limit is shown as
    /// cut off rather than as what the application is called.
    @Test("A truncated command is shown as truncated in the headline")
    func truncatedCommand() {
        let incident = bannerIncident(
            conditions: [.repeatedApplicationQuits],
            lifecycle: [quitPattern("BackgroundShortc", exits: 3)])
        let headline = NowPresentation.bannerHeadline(
            incident: incident, conditionHeadline: "Repeated unexpected quits")
        #expect(headline.text.contains("…"))
    }

    @Test("The pattern with the most exits is the subject")
    func leadingPattern() {
        let incident = bannerIncident(
            conditions: [.repeatedApplicationQuits],
            lifecycle: [quitPattern("alpha", exits: 3), quitPattern("beta", exits: 7)])
        #expect(NowPresentation.leadingRelaunchPattern(incident)?.command == "beta")
        #expect(NowPresentation.leadingRelaunchPattern(bannerIncident()) == nil)
    }
}

// MARK: - Actions

/// TASK-82 criterion #4, and design 1c's third action.
@Suite("The incident banner's actions")
struct IncidentBannerActionTests {
    private func member(_ command: String, pid: pid_t, startTime: UInt64) -> FamilyMember {
        FamilyMember(
            record: ProcessRecord(
                identity: ProcessIdentity(pid: pid, startTime: startTime),
                command: command, uid: getuid(), ppid: 1,
                metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1))),
            resolved: ResolvedIdentity(
                executablePath: "/usr/bin/\(command)", appBundlePath: nil,
                bundleID: nil, teamID: nil),
            membership: .certain)
    }

    /// A relaunched process has a new pid by construction, so the newest instance of
    /// the command is the only one still running.
    @Test("Bring-forward resolves the newest instance of the quitting command")
    func newestInstanceWins() {
        let families = [ProcessFamily(
            id: "shell", displayName: "shell", bundlePath: nil,
            members: [member("worker", pid: 10, startTime: 100),
                      member("worker", pid: 900, startTime: 900),
                      member("other", pid: 11, startTime: 990)])]
        let found = NowPresentation.familyMember(forCommand: "worker", in: families)
        #expect(found?.record.identity.pid == 900)
        #expect(NowPresentation.familyMember(forCommand: "absent", in: families) == nil)
    }

    /// FR-017, FR-050: the outcome is written from a read-back, and the wording for
    /// a write that did not land claims nothing happened.
    @Test("Marking a workload expected reports what was actually stored")
    func policyOutcomeIsHonest() {
        let saved = NowPresentation.expectedPolicyOutcome(name: "Xcode", saved: true)
        #expect(saved.contains("Recorded"))
        #expect(saved.contains("Monitoring and recording continue"))
        let failed = NowPresentation.expectedPolicyOutcome(name: "Xcode", saved: false)
        #expect(failed.contains("not saved"))
        #expect(!failed.contains("Recorded:"))
        #expect(NowPresentation.expectedPolicyActionTitle("Xcode")
            == "Heavy load is expected for Xcode")
    }

    /// The banner writes through the store's own `PolicyStore`, so the rule it
    /// records is the one every other surface reads (FR-016).
    @Test("The banner's policy reaches PolicyStore and is readable back")
    func policyIsWrittenThrough() throws {
        let store = PolicyStore(url: nil)
        let policy = ApplicationPolicy(
            bundleID: "com.example.Xcode", bundlePath: "/Applications/Xcode.app",
            displayName: "Xcode", classification: .expected)
        store.setPolicy(policy)
        let saved = try #require(store.policies.first { $0.id == policy.id })
        #expect(saved.classification == .expected)
        #expect(saved.classification.suppressesNotification)
    }
}
