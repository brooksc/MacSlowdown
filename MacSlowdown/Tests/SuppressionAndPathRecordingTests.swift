import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-76 and TASK-79: two controls that changed a stored value and no behaviour.
///
/// Both were found by the TASK-73 seam audit, and both had complete, well-tested
/// framework code on one side and no caller on the other. That is precisely the
/// shape a unit test cannot catch, so **every test here drives the app-level entry
/// point** — `MonitorStore.announce`, `MonitorStore.recordable`, a settings change —
/// and asserts the end effect. A test that called `PolicyStore.recordSuppression`
/// or `RetentionPolicy.expired` directly would have passed before the fix and after
/// it, which is how the defect survived this long.

/// Real "now", not a fixed instant: retention is applied on the way out of the
/// incident store against the wall clock, so an incident dated to a constant would
/// age out of the default 30-day window as soon as this file was a month old.
private let base = Date()

/// Settings on their own defaults suite, so a test never reads or writes the user's
/// real preferences.
@MainActor
private func isolatedSettings() -> AlertSettings {
    AlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
}

private func closedIncident(
    id: UUID = UUID(), severity: IncidentSeverity = .high
) -> Incident {
    Incident(
        id: id,
        beganAt: base.addingTimeInterval(-600),
        triggeredAt: base.addingTimeInterval(-480),
        recoveryStartedAt: base.addingTimeInterval(-120),
        closedAt: base.addingTimeInterval(-60),
        // Announces by default (FR-014 amendment 1). These tests are about rule,
        // mute and audio suppression, not about which condition it was.
        conditions: [.memoryPressure],
        severity: severity,
        peakCPUBusyFraction: 0.93,
        peakMemoryPressure: .normal)
}

private func scratchHistoryURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SuppressionAudit-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("incidents.json")
}

/// A store whose incident history holds a closed incident, so a suppression has
/// something to be linked to without the sampling loop having to run.
///
/// Backed by a scratch file rather than by memory, because `MonitorStore` reads its
/// history back through `load()` at construction and a memory-only store has
/// nothing to load. Never the user's real container: a test may not delete or
/// rewrite recorded history that belongs to someone.
///
/// Notifications go to a fake centre. `announce` hands an approved decision to
/// delivery, and the real centre would put a banner on the user's screen.
@MainActor
private func store(
    settings: AlertSettings,
    policies: PolicyStore,
    holding incidents: [Incident] = []
) -> MonitorStore {
    let history = IncidentHistoryStore(url: incidents.isEmpty ? nil : scratchHistoryURL())
    for incident in incidents {
        history.record(incident, settings: .default)
    }
    return MonitorStore(
        policies: policies,
        storage: StorageScreenModel(history: StorageHistory()),
        alertSettings: settings,
        incidentHistory: history,
        evidenceDirectory: nil,
        notifications: NotificationDelivery(centre: FakeNotificationCentre()))
}

// MARK: - TASK-76

@MainActor
@Suite("A rule that withholds an alert writes down that it did", .serialized)
struct SuppressionAuditTrailTests {
    private static let ruleID = "com.example.task76"
    private static let application = "TASK-76 Example"

    private static var rule: ApplicationPolicy {
        ApplicationPolicy(
            bundleID: ruleID, displayName: application, classification: .expected)
    }

    /// Criterion #1 and #3. The gate already suppressed correctly; what was missing
    /// was any record of it, so the assertion is on the trail and on the incident,
    /// not on the decision.
    @Test("A policy suppression reaches the audit trail and the incident")
    func policySuppressionIsRecorded() {
        let settings = isolatedSettings()
        let policies = PolicyStore()
        policies.setPolicy(Self.rule)
        // `AlertSettings.notificationSettings` builds `expectedApplications` from
        // the app's shared policy store, which is what the Apps tab writes to.
        MonitorStore.shared.policies.setPolicy(Self.rule)
        defer { MonitorStore.shared.policies.removePolicy(id: Self.ruleID) }

        let incident = closedIncident()
        let monitor = store(settings: settings, policies: policies, holding: [incident])
        monitor.applyAlertSettings()

        // The sheet's empty state is only honest while this is true.
        #expect(policies.suppressedDetections.isEmpty)

        let decision = monitor.announce(
            incident: incident, leadingContributor: Self.application,
            context: .quiet, at: base.addingTimeInterval(-300))

        #expect(!decision.shouldSend)
        #expect(decision.suppressionCause
            == .applicationPolicy(application: Self.application))

