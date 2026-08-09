import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// A settings store on its own defaults suite, so a test never reads or writes
/// the user's real preferences.
@MainActor
private func isolatedSettings(
    _ name: String = UUID().uuidString
) -> (settings: AlertSettings, defaults: UserDefaults) {
    let defaults = UserDefaults(suiteName: name)!
    return (AlertSettings(defaults: defaults), defaults)
}

@MainActor
@Suite("Alert sensitivity reads as plain language")
struct AlertSensitivityTests {
    /// The point of the plain choice is that the sentence under it is true. It is
    /// derived from the policy rather than written out, and this checks the two
    /// cannot come apart.
    @Test("Each choice restates its own sustained duration")
    func restatementMatchesPolicy() {
        for sensitivity in AlertSensitivity.allCases {
            let spelled = AlertSettings.spell(sensitivity.policy.cpuSustainedDuration)
            #expect(sensitivity.restatement.contains(spelled))
            #expect(sensitivity.restatement.hasPrefix(sensitivity.label))
        }
    }

    /// The middle choice must be the shipped defaults, not a second copy of the
    /// same numbers that can drift.
    @Test("Balanced is exactly the default incident policy")
    func balancedIsTheDefault() {
        #expect(AlertSensitivity.balanced.policy.cpuSustainedDuration
            == IncidentPolicy.default.cpuSustainedDuration)
        #expect(AlertSensitivity.balanced.policy.cpuBusyFractionThreshold
            == IncidentPolicy.default.cpuBusyFractionThreshold)
    }

    @Test("More sensitive means sooner and lower, in that order")
    func orderingIsMonotonic() {
        let ordered: [AlertSensitivity] = [.relaxed, .balanced, .sensitive]
        let durations = ordered.map(\.policy.cpuSustainedDuration.totalSeconds)
        let thresholds = ordered.map(\.policy.cpuBusyFractionThreshold)
        #expect(durations == durations.sorted(by: >))
        #expect(thresholds == thresholds.sorted(by: >))
    }

    /// FR-006: sensitivity changes what interrupts, never what is recorded. The
    /// only thing it may touch on the notification side is the announce floor.
    @Test("Sensitivity only ever raises or lowers the announcement floor")
    func sensitivityChangesInterruptionOnly() {
        #expect(AlertSensitivity.relaxed.minimumSeverity > AlertSensitivity.balanced.minimumSeverity)
        #expect(AlertSensitivity.balanced.minimumSeverity
            > AlertSensitivity.sensitive.minimumSeverity)
    }

    /// FR-054: a threshold has to be quoted the way the incident report quotes it,
    /// or a user cannot tell whether the number they set is the number that fired.
    @Test("Thresholds are spelled in the units incident detail uses")
    func unitsMatchIncidentDetail() {
        #expect(AlertSettings.spellCPU(fraction: 0.85) == "85% of this Mac's capacity")
        let spelled = AlertSettings.spell(.seconds(180))
        #expect(spelled == DateComponentsFormatter.incidentDuration.string(from: 180))
    }
}

