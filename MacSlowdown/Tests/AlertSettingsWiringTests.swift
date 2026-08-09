import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-69, part 1: the Alerts tab used to change a stored value and no behaviour.
/// These tests are about the wiring — that a control reaches the running detector
/// and the running notification gate — not about what the detector then does with
/// it, which `MetricsTests` covers.

/// Settings on their own defaults suite, so a test never reads or writes the
/// user's real preferences.
@MainActor
private func isolatedSettings() -> AlertSettings {
    AlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
}

@MainActor
private func store(
    settings: AlertSettings, history: MetricsHistory = MetricsHistory()
) -> MonitorStore {
    MonitorStore(history: history, policies: PolicyStore(),
                 storage: StorageScreenModel(history: StorageHistory()),
                 alertSettings: settings)
}

private func sample(at timestamp: Date, busyPercentOfOneCore: Double) -> HistorySample {
    HistorySample(
        timestamp: timestamp, totalBusyPercentOfOneCore: busyPercentOfOneCore,
        attributedPercentOfOneCore: busyPercentOfOneCore,
        unattributedPercentOfOneCore: 0, topContributors: [])
}

@MainActor
@Suite("Alert settings reach the running monitor", .serialized)
struct AlertSettingsWiringTests {

    /// The whole point of the task. A stored value that no one reads is not a
    /// setting, so this asserts on the detector's policy rather than on the store.
    @Test("A chosen sensitivity becomes the detector's policy")
    func sensitivityReachesTheDetector() {
        let settings = isolatedSettings()
        let monitor = store(settings: settings)
        #expect(monitor.incidentPolicyInForce == IncidentPolicy.default)

        settings.sensitivity = .sensitive
        monitor.applyAlertSettings()
        #expect(monitor.incidentPolicyInForce
            == AlertSensitivity.sensitive.policy)
        #expect(monitor.incidentPolicyInForce.cpuSustainedDuration == .seconds(60))
    }

    @Test("An edited exact threshold becomes the detector's policy")
    func exactThresholdsReachTheDetector() {
        let settings = isolatedSettings()
        let monitor = store(settings: settings)

        settings.usesCustomThresholds = true
        settings.cpuBusyFractionThreshold = 0.62
        settings.cpuSustainedSeconds = 45
        monitor.applyAlertSettings()

        #expect(monitor.incidentPolicyInForce.cpuBusyFractionThreshold == 0.62)
        #expect(monitor.incidentPolicyInForce.cpuSustainedDuration == .seconds(45))
    }

    /// FR-014, and the audio deferral FR-019 asks for. `respectFocus` is checked
    /// too, because it is the one the interface says macOS holds — the gate's own
    /// check still has to be armed for the day a signal exists.
    @Test("Notification choices reach the gate")
    func notificationSettingsReachTheGate() {
        let settings = isolatedSettings()
        let monitor = store(settings: settings)

        settings.deferDuringAudio = false
        settings.sensitivity = .sensitive
        monitor.applyAlertSettings()
        #expect(!monitor.notificationSettingsInForce.deferDuringAudio)
        #expect(monitor.notificationSettingsInForce.minimumSeverity == .moderate)
        #expect(monitor.notificationSettingsInForce.respectFocus)
        #expect(monitor.notificationSettingsInForce.announcesIncidents)

        settings.announceIncidents = false
        monitor.applyAlertSettings()
        #expect(!monitor.notificationSettingsInForce.announcesIncidents)
    }

    /// FR-016: a per-app rule is a notification decision, and it has to arrive
    /// through the same path as everything else on the Alerts tab.
    @Test("An application marked expected reaches the gate as a suppression")
    func expectedApplicationsReachTheGate() {
        let settings = isolatedSettings()
        let policies = PolicyStore()
        let monitor = MonitorStore(policies: policies,
                                   storage: StorageScreenModel(history: StorageHistory()),
                                   alertSettings: settings)
        // `notificationSettings` reads the app's shared policy store, which is what
        // the Apps tab writes to.
        MonitorStore.shared.policies.setPolicy(ApplicationPolicy(
            bundleID: "com.example.task69", displayName: "TASK-69 Example",
            classification: .expected))
        defer { MonitorStore.shared.policies.removePolicy(id: "com.example.task69") }

        monitor.applyAlertSettings()
        #expect(monitor.notificationSettingsInForce.expectedApplications
            .contains("TASK-69 Example"))
    }

    /// Criterion #2. The notice is not dismissed by the interface; it retires
    /// because something applied the settings. Its copy is untouched.
    @Test("Applying the settings retires the 'not yet in effect' notice")
    func applyingRetiresTheNotice() {
        let settings = isolatedSettings()
        #expect(!settings.isAppliedToMonitoring)
        store(settings: settings).applyAlertSettings()
        #expect(settings.isAppliedToMonitoring)
    }

    /// A store with no settings injected — every test that drives the detector
    /// directly — must not reach for the user's real preferences.
    @Test("A store with no settings injected applies nothing")
    func noSettingsMeansNoApplication() {
        let monitor = MonitorStore(policies: PolicyStore(),
                                   storage: StorageScreenModel(history: StorageHistory()))
        #expect(monitor.applyAlertSettings() == false)
        #expect(monitor.incidentPolicyInForce == IncidentPolicy.default)
    }

    // MARK: - Part 2, end to end through the store

    /// Criterion #5, through the real path: the retained series the store already
    /// keeps is what a tightened threshold is re-decided against.
    @Test("Tightening a threshold is re-decided over the store's retained samples")
    func tighteningReadsTheRetainedSeries() {
        let settings = isolatedSettings()
        let history = MetricsHistory()
        let monitor = store(settings: settings, history: history)
        let cores = Double(monitor.machine.logicalCores)
        let now = Date()

        // Ten minutes at 80% of machine capacity: under the 85% default, so the
        // detector has never seen a breach.
        for offset in stride(from: -600.0, through: 0.0, by: 2.0) {
            history.append(sample(at: now.addingTimeInterval(offset),
                                  busyPercentOfOneCore: 0.80 * cores * 100))
        }

        settings.usesCustomThresholds = true
        settings.cpuBusyFractionThreshold = 0.75
        #expect(monitor.applyAlertSettings())
    }

    /// And the honest limit: with nothing retained there is nothing to look back
    /// over, so the clock starts from the change. Less is claimed, not more.
    @Test("With no retained readings, a tightened threshold claims nothing")
    func noHistoryMeansNoBackdating() {
        let settings = isolatedSettings()
        let monitor = store(settings: settings)
        settings.usesCustomThresholds = true
        settings.cpuBusyFractionThreshold = 0.60
        #expect(monitor.applyAlertSettings() == false)
    }
}
