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

/// The file format an automation asks for. Maps one-to-one onto `ReportFormat`;
/// both are renderings of the same document, never a second report.
enum ReportFileFormat: String, AppEnum {
    case plainText
    case json

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Report format")
    static let caseDisplayRepresentations: [ReportFileFormat: DisplayRepresentation] = [
        .plainText: "Plain text",
        .json: "JSON",
    ]

    var format: ReportFormat {
        switch self {
        case .plainText: .plainText
        case .json: .json
        }
    }
}

/// A report produced without anybody watching.
///
/// The interactive sheet shows the document before it leaves; a shortcut cannot,
/// so this states in words what the preview would have shown, and says so out loud
/// when the choices hide less than the app's own default would have. Everything
/// here comes from `IncidentReport.document` — the same object the sheet previews
/// and writes — so redaction cannot differ between the two paths (FR-028).
struct UnattendedIncidentReport {
    let document: ExportDocument
    let format: ReportFormat

    var text: String { String(decoding: document.data(as: format), as: UTF8.self) }
    var byteCount: Int { document.byteCount(as: format) }

    static func make(
        incident: Incident,
        summary: IncidentSummary,
        attribution: CPUAttribution?,
        machine: MachineContext,
        families: [ProcessFamily],
        options: RedactionOptions,
        format: ReportFormat,
        generatedAt: Date = Date()
    ) -> UnattendedIncidentReport {
        UnattendedIncidentReport(
            document: IncidentReport.document(
                incident: incident, machine: machine, summary: summary,
                attribution: attribution,
                contributorPaths: IncidentReport.contributorPaths(in: families),
                sections: .all, options: options, generatedAt: generatedAt),
            format: format)
    }

    /// What a person would have seen in the preview, said instead of shown. The
    /// warning comes first when there is one: an automation that hides less than the
    /// interactive path must not bury that at the end of a sentence about bytes.
    var disclosure: String {
        var parts: [String] = []
        if let warning = document.options.weakerThanDefaultWarning { parts.append(warning) }
        parts.append(document.options.disclosure)
        parts.append("\(document.redactedFieldCount) of \(document.sensitiveFieldCount) "
                     + "sensitive fields hidden, \(byteCount) bytes.")
        parts.append("Nothing was sent anywhere.")
        if let cost = document.costWarning { parts.append(cost) }
        return parts.joined(separator: " ")
    }
}

struct ExportLatestIncidentIntent: AppIntent {
    static let title: LocalizedStringResource = "Export latest MacSlowdown incident"
    static let description = IntentDescription(
        """
        Produces a report for the most recent incident, from the same document the \
        app's export sheet previews. Nothing is sent anywhere; you get the text to \
        share yourself. The result states which fields were hidden, because a \
        shortcut cannot show you the preview.
        """)
    static let openAppWhenRun = false

    // The same three choices the export sheet offers, with the same defaults, so an
    // unattended run is never less redacted than an interactive one unless someone
    // deliberately turns a toggle off — and the result says so when they have.
    // AppIntents requires literal defaults, so these cannot reference
    // `RedactionOptions.default` directly. `declaredDefaults` below restates them as
    // a value, and a test asserts the two are equal — otherwise a change to the
    // app's default redaction could silently leave the automation behind.
    @Parameter(title: "Hide my user name", default: true)
    var hideUserName: Bool

    @Parameter(title: "Hide file paths", default: true)
    var hideFilePaths: Bool

    @Parameter(title: "Hide app and process names", default: false)
    var hideProcessNames: Bool

    static let declaredDefaults = RedactionOptions(
        hideUserName: true, hideFilePaths: true, hideProcessNames: false)

    @Parameter(title: "Format", default: .plainText)
    var format: ReportFileFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export the latest incident as \(\.$format)") {
            \.$hideUserName
            \.$hideFilePaths
            \.$hideProcessNames
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = MonitorStore.shared
        guard let incident = store.openIncident ?? store.recentIncidents.first else {
            let message = "There are no recorded incidents to export."
            return .result(value: message, dialog: IntentDialog("\(message)"))
        }

        let report = UnattendedIncidentReport.make(
            incident: incident,
            summary: IncidentSummarizer.summarize(
                incident: incident, attribution: store.attribution),
            attribution: store.attribution,
            machine: store.machine,
            families: store.families,
            options: RedactionOptions(hideUserName: hideUserName,
                                      hideFilePaths: hideFilePaths,
                                      hideProcessNames: hideProcessNames),
            format: format.format)

        return .result(value: report.text, dialog: IntentDialog("\(report.disclosure)"))
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