@MainActor
@Suite("Alert settings store", .serialized)
struct AlertSettingsStoreTests {
    @Test("Defaults are the shipped behaviour, not an invented one")
    func defaultsMatchTheApp() {
        let (settings, _) = isolatedSettings()
        #expect(settings.sensitivity == .balanced)
        #expect(settings.announceIncidents)
        #expect(settings.deferDuringAudio)
        #expect(!settings.usesCustomThresholds)
        #expect(settings.incidentPolicy.cpuSustainedDuration
            == IncidentPolicy.default.cpuSustainedDuration)
    }

    @Test("Choices survive a relaunch")
    func choicesPersist() {
        let name = UUID().uuidString
        let (settings, defaults) = isolatedSettings(name)
        settings.sensitivity = .sensitive
        settings.deferDuringAudio = false
        settings.retention = .sevenDays
        settings.recordFilePaths = true

        let restored = AlertSettings(defaults: defaults)
        #expect(restored.sensitivity == .sensitive)
        #expect(!restored.deferDuringAudio)
        #expect(restored.retention == .sevenDays)
        #expect(restored.recordFilePaths)
    }

    /// Choosing a word re-seeds the numbers, so the disclosure always shows what
    /// the word means rather than a stale set from an earlier choice.
    @Test("Changing the plain choice moves the exact figures with it")
    func sensitivityReseedsThresholds() {
        let (settings, _) = isolatedSettings()
        settings.sensitivity = .sensitive
        #expect(settings.cpuSustainedSeconds
            == AlertSensitivity.sensitive.policy.cpuSustainedDuration.totalSeconds)
        #expect(settings.cpuBusyFractionThreshold
            == AlertSensitivity.sensitive.policy.cpuBusyFractionThreshold)
    }

    @Test("Edited figures override the word, and can be put back")
    func customThresholdsOverride() {
        let (settings, _) = isolatedSettings()
        settings.usesCustomThresholds = true
        settings.cpuSustainedSeconds = 45
        settings.cpuBusyFractionThreshold = 0.7
        #expect(settings.incidentPolicy.cpuSustainedDuration == .seconds(45))
        #expect(settings.incidentPolicy.cpuBusyFractionThreshold == 0.7)

        settings.useThresholdsFromSensitivity()
        #expect(!settings.usesCustomThresholds)
        #expect(settings.incidentPolicy.cpuSustainedDuration
            == settings.sensitivity.policy.cpuSustainedDuration)
    }

    /// The memory-pressure *level* is not configurable because nothing reads any
    /// other value. Making it a stored constant is what stops a picker appearing
    /// that would silently do nothing.
    @Test("The memory pressure floor is fixed at warning")
    func memoryFloorIsFixed() {
        let (settings, _) = isolatedSettings()
        #expect(settings.memoryPressureFloor == .warning)
    }

    /// FR-029: paths off unless the user asks, and the retention default is the
    /// framework's rather than a second opinion held by the UI.
    @Test("Privacy defaults are the framework's own")
    func privacyDefaults() {
        let (settings, _) = isolatedSettings()
        #expect(!settings.recordFilePaths)
        #expect(settings.privacySettings.recordFilePaths == false)
        #expect(settings.retention == PrivacySettings.default.retention)
    }

    /// Turning alerts off must not lower the recording bar — only the announcing
    /// one. The gate reads `minimumSeverity`; nothing about detection changes.
    @Test("Silencing alerts raises the announcement floor and nothing else")
    func silencingTouchesInterruptionOnly() {
        let (settings, _) = isolatedSettings()
        let before = settings.incidentPolicy
        settings.announceIncidents = false
        #expect(settings.notificationSettings.minimumSeverity == .severe)
        #expect(settings.incidentPolicy.cpuSustainedDuration == before.cpuSustainedDuration)
        #expect(settings.incidentPolicy.cpuBusyFractionThreshold
            == before.cpuBusyFractionThreshold)
    }

    /// The interface says "saved, but not yet in effect" until something consumes
    /// these values. It must start out saying so, or the claim is decorative.
    @Test("Settings report themselves as not yet applied until a consumer says otherwise")
    func appliedFlagStartsFalse() {
        let (settings, _) = isolatedSettings()
        #expect(!settings.isAppliedToMonitoring)
        settings.markAppliedToMonitoring()
        #expect(settings.isAppliedToMonitoring)
    }

    /// FR-014: Focus is honoured by macOS, not by us. Leaving `respectFocus` on
    /// and offering no toggle keeps the gate's check in place without claiming a
    /// decision the app cannot make.
    @Test("Focus handling stays on and is not a user control")
    func focusIsNotAControl() {
        let (settings, _) = isolatedSettings()
        #expect(settings.notificationSettings.respectFocus)
    }
}

@MainActor
@Suite("Per-app rules")
struct AppRuleVocabularyTests {
    /// FR-016: the vocabulary is a sentence a person would say, not a severity
    /// enum in disguise.
    @Test("Every rule reads as plain language")
    func vocabularyIsPlain() {
        let labels = PolicyClassification.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(labels.allSatisfy { $0.first?.isUppercase == true && $0.count > 6 })
    }

