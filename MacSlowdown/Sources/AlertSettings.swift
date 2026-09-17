import Foundation
import Metrics
import Observation

/// How eagerly MacSlowdown interrupts (FR-006, FR-014).
///
/// The design's point is that an ordinary user chooses a word, not a number: the
/// three cases below are the *only* thing most people ever touch, and each one
/// stands for a complete `IncidentPolicy`. The exact figures stay reachable
/// behind a disclosure so nothing is hidden — but nobody has to decode them to
/// make a sensible choice.
enum AlertSensitivity: String, CaseIterable, Identifiable, Sendable {
    case relaxed
    case balanced
    case sensitive

    var id: String { rawValue }

    /// The next step towards fewer interruptions, or nil at the quiet end.
    ///
    /// **One dial, reached from more places.** TASK-108's finding was that the
    /// control the product owner asked for already existed and nobody could find
    /// it — two weeks of use, the exact problem it solves, and a request to build
    /// it. Adding a second control would have made that worse, so this is how the
    /// banner's "Alert me less" moves the existing setting rather than introducing
    /// a rival one (FR-060).
    var quieter: AlertSensitivity? {
        switch self {
        case .sensitive: .balanced
        case .balanced: .relaxed
        case .relaxed: nil
        }
    }

    var label: String {
        switch self {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .sensitive: "Sensitive"
        }
    }

    /// The thresholds this word stands for.
    ///
    /// `balanced` is deliberately `IncidentPolicy.default` rather than a second
    /// copy of the same numbers: the shipped defaults and the middle choice must
    /// not be able to drift apart.
    var policy: IncidentPolicy {
        switch self {
        case .relaxed:
            IncidentPolicy(
                cpuBusyFractionThreshold: 0.92,
                cpuSustainedDuration: .seconds(300),
                memoryPressureSustainedDuration: .seconds(180))
        case .balanced:
            .default
        case .sensitive:
            IncidentPolicy(
                cpuBusyFractionThreshold: 0.75,
                cpuSustainedDuration: .seconds(60),
                memoryPressureSustainedDuration: .seconds(45))
        }
    }

    /// Incidents quieter than this are recorded but never announced. Recording is
    /// unaffected by all three choices — sensitivity changes interruption only.
    var minimumSeverity: IncidentSeverity {
        switch self {
        case .relaxed: .severe
        case .balanced: .high
        case .sensitive: .moderate
        }
    }

    /// The behaviour, restated in words. Derived from `policy` rather than
    /// written out, so the sentence cannot contradict the thresholds it describes.
    ///
    /// **It says that the choice moves the detection threshold** (TASK-111
    /// criterion 4, design 5g). The three options were described as changing which
    /// severities announce, and they do — but they also move the CPU line, 92% /
    /// 85% / 75%, so "Tell me early" changes what *counts* as a condition and not
    /// merely what is said about one. A restatement that mentioned only the second
    /// half understated the control: someone choosing it to hear more would also,
    /// unannounced, have changed what their history records.
    var restatement: String {
        "\(label): a condition starts once total CPU stays above "
            + "\(AlertSettings.spellCPU(fraction: policy.cpuBusyFractionThreshold)) "
            + "for \(AlertSettings.spell(policy.cpuSustainedDuration)), and you hear "
            + "about the ones rated \(minimumSeverity.label.lowercased()) or worse. "
            + AlertSensitivity.thresholdCaveat
    }

    /// The half of the restatement that is the same whichever option is chosen, and
    /// the half that was missing. Separated so a test can assert it is present
    /// without repeating the whole sentence for all three options.
    static let thresholdCaveat =
        "This moves the line itself, not just what gets said about it — a lower "
        + "line records more conditions and shows more of them in the overview."
}

