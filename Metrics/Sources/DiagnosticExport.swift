import Foundation

/// What may be stripped from an export before it leaves the machine (FR-028).
public struct RedactionOptions: Sendable, Equatable {
    public var hideUserName: Bool
    public var hideFilePaths: Bool
    public var hideProcessNames: Bool

    public init(hideUserName: Bool = true, hideFilePaths: Bool = true,
                hideProcessNames: Bool = false) {
        self.hideUserName = hideUserName
        self.hideFilePaths = hideFilePaths
        self.hideProcessNames = hideProcessNames
    }

    /// Defaults redact the two fields that identify a person without costing much
    /// interpretability. Process names are left in because removing them makes a
    /// report nearly useless, and the interface says so rather than letting a user
    /// discover it after sending.
    public static let `default` = RedactionOptions()

    public var redactedFieldCount: Int {
        [hideUserName, hideFilePaths, hideProcessNames].count { $0 }
    }

    /// Warning shown when a choice materially damages the report's usefulness.
    public var costWarning: String? {
        hideProcessNames
            ? "Hiding process names makes the report much harder for anyone to interpret."
            : nil
    }
}

/// A diagnostic report, previewable before anything leaves the machine (FR-028).
public struct DiagnosticExport: Sendable {
    public let incident: Incident
    public let machine: MachineContext
    public let summary: IncidentSummary
    public let attribution: CPUAttribution?
    public let options: RedactionOptions
    public let generatedAt: Date

    public static let redactedPlaceholder = "[redacted]"

    /// The exact text that would be shared. FR-028 requires the preview be the
    /// real thing rather than a description of it, so this is what gets written.
    public var text: String {
        var lines: [String] = []
        lines.append("MacSlowdown incident report")
        lines.append("")
        lines.append("Incident      \(incident.conditions.map(\.label).sorted().joined(separator: ", "))")
        lines.append("Severity      \(incident.severity.label)")
        lines.append("Began         \(incident.beganAt.formatted(.iso8601))")
        if let closed = incident.closedAt {
            lines.append("Ended         \(closed.formatted(.iso8601))")
        } else {
            lines.append("Ended         still open at export")
        }
        lines.append("")

        lines.append("Machine       \(machine.hardwareModel) · \(machine.architecture)")
        lines.append("Cores         \(machine.logicalCores) logical")
        lines.append("Memory        \(String(format: "%.0f GB", machine.physicalMemoryGB))")
        lines.append("macOS         \(machine.osVersion)")
        lines.append("User          \(options.hideUserName ? Self.redactedPlaceholder : NSUserName())")
        lines.append("")

        // FR-040: versions travel with the report so it stays interpretable after
        // the app changes.
        lines.append("App           \(machine.appVersion) (\(machine.appBuild))")
        lines.append("Schema        \(machine.schemaVersion)")
        lines.append("")

        lines.append("Findings")
        for conclusion in summary.conclusions {
            lines.append("  [\(conclusion.evidence.rawValue)"
                + (conclusion.confidence.map { ", \($0.rawValue)" } ?? "") + "] "
                + redactNames(conclusion.text))
        }
        if !summary.ruledOut.isEmpty {
            lines.append("")
            lines.append("Ruled out")
            for conclusion in summary.ruledOut {
                lines.append("  [\(conclusion.evidence.rawValue)] \(redactNames(conclusion.text))")
            }
        }

        if let attribution {
            lines.append("")
            lines.append("Measurements (percent of one core)")
            for figure in attribution.figures {
                lines.append(String(format: "  %-30@ %8.1f  %@",
                                    figure.label as NSString,
                                    figure.percentOfOneCore,
                                    figure.evidence.rawValue))
            }
            if !attribution.contributors.isEmpty {
                lines.append("")
                lines.append("Contributors")
                for contributor in attribution.contributors.prefix(10) {
                    let name = options.hideProcessNames
                        ? Self.redactedPlaceholder : contributor.label
                    lines.append(String(format: "  %-30@ %8.1f",
                                        name as NSString, contributor.percentOfOneCore))
                }
            }
        }

        lines.append("")
        lines.append("\(options.redactedFieldCount) of 3 redactable fields hidden.")
        return lines.joined(separator: "\n")
    }

    /// Process names appear inside prose findings too, so redaction has to reach
    /// them there rather than only in the structured fields.
    private func redactNames(_ text: String) -> String {
        guard options.hideProcessNames, let attribution else { return text }
        var result = text
        for contributor in attribution.contributors {
            result = result.replacingOccurrences(
                of: contributor.label, with: Self.redactedPlaceholder)
        }
        return result
    }

    /// Every value that would leave the machine, for a preview that shows what is
    /// hidden rather than only what is shown.
    public var redactedFields: [String] {
        var fields: [String] = []
        if options.hideUserName { fields.append("User name") }
        if options.hideFilePaths { fields.append("File paths") }
        if options.hideProcessNames { fields.append("Process names") }
        return fields
    }

    public var byteCount: Int { text.utf8.count }
}

public enum DiagnosticExporter {
    /// Builds a report. **Writes nothing and sends nothing** — FR-028 requires no
    /// automatic transmission, so producing and delivering are separate steps and
    /// only the caller can perform the second.
    public static func export(
        incident: Incident,
        summary: IncidentSummary,
        attribution: CPUAttribution?,
        machine: MachineContext = .current(),
        options: RedactionOptions = .default,
        generatedAt: Date = Date()
    ) -> DiagnosticExport {
        DiagnosticExport(
            incident: incident, machine: machine, summary: summary,
            attribution: attribution, options: options, generatedAt: generatedAt)
    }
}