    /// The guarantee the Apps tab prints: a rule changes what is flagged, never
    /// what is recorded. `PolicyStore` has no path that removes a measurement, and
    /// suppression is written to an audit trail rather than dropped.
    @Test("Suppressing an alert leaves an audit record behind")
    func suppressionIsAudited() {
        let store = PolicyStore()
        store.recordSuppression(SuppressedDetection(
            application: "HandBrake", classification: .ignored, severity: .high))
        #expect(store.suppressedDetections.count == 1)
        #expect(store.suppressedDetections[0].summary.contains("not alerted"))
    }

    /// The app must hold exactly one store, or Settings and the inventory
    /// inspector will disagree about what the user marked expected.
    @Test("The app's rules come from one shared store")
    func oneSharedStore() {
        let created = ApplicationPolicy(
            bundleID: "com.example.settings-test", displayName: "Settings Test",
            classification: .expected)
        MonitorStore.shared.policies.setPolicy(created)
        #expect(MonitorStore.shared.policies.policies.contains { $0.id == created.id })
        MonitorStore.shared.policies.removePolicy(id: created.id)
        #expect(!MonitorStore.shared.policies.policies.contains { $0.id == created.id })
    }
}

@Suite("Stored data")
struct StoredDataTests {
    /// FR-029 wants retention shown with what it costs. An unreadable folder says
    /// so; it never reports a made-up figure.
    @Test("Usage is either a real size, nothing, or an admission")
    func usageIsHonest() {
        let description = StoredData.usageDescription()
        #expect(!description.isEmpty)
        #expect(description.contains("Currently using"))
    }

    /// Rules are the user's decisions, not recorded evidence. Deleting history
    /// must not take them with it.
    @Test("Deleting history never targets the rules file")
    func rulesAreNotHistory() {
        #expect(!StoredData.recordedEvidenceFiles().contains {
            $0.lastPathComponent == StoredData.rulesFileName
        })
    }
}

@MainActor
@Suite("Login item wording distinguishes a location from a fault")
struct LoginItemLocationTests {
    /// TASK-64: a developer running out of `.build` sees `notFound` constantly.
    /// Saying "the app could not be found" makes that indistinguishable from a
    /// broken install.
    @Test("A build run from outside Applications is named as such, not as a fault")
    func locationIsNotAFault() {
        let text = LoginItem.explanation(
            for: .unavailableFromThisLocation(directory: "/Users/x/code/.build/Debug"))
        #expect(text.contains("/Users/x/code/.build/Debug"))
        #expect(text.contains("Applications"))
        #expect(text.lowercased().contains("nothing is wrong"))
    }

    @Test("The two unavailable states do not read the same")
    func statesAreDistinguishable() {
        let location = LoginItem.explanation(
            for: .unavailableFromThisLocation(directory: "/tmp"))
        let fault = LoginItem.explanation(
            for: .unavailable("The app could not be found by the system."))
        #expect(location != fault)
    }

    @Test("An installed copy is not excused as a location problem")
    func installedCopyReportsARealFailure() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(LoginItem.unregisterableLocation(
            bundleURL: URL(fileURLWithPath: "/Applications/MacSlowdown.app"),
            home: home) == nil)
        #expect(LoginItem.unregisterableLocation(
            bundleURL: URL(fileURLWithPath: "/Users/x/Applications/MacSlowdown.app"),
            home: home) == nil)
        #expect(LoginItem.unregisterableLocation(
            bundleURL: URL(fileURLWithPath: "/Users/x/code/.build/MacSlowdown.app"),
            home: home) == "/Users/x/code/.build")
    }

    /// A control the system will refuse must not look operable.
    @Test("The toggle is inert in every state the system will refuse")
    func toggleIsInertWhenRefused() {
        let refused: [LoginItem.State] = [
            .requiresApproval,
            .unavailableFromThisLocation(directory: "/tmp"),
            .unavailable("nope"),
        ]
        for state in refused {
            #expect(!LoginItem.isAdjustable(state))
        }
        #expect(LoginItem.isAdjustable(.enabled))
        #expect(LoginItem.isAdjustable(.disabled))
    }
}