/// Alert and privacy preferences, persisted in `UserDefaults`.
///
/// **What this does not do.** It does not apply anything itself. The monitoring
/// loop owns the `IncidentDetector` and the `NotificationGate` and reads these
/// values on each sample (`MonitorStore.applyAlertSettings`), which is what sets
/// `isAppliedToMonitoring`. Until monitoring is running they are a saved
/// preference and nothing more, and the interface says so rather than implying a
/// control took effect (FR-002's rule against presenting something we have not
/// measured, applied to our own behaviour).
@MainActor
@Observable
final class AlertSettings {
    static let shared = AlertSettings()

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let chosen = (defaults.string(forKey: Key.sensitivity)
            .flatMap(AlertSensitivity.init(rawValue:))) ?? .balanced
        let chosenPolicy = chosen.policy
        announceIncidents = defaults.object(forKey: Key.announce) as? Bool ?? true
        sensitivity = chosen
        deferDuringAudio = defaults.object(forKey: Key.deferDuringAudio) as? Bool ?? true
        usesCustomThresholds = defaults.bool(forKey: Key.customThresholds)
        cpuBusyFractionThreshold = defaults.object(forKey: Key.cpuFraction) as? Double
            ?? chosenPolicy.cpuBusyFractionThreshold
        cpuSustainedSeconds = defaults.object(forKey: Key.cpuSeconds) as? Double
            ?? chosenPolicy.cpuSustainedDuration.totalSeconds
        memorySustainedSeconds = defaults.object(forKey: Key.memorySeconds) as? Double
            ?? chosenPolicy.memoryPressureSustainedDuration.totalSeconds
        conditionOverrides = (defaults.dictionary(forKey: Key.conditionOverrides)
            as? [String: Bool]) ?? [:]
        recordFilePaths = defaults.bool(forKey: Key.recordFilePaths)
        retention = (defaults.string(forKey: Key.retention)
            .flatMap(PrivacySettings.Retention.init(rawValue:))) ?? PrivacySettings.default.retention
    }

    private enum Key {
        static let announce = "alerts.announceIncidents"
        static let sensitivity = "alerts.sensitivity"
        static let deferDuringAudio = "alerts.deferDuringAudio"
        static let customThresholds = "alerts.usesCustomThresholds"
        static let cpuFraction = "alerts.cpuBusyFractionThreshold"
        static let cpuSeconds = "alerts.cpuSustainedSeconds"
        static let memorySeconds = "alerts.memorySustainedSeconds"
        static let conditionOverrides = "alerts.conditionInterrupts"
        static let recordFilePaths = "privacy.recordFilePaths"
        static let retention = "privacy.retention"
    }

    // MARK: - Alerts

    var announceIncidents: Bool {
        didSet { defaults.set(announceIncidents, forKey: Key.announce) }
    }

    var sensitivity: AlertSensitivity {
        didSet {
            defaults.set(sensitivity.rawValue, forKey: Key.sensitivity)
            // Changing the plain-language choice re-seeds the exact figures, so
            // the disclosure always shows what the chosen word actually means.
            guard !usesCustomThresholds else { return }
            cpuBusyFractionThreshold = sensitivity.policy.cpuBusyFractionThreshold
            cpuSustainedSeconds = sensitivity.policy.cpuSustainedDuration.totalSeconds
            memorySustainedSeconds =
                sensitivity.policy.memoryPressureSustainedDuration.totalSeconds
        }
    }

    /// FR-019. The audio signal behind it is real and already sampled by the
    /// monitoring loop — see `AudioSignals`, measured available under the sandbox.
    var deferDuringAudio: Bool {
        didSet { defaults.set(deferDuringAudio, forKey: Key.deferDuringAudio) }
    }

    /// Which conditions the user has decided about, keyed by raw value (design
    /// 5g's switches).
    ///
    /// **A dictionary rather than a "these interrupt" set**, because a condition
    /// the user has never had an opinion about is a third state, not an off. A set
    /// would freeze today's `announcesByDefault` answers into every installation
    /// the moment anyone opened this screen, and a later change to a default would
    /// silently fail to reach them.
    private var conditionOverrides: [String: Bool] {
        didSet { defaults.set(conditionOverrides, forKey: Key.conditionOverrides) }
    }

    /// Whether one condition may interrupt: the user's switch if they set one, our
    /// default otherwise.
    func interrupts(_ condition: IncidentCondition) -> Bool {
        conditionOverrides[condition.rawValue] ?? condition.announcesByDefault
    }

    /// Whether the user has decided about this condition, as opposed to leaving it
    /// at our default. Shown rather than hidden: a screen that cannot distinguish
    /// the two cannot offer to put one back.
    func hasDecided(about condition: IncidentCondition) -> Bool {
        conditionOverrides[condition.rawValue] != nil
    }

    func setInterrupts(_ condition: IncidentCondition, _ interrupts: Bool) {
        conditionOverrides[condition.rawValue] = interrupts
    }

    /// Whether the exact figures have been edited away from the chosen word.
    var usesCustomThresholds: Bool {
        didSet { defaults.set(usesCustomThresholds, forKey: Key.customThresholds) }
    }

    var cpuBusyFractionThreshold: Double {
        didSet { defaults.set(cpuBusyFractionThreshold, forKey: Key.cpuFraction) }
    }

    var cpuSustainedSeconds: Double {
        didSet { defaults.set(cpuSustainedSeconds, forKey: Key.cpuSeconds) }
    }

    var memorySustainedSeconds: Double {
        didSet { defaults.set(memorySustainedSeconds, forKey: Key.memorySeconds) }
    }

    /// The memory-pressure *level* that counts as a breach is not a setting.
    /// `SystemObservation.breaches` treats warning-or-above as the condition, and
    /// there is no code path that reads any other floor — so offering a picker
    /// here would be a control that silently does nothing.
    let memoryPressureFloor: MemoryPressureLevel = .warning

    /// Resets the exact figures back to the chosen word.
    func useThresholdsFromSensitivity() {
        usesCustomThresholds = false
        cpuBusyFractionThreshold = sensitivity.policy.cpuBusyFractionThreshold
        cpuSustainedSeconds = sensitivity.policy.cpuSustainedDuration.totalSeconds
        memorySustainedSeconds = sensitivity.policy.memoryPressureSustainedDuration.totalSeconds
    }

    // MARK: - Privacy

    /// FR-029: off by default, and an explicit opt-in when it is on.
    ///
    /// Read by `MonitorStore.recordable(_:)`, which is what makes it a control
    /// rather than a stored value (TASK-79). It governs what is *kept* — the
    /// executable location written into an incident record — not whether paths are
    /// resolved, which grouping and icons depend on and which no setting can turn
    /// off without breaking them.
    var recordFilePaths: Bool {
        didSet { defaults.set(recordFilePaths, forKey: Key.recordFilePaths) }
    }

    var retention: PrivacySettings.Retention {
        didSet { defaults.set(retention.rawValue, forKey: Key.retention) }
    }

    // MARK: - What the monitoring loop would consume

    /// The detector policy these settings describe.
    var incidentPolicy: IncidentPolicy {
        var policy = sensitivity.policy
        guard usesCustomThresholds else { return policy }
        policy.cpuBusyFractionThreshold = cpuBusyFractionThreshold
        policy.cpuSustainedDuration = .seconds(cpuSustainedSeconds)
        policy.memoryPressureSustainedDuration = .seconds(memorySustainedSeconds)
        return policy
    }

    /// The notification gate settings these describe.
    ///
    /// `respectFocus` stays on and is not a control: no public API reports the
    /// current Focus to a sandboxed app, so our own gate can never see it — macOS
    /// holds the banner instead. A toggle would claim a decision we do not make.
    var notificationSettings: NotificationSettings {
        var settings = NotificationSettings(
            // Both, not either. The floor is what the chosen word means; the switch
            // is whether anything is announced at all. Raising the floor alone still
            // announced severe incidents to someone who turned alerts off.
            announcesIncidents: announceIncidents,
            minimumSeverity: announceIncidents ? sensitivity.minimumSeverity : .severe,
            respectFocus: true,
            deferDuringAudio: deferDuringAudio,
            // One rule per application *and* condition (FR-016 amendment 1). A
            // policy carrying two conditions becomes two rules rather than one
            // wildcard, so what the gate evaluates is exactly what the Rules list
            // shows, row for row.
            rules: MonitorStore.shared.policies.policies
                .filter { $0.classification.suppressesNotification }
                .flatMap { policy in
                    policy.conditions.map {
                        SuppressionRule(application: policy.displayName, condition: $0)
                    }
                })
        settings.announcedConditions = decided(interrupting: true)
        settings.silencedConditions = decided(interrupting: false)
        // Read here rather than stored, so ending the session takes effect on the
        // next sample without anything having to remember to push it.
        settings.sessionQuiet = SessionQuiet.shared.isActive
        return settings
    }

    private func decided(interrupting: Bool) -> Set<IncidentCondition> {
        Set(conditionOverrides
            .filter { $0.value == interrupting }
            .keys.compactMap(IncidentCondition.init(rawValue:)))
    }

    /// The privacy settings these describe.
    ///
    /// Read by `MonitorStore.privacySettings`, which applies the retention period
    /// to stored incidents on every write and on every sample (TASK-72) and decides
    /// whether an executable location is recorded (TASK-79). Nothing here is a
    /// stored value with no reader.
    ///
    /// `persistAcrossRestarts` is left at the type's own default and is **not**
    /// surfaced as a control: the product decision is that history persists, and the
    /// Privacy tab states that rather than offering a switch whose off position
    /// would silently throw recorded evidence away.
    var privacySettings: PrivacySettings {
        PrivacySettings(
            retention: retention,
            persistAcrossRestarts: PrivacySettings.default.persistAcrossRestarts,
            recordFilePaths: recordFilePaths)
    }

    /// Set by whatever consumes the values above — `MonitorStore` does, when it
    /// starts monitoring and on every sample thereafter. The interface says
    /// "saved, not yet in effect" until then, and stops saying it without a copy
    /// change the moment the monitoring loop calls this (TASK-69).
    private(set) var isAppliedToMonitoring = false

    func markAppliedToMonitoring() { isAppliedToMonitoring = true }

    // MARK: - Wording

    /// Durations are spelled the same way incident detail spells them, so the
    /// threshold a user sets and the duration a report quotes read alike.
    nonisolated static func spell(_ duration: Duration) -> String {
        DateComponentsFormatter.incidentDuration.string(from: duration.totalSeconds)
            ?? "\(Int(duration.totalSeconds)) seconds"
    }

    /// CPU thresholds are machine-relative everywhere, matching the incident
    /// summary's "% of this Mac's capacity" (FR-004).
    nonisolated static func spellCPU(fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))% of this Mac's capacity"
    }
}