        let recorded = policies.suppressedDetections
        #expect(recorded.count == 1)
        #expect(recorded.first?.application == Self.application)
        #expect(recorded.first?.classification == .expected)
        #expect(recorded.first?.severity == .high)
        // Linked, so "why was I not told about *this*" is answerable from the
        // incident rather than only from a list the user has to correlate by hand.
        #expect(recorded.first?.incidentID == incident.id)

        let stored = monitor.recentIncidents.first
        #expect(stored?.id == incident.id)
        #expect(stored?.suppressions.count == 1)
        #expect(stored?.suppressions.first?.incidentID == incident.id)
        if case .notAlerted(let suppression) = stored?.outcome {
            #expect(suppression.application == Self.application)
        } else {
            Issue.record("the incident's own outcome should say it was not alerted")
        }
    }

    /// Criterion #2. A mute withheld the alert too, and it is not a rule about an
    /// application — recording it as one would answer "why was I not told" with
    /// somebody else's reason.
    @Test("A mute is suppressed without being written to the rules trail")
    func mutingIsNotRecordedAsARule() {
        let settings = isolatedSettings()
        let policies = PolicyStore()
        let incident = closedIncident()
        let monitor = store(settings: settings, policies: policies, holding: [incident])
        monitor.applyAlertSettings()
        monitor.mute(forMinutes: 30)

        let decision = monitor.announce(
            incident: incident, leadingContributor: "Something Unruled",
            context: .quiet, at: Date())

        #expect(!decision.shouldSend)
        #expect(decision.suppressionCause == .muted)
        #expect(policies.suppressedDetections.isEmpty)
        #expect(monitor.recentIncidents.first?.suppressions.isEmpty == true)
    }

    /// The same, for the audio deferral FR-019 asks for.
    @Test("An alert held during audio is not written to the rules trail")
    func audioDeferralIsNotRecordedAsARule() {
        let settings = isolatedSettings()
        let policies = PolicyStore()
        let incident = closedIncident()
        let monitor = store(settings: settings, policies: policies, holding: [incident])
        monitor.applyAlertSettings()

        let decision = monitor.announce(
            incident: incident, leadingContributor: "Something Unruled",
            context: InterruptionContext(audioActive: true, audioApplication: "Music"),
            at: Date())

        #expect(decision.suppressionCause == .audio)
        #expect(policies.suppressedDetections.isEmpty)
    }

    /// Criterion #4. The empty state has to stay reachable: an announced incident
    /// must not put anything in the trail, or the list would fill up with slowdowns
    /// the user *was* told about.
    @Test("An announced incident writes nothing to the trail")
    func announcedIncidentsAreNotRecorded() {
        let settings = isolatedSettings()
        let policies = PolicyStore()
        let incident = closedIncident(severity: .severe)
        let monitor = store(settings: settings, policies: policies, holding: [incident])
        monitor.applyAlertSettings()

        let decision = monitor.announce(
            incident: incident, leadingContributor: "Something Unruled",
            context: .quiet, at: Date())

        #expect(decision.shouldSend)
        #expect(policies.suppressedDetections.isEmpty)
    }

    /// A rule the store does not hold records nothing rather than guessing the
    /// classification. Inventing `.expected` would be putting words in the user's
    /// mouth in the one place that exists to report what they actually chose.
    @Test("A suppression with no matching rule records nothing rather than guessing")
    func unmatchedRuleRecordsNothing() {
        let settings = isolatedSettings()
        // Deliberately empty: the gate is told the application is expected, the
        // store holds no rule for it.
        let policies = PolicyStore()
        MonitorStore.shared.policies.setPolicy(Self.rule)
        defer { MonitorStore.shared.policies.removePolicy(id: Self.ruleID) }

        let incident = closedIncident()
        let monitor = store(settings: settings, policies: policies, holding: [incident])
        monitor.applyAlertSettings()

        let decision = monitor.announce(
            incident: incident, leadingContributor: Self.application,
            context: .quiet, at: base.addingTimeInterval(-300))

        #expect(decision.suppressionCause
            == .applicationPolicy(application: Self.application))
        #expect(policies.suppressedDetections.isEmpty)
    }
}

// MARK: - TASK-79

private func contributor(name: String, path: String?) -> IncidentContributor {
    IncidentContributor(
        applicationID: path ?? "name:\(name)",
        displayName: name,
        bundleID: "com.example.\(name.lowercased())",
        bundlePath: path,
        peakPercentOfOneCore: 220,
        hasUncertainMembers: false)
}

