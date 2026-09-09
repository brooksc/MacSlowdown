import Foundation
import Metrics
import Testing

@testable import MacSlowdown

/// TASK-112 and TASK-111 criterion 4, on the app side of the boundary. The gate's
/// own behaviour is asserted in `Metrics/Tests/NotificationPolicyTests.swift`; what
/// is checked here is that the settings a person touches produce it, and that the
/// sentences shown beside those settings say what the code does.
@MainActor
@Suite("Scoped suppression, the settings that produce it")
struct ScopedSuppressionSurfaceTests {
    private func isolated() -> AlertSettings {
        AlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    // MARK: - Per-condition interruption (design 5g)

    /// A condition nobody has decided about follows `announcesByDefault`, and the
    /// third state is visible as a third state rather than collapsed into an off.
    @Test("An untouched condition follows the default and reports that it is untouched")
    func untouchedConditionsFollowTheDefault() {
        let settings = isolated()
        #expect(settings.interrupts(.memoryPressure))
        #expect(!settings.interrupts(.cpuSaturation))
        #expect(!settings.hasDecided(about: .cpuSaturation))

        settings.setInterrupts(.cpuSaturation, false)
        // Setting it to what the default already said is still a decision, and the
        // screen has to be able to see that so it can offer to undo it.
        #expect(settings.hasDecided(about: .cpuSaturation))
    }

    @Test("A switched condition reaches the gate in the right direction")
    func switchesReachTheGate() {
        let settings = isolated()
        settings.setInterrupts(.cpuSaturation, true)
        settings.setInterrupts(.memoryPressure, false)

        let gate = settings.notificationSettings
        #expect(gate.announcedConditions.contains(.cpuSaturation))
        #expect(gate.silencedConditions.contains(.memoryPressure))
        #expect(gate.interrupts(.cpuSaturation))
        #expect(!gate.interrupts(.memoryPressure))
    }

    /// The switches survive a relaunch. They are the one part of this work that is
    /// meant to: the session-scoped rule below is the part that must not.
    @Test("A condition decision is remembered across a restart")
    func conditionDecisionsPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        AlertSettings(defaults: defaults).setInterrupts(.cpuSaturation, true)
        #expect(AlertSettings(defaults: defaults).interrupts(.cpuSaturation))
    }

    // MARK: - The session-scoped rule (design 5f)

    /// Criterion #2, and the reason it holds: nothing writes the session anywhere.
    /// A second `AlertSettings` over the same defaults — which is what a relaunch
    /// amounts to — cannot see a session that is running in this process.
    @Test("Quiet for this work session does not survive a relaunch")
    func sessionQuietIsNotPersisted() {
        let session = SessionQuiet()
        session.begin(at: Date(timeIntervalSince1970: 1_000))
        #expect(session.isActive)
        // A freshly constructed one is what a relaunch produces, because the state
        // lives in the object and nowhere else. If this ever fails, someone has
        // given the session a home on disk and broken the promise that it expires
        // at logout with nothing for the user to remember.
        #expect(!SessionQuiet().isActive)
    }

    @Test("A second press does not restart the session's clock")
    func sessionQuietDoesNotRestart() {
        let session = SessionQuiet()
        let first = Date(timeIntervalSince1970: 1_000)
        session.begin(at: first)
        session.begin(at: first.addingTimeInterval(600))
        #expect(session.startedAt == first)
    }

    /// Visible while active, and silent otherwise (design 5f). The sentence names
    /// the moment it was set and restates that recording continues.
    @Test("An active session says when it was set and that recording continues")
    func sessionQuietDescribesItself() {
        let session = SessionQuiet()
        #expect(session.statusDetail() == nil)
        session.begin(at: Date(timeIntervalSince1970: 1_000))
        let detail = session.statusDetail()
        #expect(detail?.contains("ends when you log out") == true)
        #expect(detail?.contains("still recorded") == true)

        session.end()
        #expect(session.statusDetail() == nil)
    }

    // MARK: - The offer (design 5f)

    private static let offer = SuppressionOffer(
        application: "Xcode", condition: .cpuSaturation)

