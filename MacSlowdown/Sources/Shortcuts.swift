import AppIntents
import Foundation
import Metrics

/// Automation for safe operations (FR-035).
///
/// Deliberately limited to the same set the interface offers: show status, mute
/// alerts, export the latest incident. There is no process-control intent,
/// because there is no process control — an automation surface that exposed more
/// than the UI would be a way around the constraint rather than an extension of
/// the product.
///
/// Every intent returns structured success or failure rather than throwing an
/// opaque error, and states what it could not do when it cannot act.
enum ShortcutsVersion {
    /// Bumped when an intent's parameters or meaning change, so an existing
    /// shortcut keeps working or fails loudly rather than quietly doing something
    /// different (FR-035: commands are versioned).
    static let current = 1
}

struct ShowStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Show MacSlowdown status"
    static let description = IntentDescription(
        "Reports the current condition, total CPU, and how much of it can be attributed.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = MonitorStore.shared
        guard let attribution = store.attribution else {
            let message = store.isRunning
                ? "MacSlowdown is starting up and has not taken a full reading yet."
                : "MacSlowdown is not monitoring right now."
            return .result(value: message, dialog: IntentDialog("\(message)"))
        }

        // Reports the unattributed share too: a status that named only what we can
        // see would overstate how much we know (FR-055).
        let summary = """
            \(store.severity.label). Total CPU \
            \(CPUPresentation.percentOfOneCore(attribution.totalBusyPercentOfOneCore)) of one \
            core, of which \
            \(CPUPresentation.percentOfOneCore(attribution.unattributedPercentOfOneCore)) \
            could not be attributed to any process we are permitted to measure.
            """
        return .result(value: summary, dialog: IntentDialog("\(summary)"))
    }
}

struct MuteAlertsIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute MacSlowdown alerts"
    static let description = IntentDescription(
        "Stops alerts for a period. Monitoring keeps running, so the history is intact when the mute expires.")
    static let openAppWhenRun = false

    @Parameter(title: "Minutes", default: 60)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard minutes > 0 else {
            // Structured failure rather than a thrown error, so a shortcut can
            // branch on it.
            return .result(dialog: IntentDialog("Muting needs a positive number of minutes."))
        }
        MonitorStore.shared.mute(forMinutes: minutes)
        return .result(dialog: IntentDialog("Alerts muted for \(minutes) minutes. Monitoring is still running."))
    }
}

struct ExportLatestIncidentIntent: AppIntent {
    static let title: LocalizedStringResource = "Export latest MacSlowdown incident"
    static let description = IntentDescription(
        "Produces a redacted report for the most recent incident. Nothing is sent anywhere; you get the text to share yourself.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = MonitorStore.shared
        guard let incident = store.openIncident ?? store.recentIncidents.first else {
            let message = "There are no recorded incidents to export."
            return .result(value: message, dialog: IntentDialog("\(message)"))
        }

        let summary = IncidentSummarizer.summarize(
            incident: incident, attribution: store.attribution)
        let report = DiagnosticExporter.export(
            incident: incident, summary: summary, attribution: store.attribution,
            machine: store.machine, options: .default)

        return .result(
            value: report.text,
            dialog: IntentDialog("Exported a \(report.byteCount)-byte report with \(report.options.redactedFieldCount) fields redacted. Nothing was sent."))
    }
}

struct MacSlowdownShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowStatusIntent(),
            phrases: ["What is \(.applicationName) showing?"],
            shortTitle: "Show status",
            systemImageName: "gauge.with.dots.needle.33percent")
        AppShortcut(
            intent: MuteAlertsIntent(),
            phrases: ["Mute \(.applicationName)"],
            shortTitle: "Mute alerts",
            systemImageName: "bell.slash")
        AppShortcut(
            intent: ExportLatestIncidentIntent(),
            phrases: ["Export the latest \(.applicationName) incident"],
            shortTitle: "Export latest incident",
            systemImageName: "square.and.arrow.up")
    }
}