private let sampleWithPaths = AttributionSample(
    applications: [
        contributor(name: "Xcode", path: "/Applications/Xcode.app"),
        contributor(name: "kernel_task", path: nil),
    ],
    totalBusyPercentOfOneCore: 600,
    attributedPercentOfOneCore: 440,
    unattributedPercentOfOneCore: 160,
    logicalCoreCount: 10)

@MainActor
@Suite("'Record file paths' changes what is recorded", .serialized)
struct RecordFilePathsTests {
    /// The default. FR-029 says off, and until TASK-79 the app recorded paths
    /// anyway — so this is the case the shipped default was already claiming.
    @Test("Off by default, so a recorded incident holds no executable location")
    func offByDefaultRemovesPaths() {
        let settings = isolatedSettings()
        #expect(!settings.recordFilePaths)
        let monitor = store(settings: settings, policies: PolicyStore())

        let recorded = monitor.recordable(sampleWithPaths)
        #expect(recorded.applications.allSatisfy { $0.bundlePath == nil })
        // The id *is* the path where one exists, so leaving it would keep the
        // location on disk under a different field name.
        #expect(recorded.applications.allSatisfy { !$0.applicationID.hasPrefix("/") })
        #expect(recorded.applications.first?.applicationID == "name:Xcode")
        // Everything that is not a location survives.
        #expect(recorded.applications.first?.displayName == "Xcode")
        #expect(recorded.applications.first?.bundleID == "com.example.xcode")
        #expect(recorded.applications.first?.peakPercentOfOneCore == 220)
        #expect(recorded.totalBusyPercentOfOneCore == 600)
        #expect(recorded.logicalCoreCount == 10)
    }

    /// The control, driven the way a user drives it: change the setting, and what
    /// the monitor records changes.
    @Test("Turning it on records the location again")
    func turningItOnKeepsPaths() {
        let settings = isolatedSettings()
        let monitor = store(settings: settings, policies: PolicyStore())
        #expect(monitor.recordable(sampleWithPaths).applications.first?.bundlePath == nil)

        settings.recordFilePaths = true
        #expect(monitor.recordable(sampleWithPaths).applications.first?.bundlePath
            == "/Applications/Xcode.app")
        #expect(monitor.recordable(sampleWithPaths).applications.first?.applicationID
            == "/Applications/Xcode.app")

        settings.recordFilePaths = false
        #expect(monitor.recordable(sampleWithPaths).applications.first?.bundlePath == nil)
    }

    /// The end effect the setting is about: what is on disk. A field-by-field
    /// assertion would not catch a path that reached the file through some other
    /// key, so this reads the bytes.
    @Test("With paths off, no location appears in the written history")
    func writtenHistoryHoldsNoPath() throws {
        let settings = isolatedSettings()
        let monitor = store(settings: settings, policies: PolicyStore())

        var incident = closedIncident()
        incident.attribution = IncidentAttribution(
            sample: monitor.recordable(sampleWithPaths), at: base)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TASK79-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("incidents.json")

        IncidentHistoryStore(url: url).record(incident, settings: .default, now: base)
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(!written.contains("/Applications/Xcode.app"))
        // Still a usable record: the application is named, only its location is out.
        #expect(written.contains("Xcode"))
    }

    /// Criterion #4 of TASK-79, stated as a test rather than as a claim: the
    /// gathered `PrivacySettings` is what the monitor reads, both halves of it.
    @Test("Both privacy settings reach the monitor through AlertSettings")
    func privacySettingsHasARealReader() {
        let settings = isolatedSettings()
        let monitor = store(settings: settings, policies: PolicyStore())

        settings.recordFilePaths = true
        #expect(monitor.recordable(sampleWithPaths).applications.first?.bundlePath != nil)

        // The retention half, wired by TASK-72 and re-checked here from the app's
        // entry point: an incident older than the chosen period is not retained.
        settings.retention = .sevenDays
        let old = Incident(
            id: UUID(),
            beganAt: base.addingTimeInterval(-60 * 60 * 24 * 30),
            triggeredAt: base.addingTimeInterval(-60 * 60 * 24 * 30),
            recoveryStartedAt: nil,
            closedAt: base.addingTimeInterval(-60 * 60 * 24 * 30),
            conditions: [.memoryPressure],
            severity: .high,
            peakCPUBusyFraction: 0.9,
            peakMemoryPressure: .normal)
        let history = IncidentHistoryStore(url: nil)
        history.record(old, settings: settings.privacySettings, now: base)
        #expect(history.incidents.isEmpty,
                "an incident 30 days old is outside a 7-day retention")
    }
}