    /// Three sentences, ordered by how much they give up: the temporary one first,
    /// then the narrow permanent one, then the broad one.
    @Test("The offer is three sentences in order of what they give up")
    func offerIsThreeSentencesInOrder() {
        #expect(Self.offer.options.map(\.choice)
            == [.session, .applicationAndCondition, .conditionAnywhere])
    }

    /// The narrow option has to make its narrowness concrete, or it reads the same
    /// as the broad one and nobody has a reason to prefer it.
    @Test("The application-scoped sentence names a condition still heard about")
    func theNarrowOptionSaysWhatSurvives() {
        let detail = Self.offer.options
            .first { $0.choice == .applicationAndCondition }?.detail
        #expect(detail?.contains("only Xcode") == true)
        #expect(detail?.contains("still hear about Xcode") == true)
    }

    /// FR-055's unattributable share is an ordinary case, not an error. With no
    /// application there is no application-scoped sentence, and nothing is guessed.
    @Test("An unattributed condition drops the application sentence rather than guessing")
    func unattributedOfferDropsTheNarrowOption() {
        let offer = SuppressionOffer(application: nil, condition: .memoryPressure)
        #expect(offer.options.map(\.choice) == [.session, .conditionAnywhere])
        #expect(offer.subtitle.contains("could not attribute"))
    }

    /// The subtitle deliberately does not lead with a rank. A sheet that did would
    /// invite exactly the ranking-keyed rule amendment 1 removes.
    @Test("The offer never claims a rank")
    func offerDoesNotClaimARank() {
        #expect(!Self.offer.subtitle.lowercased().contains("largest"))
        #expect(Self.offer.subtitle.contains("Xcode"))
    }

    /// Nothing here stops recording, and the sheet says so where the choice is
    /// made rather than somewhere the user would have to go and look.
    @Test("The offer promises that recording continues")
    func offerPromisesRecording() {
        #expect(SuppressionOffer.footer.contains("Nothing here stops MacSlowdown recording"))
        #expect(SuppressionOffer.footer.contains("reversible"))
    }

    // MARK: - Applying a choice

    /// Criterion #1, end to end through the store: the rule that comes out names
    /// one condition, and the gate settings built from it name the same one.
    @Test("Choosing the application-scoped option writes a rule naming one condition")
    func applyingWritesAScopedRule() {
        let policies = PolicyStore()
        let store = MonitorStore(policies: policies,
                                 storage: StorageScreenModel(history: StorageHistory()))
        let settings = isolated()
        SuppressionOfferAction.apply(
            .applicationAndCondition, offer: Self.offer,
            store: store, settings: settings, session: SessionQuiet())

        let rule = policies.policies.first { $0.displayName == "Xcode" }
        #expect(rule?.conditions == [.cpuSaturation])
        #expect(rule?.classification == .expected)
        #expect(rule?.applies(to: .memoryPressure) == false)
    }

    /// A second condition for the same application is a second statement, not a
    /// replacement of the first.
    @Test("A second condition is added to an application's rule, not swapped in")
    func applyingMergesConditions() {
        let policies = PolicyStore()
        let store = MonitorStore(policies: policies,
                                 storage: StorageScreenModel(history: StorageHistory()))
        let settings = isolated()
        let session = SessionQuiet()
        SuppressionOfferAction.apply(
            .applicationAndCondition, offer: Self.offer,
            store: store, settings: settings, session: session)
        SuppressionOfferAction.apply(
            .applicationAndCondition,
            offer: SuppressionOffer(application: "Xcode", condition: .thermalPressure),
            store: store, settings: settings, session: session)

        #expect(policies.policies.first { $0.displayName == "Xcode" }?.conditions
            == [.cpuSaturation, .thermalPressure])
    }

    @Test("The broad option silences the condition for every application")
    func applyingTheBroadOptionSilencesEverywhere() {
        let settings = isolated()
        SuppressionOfferAction.apply(
            .conditionAnywhere, offer: Self.offer,
            store: MonitorStore(policies: PolicyStore(),
                                storage: StorageScreenModel(history: StorageHistory())),
            settings: settings, session: SessionQuiet())
        #expect(!settings.interrupts(.cpuSaturation))
        #expect(settings.hasDecided(about: .cpuSaturation))
    }

    // MARK: - The sensitivity restatement (TASK-111 criterion 4)

    /// The defect: the three options were described as changing which severities
    /// announce, when they also move the CPU line. All three restatements have to
    /// say so, and each has to quote its own threshold rather than a shared one.
    @Test("Every sensitivity restatement discloses that it moves the threshold")
    func restatementDisclosesTheThreshold() {
        for sensitivity in AlertSensitivity.allCases {
            let restatement = sensitivity.restatement
            #expect(restatement.contains(AlertSensitivity.thresholdCaveat),
                    "\(sensitivity.label) does not say the line moves")
            #expect(restatement.contains(AlertSettings.spellCPU(
                fraction: sensitivity.policy.cpuBusyFractionThreshold)),
                    "\(sensitivity.label) does not quote its own CPU threshold")
            #expect(restatement.contains(sensitivity.minimumSeverity.label.lowercased()),
                    "\(sensitivity.label) no longer says which severities announce")
        }
    }

    /// The three thresholds the amendment names, read back off the policies so the
    /// restatement and the detector cannot quietly disagree.
    @Test("The three options really are three different CPU thresholds")
    func theThreeOptionsMoveTheLine() {
        #expect(AlertSensitivity.relaxed.policy.cpuBusyFractionThreshold == 0.92)
        #expect(AlertSensitivity.balanced.policy.cpuBusyFractionThreshold == 0.85)
        #expect(AlertSensitivity.sensitive.policy.cpuBusyFractionThreshold == 0.75)
    }

    // MARK: - The privacy disclosure (FR-029)

    /// An incomplete disclosure reads as a complete one, which is why this is a
    /// test and not a comment. Reports became a stored category when
    /// `SlowdownReportStore` started writing them.
    @Test("Slowdown reports appear in the stored-data disclosure")
    func reportsAppearInTheDisclosure() {
        let row = PrivacySettings.storedCategories
            .first { $0.category.lowercased().contains("reported") }
        #expect(row != nil)
        // The one stored thing that is the user's words rather than our readings.
        #expect(row?.detail.contains("yours rather than ours") == true)
        // And it must not repeat design 6d's claim that reports outlive everything
        // else: the build applies the same retention to them as to incidents.
        #expect(row?.detail.contains("same period as incidents") == true)
    }

    /// FR-029, and the reason "delete all history" is true of reports: the
    /// evidence sweep takes everything but the rules file.
    @Test("The reports file is recorded evidence, and the rules file is not")
    func reportsAreRecordedEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredDataReports-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["slowdown-reports.json", "incidents.json", StoredData.rulesFileName] {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
        }

        let evidence = StoredData.recordedEvidenceFiles(in: directory)
            .map(\.lastPathComponent)
        #expect(evidence.contains("slowdown-reports.json"))
        #expect(!evidence.contains(StoredData.rulesFileName))

        StoredData.deleteRecordedEvidence(in: directory)
        #expect(StoredData.recordedEvidenceFiles(in: directory).isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(StoredData.rulesFileName).path))
    }
}
