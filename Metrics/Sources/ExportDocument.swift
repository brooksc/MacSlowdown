import Foundation

// MARK: - Choices

/// Which optional sections a report carries (FR-028, design 1k "Include").
public struct ReportSections: Sendable, Equatable {
    public var measurements: Bool
    public var machineDetails: Bool
    public var timeline: Bool

    public init(measurements: Bool = true, machineDetails: Bool = true, timeline: Bool = true) {
        self.measurements = measurements
        self.machineDetails = machineDetails
        self.timeline = timeline
    }

    public static let all = ReportSections()
}

/// The file formats a report can be written as.
///
/// Only formats the framework genuinely renders from the document are offered. The
/// design shows "PDF and JSON"; PDF is deliberately absent — see
/// `ReportFormat.unofferedFormatsExplanation`.
public enum ReportFormat: String, Sendable, CaseIterable, Codable, Identifiable {
    case plainText
    case json

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .plainText: "Plain text (.txt)"
        case .json: "JSON (.json)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .json: "json"
        }
    }

    /// Stated in the interface rather than left as a silent omission: a format we
    /// cannot render from the same document as the preview could disagree with the
    /// preview, which is the one failure FR-028 exists to prevent.
    public static let unofferedFormatsExplanation =
        "Both formats are written from exactly what the preview shows."
}

// MARK: - Document model

/// One value in a report.
///
/// A redacted value carries no text. Redaction happens when the document is
/// **built**, not when it is rendered, so a hidden value is absent from the
/// document itself and cannot reach a file by any path. The preview and the file
/// are two renderings of this one object.
public enum ReportValue: Sendable, Equatable {
    case text(String)
    /// Hidden at the user's request. The value is not held.
    case redacted
    /// Never available to us in the first place. Not the same as redacted, and
    /// never counted as one (FR-002: unavailable is labelled, not approximated).
    case unavailable(String)
}

public struct ReportField: Sendable, Equatable {
    public let label: String
    public let value: ReportValue
    /// Whether this field could identify the person or their files, and so counts
    /// towards "n of m sensitive fields redacted".
    public let isSensitive: Bool

    public init(_ label: String, _ value: ReportValue, sensitive: Bool = false) {
        self.label = label
        self.value = value
        self.isSensitive = sensitive
    }

    public var isRedacted: Bool { value == .redacted }
}

public enum ReportRow: Sendable, Equatable {
    case field(ReportField)
    case prose(String)
}

public struct ReportSection: Sendable, Equatable {
    public let title: String?
    public let rows: [ReportRow]

    public init(title: String?, rows: [ReportRow]) {
        self.title = title
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }
}

/// A report, ready to preview and ready to write — the same object for both.
public struct ExportDocument: Sendable, Equatable {
    public let title: String
    public let generatedAt: Date
    public let sections: [ReportSection]
    public let options: RedactionOptions
    public let included: ReportSections

    public var fields: [ReportField] {
        sections.flatMap(\.rows).compactMap {
            if case .field(let field) = $0 { return field }
            return nil
        }
    }

    /// The denominator in the status line: sensitive fields actually present in
    /// this report, not a fixed guess. A path we never recorded is not a field the
    /// user can be told they redacted.
    public var sensitiveFieldCount: Int { fields.count { $0.isSensitive } }
    public var redactedFieldCount: Int { fields.count { $0.isSensitive && $0.isRedacted } }

    public func byteCount(as format: ReportFormat) -> Int { data(as: format).count }

    /// "2 of 6 sensitive fields hidden · 4 KB" (design 1k).
    public func statusLine(for format: ReportFormat) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(byteCount(as: format)), countStyle: .file)
        return "\(redactedFieldCount) of \(sensitiveFieldCount) sensitive fields hidden · \(size)"
    }

    /// The cost of the current choices, stated before sending rather than
    /// discovered after. Over-redaction is allowed; it is not silent.
    public var costWarning: String? { options.costWarning }

    // MARK: Renderings

    public static let redactedPlaceholder = "[redacted]"

    public var plainText: String {
        var lines: [String] = [title, String(repeating: "=", count: title.count), ""]
        for section in sections where !section.isEmpty {
            if let heading = section.title {
                lines.append(heading)
            }
            for row in section.rows {
                switch row {
                case .field(let field):
                    lines.append(String(format: "  %@%@",
                                        field.label.padding(toLength: max(30, field.label.count + 2),
                                                            withPad: " ", startingAt: 0),
                                        Self.rendered(field.value)))
                case .prose(let text):
                    lines.append("  \(text)")
                }
            }
            lines.append("")
        }
        lines.append("\(redactedFieldCount) of \(sensitiveFieldCount) sensitive fields hidden "
                     + "at the request of the person who exported this report.")
        return lines.joined(separator: "\n")
    }

    public var json: String {
        let encoder = JSONEncoder()
        // `.withoutEscapingSlashes` matters for more than legibility: without it a
        // path is written as `\/Users\/…`, so a check that the raw path is absent
        // would pass while the path was in fact present. Redaction has to be
        // verifiable by reading the file.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(JSONDocument(self)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public func data(as format: ReportFormat) -> Data {
        switch format {
        case .plainText: Data(plainText.utf8)
        case .json: Data(json.utf8)
        }
    }

    static func rendered(_ value: ReportValue) -> String {
        switch value {
        case .text(let text): text
        case .redacted: redactedPlaceholder
        case .unavailable(let reason): "not available — \(reason)"
        }
    }
}

// MARK: - JSON shape

/// The JSON rendering. A redacted field carries `"redacted": true` and **no**
/// value key, so the omission is machine-readable and the value is not present.
private struct JSONDocument: Encodable {
    struct Field: Encodable {
        let label: String
        let value: String?
        let redacted: Bool
        let unavailable: String?
        let sensitive: Bool
    }
    struct Section: Encodable {
        let title: String?
        let fields: [Field]
        let notes: [String]
    }

    let title: String
    let generatedAt: Date
    let sensitiveFieldCount: Int
    let redactedFieldCount: Int
    let sections: [Section]

    init(_ document: ExportDocument) {
        title = document.title
        generatedAt = document.generatedAt
        sensitiveFieldCount = document.sensitiveFieldCount
        redactedFieldCount = document.redactedFieldCount
        sections = document.sections.map { section in
            var fields: [Field] = []
            var notes: [String] = []
            for row in section.rows {
                switch row {
                case .field(let field):
                    switch field.value {
                    case .text(let text):
                        fields.append(Field(label: field.label, value: text, redacted: false,
                                            unavailable: nil, sensitive: field.isSensitive))
                    case .redacted:
                        fields.append(Field(label: field.label, value: nil, redacted: true,
                                            unavailable: nil, sensitive: field.isSensitive))
                    case .unavailable(let reason):
                        fields.append(Field(label: field.label, value: nil, redacted: false,
                                            unavailable: reason, sensitive: field.isSensitive))
                    }
                case .prose(let text):
                    notes.append(text)
                }
            }
            return Section(title: section.title, fields: fields, notes: notes)
        }
    }
}

// MARK: - Builder

public enum IncidentReport {
    public static let title = "MacSlowdown incident report"

    /// Executable paths for the processes a report can name, taken from the same
    /// grouping the app shows.
    ///
    /// Lives here rather than in a view so that every path producing a report feeds
    /// the redactor the same map. If one caller supplied paths and another did not,
    /// the "File paths" choice would mean different things in two reports of the
    /// same incident — a quieter version of the divergence FR-028 forbids.
    public static func contributorPaths(
        in families: [ProcessFamily]
    ) -> [ProcessIdentity: String] {
        var paths: [ProcessIdentity: String] = [:]
        for family in families {
            for member in family.members {
                if let path = member.resolved.executablePath {
                    paths[member.record.identity] = path
                }
            }
        }
        return paths
    }

    /// Builds the document that both the preview and the saved file are rendered
    /// from (FR-028). Writes nothing and sends nothing — only the caller can
    /// deliver it (FR-029).
    ///
    /// - Parameter contributorPaths: executable paths for contributors, where the
    ///   app recorded them. Absent by default, because `PrivacySettings`
    ///   deliberately does not record paths unless asked.
    public static func document(
        incident: Incident,
        machine: MachineContext,
        summary: IncidentSummary,
        attribution: CPUAttribution?,
        contributorPaths: [ProcessIdentity: String] = [:],
        sections included: ReportSections = .all,
        options: RedactionOptions = .default,
        generatedAt: Date = Date()
    ) -> ExportDocument {
        let redactor = Redactor(
            options: options, attribution: attribution, paths: contributorPaths,
            // What the incident itself recorded, which is what the prose is built
            // from for any incident that is not still running.
            additionalNames: (incident.attribution?.applications.map(\.displayName) ?? [])
                + incident.lifecycleFindings.map(\.command))
        var sections: [ReportSection] = []

        sections.append(ReportSection(title: nil, rows: [
            .field(ReportField("Incident",
                               .text(incident.conditions.map(\.label).sorted()
                                   .joined(separator: ", ")))),
            .field(ReportField("Severity", .text(incident.severity.label))),
            .field(ReportField("When", .text(window(incident)))),
        ]))

        if included.machineDetails {
            sections.append(ReportSection(title: "Machine", rows: [
                .field(ReportField("Model", .text(machine.hardwareModel))),
                .field(ReportField("Architecture", .text(machine.architecture))),
                .field(ReportField("Cores", .text("\(machine.logicalCores) logical"))),
                .field(ReportField("Memory",
                                   .text(String(format: "%.0f GB", machine.physicalMemoryGB)))),
                .field(ReportField("macOS", .text(machine.osVersion))),
                .field(ReportField("User", redactor.userName(), sensitive: true)),
            ]))
        }

        if included.measurements {
            sections.append(measurementSection(
                incident: incident, attribution: attribution, redactor: redactor))
        }

        if included.timeline {
            sections.append(timelineSection(incident))
        }

        sections.append(summarySection(summary, redactor: redactor))

        // FR-040: versions travel with the report so it stays interpretable after
        // the app changes. Never optional — a report without them cannot be read.
        sections.append(ReportSection(title: "About this report", rows: [
            .field(ReportField("App", .text("\(machine.appVersion) (\(machine.appBuild))"))),
            .field(ReportField("Schema", .text("\(machine.schemaVersion)"))),
            .field(ReportField("Generated", .text(generatedAt.formatted(.iso8601)))),
            .prose("Produced on this Mac and never uploaded. Whoever exported it chose "
                   + "what to include and sent the file themselves."),
        ]))

        return ExportDocument(title: title, generatedAt: generatedAt, sections: sections,
                              options: options, included: included)
    }

    /// The incident's measurements.
    ///
    /// **The incident's own recording wins over live state**, which is the rule
    /// `IncidentDetailView.evidenceFigures` already followed on screen and this
    /// function did not. It consulted only the live attribution, so exporting a
    /// closed incident produced a "Measurements" section listing whatever happened
    /// to be busy at the moment the user pressed Export — under that incident's
    /// heading, with per-contributor percentages and paths. The screen behind the
    /// button and the file that left it stated different contributors for the same
    /// incident, and the file was the wrong one (FR-002, FR-028).
    ///
    /// Live state is used only while the incident is still open and has recorded
    /// nothing of its own.
    private static func measurementSection(
        incident: Incident, attribution: CPUAttribution?, redactor: Redactor
    ) -> ReportSection {
        var rows: [ReportRow] = [
            .field(ReportField("Peak CPU",
                               .text("\(Int((incident.peakCPUBusyFraction * 100).rounded()))% "
                                     + "of this Mac's capacity"))),
            .field(ReportField("Peak memory pressure",
                               .text(incident.peakMemoryPressure.label))),
        ]

        if let recorded = incident.attribution {
            return recordedMeasurementSection(recorded, rows: rows, redactor: redactor)
        }

        guard let attribution, incident.isOpen else {
            rows.append(.prose("Per-process measurements were not retained for this incident."))
            return ReportSection(title: "Measurements", rows: rows)
        }

        for figure in attribution.figures {
            rows.append(.field(ReportField(
                figure.label,
                .text(String(format: "%.1f%% of one core (%@)",
                             figure.percentOfOneCore, figure.evidence.rawValue)))))
        }

        for contributor in attribution.contributors.prefix(5) {
            rows.append(.field(ReportField(
                "Contributor",
                redactor.processName(contributor.label,
                                     detail: String(format: "%.1f%% of one core",
                                                    contributor.percentOfOneCore)),
                sensitive: true)))
            rows.append(.field(ReportField(
                "Path", redactor.path(for: contributor.identity), sensitive: true)))
        }

        rows.append(.prose(redactor.prose(attribution.explanation)))
        return ReportSection(title: "Measurements", rows: rows)
    }

    /// The same section built from what the incident recorded at its busiest
    /// moment, rather than from the machine as it is now.
    private static func recordedMeasurementSection(
        _ recorded: IncidentAttribution, rows: [ReportRow], redactor: Redactor
    ) -> ReportSection {
        var rows = rows
        for figure in recorded.figures {
            rows.append(.field(ReportField(
                figure.label,
                .text(String(format: "%.1f%% of one core (%@)",
                             figure.percentOfOneCore, figure.evidence.rawValue)))))
        }

        for contributor in recorded.applications.prefix(5) {
            rows.append(.field(ReportField(
                "Contributor",
                redactor.processName(contributor.displayName,
                                     detail: String(format: "%.1f%% of one core at its peak",
                                                    contributor.peakPercentOfOneCore)),
                sensitive: true)))
            // A recorded contributor carries no `(pid, start time)` — by design, so
            // that a family survives PID replacement — so there is no per-process
            // path to look up. `applicationID` is the bundle path where the
            // application had one, and that is a path the user can be asked about;
            // where it is a display name instead, say the path was not recorded
            // rather than presenting a name as one.
            rows.append(.field(ReportField(
                "Path", redactor.recordedPath(contributor.applicationID), sensitive: true)))
        }

        // Said explicitly, because a reader comparing this against Activity Monitor
        // needs to know these are peaks from an interval that has ended rather than
        // a reading anyone can reproduce now.
        rows.append(.prose(
            "Recorded while this incident was happening, at its busiest moment, on "
            + "\(recorded.logicalCoreCount) logical cores. These are not current "
            + "readings."))
        return ReportSection(title: "Measurements", rows: rows)
    }

    /// The incident's own lifecycle. Every entry is a recorded timestamp; nothing
    /// here is inferred.
    private static func timelineSection(_ incident: Incident) -> ReportSection {
        var rows: [ReportRow] = [
            .field(ReportField("Conditions began", .text(incident.beganAt.formatted(.iso8601)))),
            .field(ReportField("Sustained long enough to count",
                               .text(incident.triggeredAt.formatted(.iso8601)))),
        ]
        if let recovery = incident.recoveryStartedAt {
            rows.append(.field(ReportField("Conditions cleared",
                                           .text(recovery.formatted(.iso8601)))))
        }
        if let closed = incident.closedAt {
            rows.append(.field(ReportField("Closed", .text(closed.formatted(.iso8601)))))
        } else {
            rows.append(.field(ReportField("Closed", .unavailable("still open at export"))))
        }
        return ReportSection(title: "Timeline", rows: rows)
    }

    /// FR-038: every statement travels with its evidence class, and every
    /// hypothesis with its confidence, so a recipient can weigh it the same way the
    /// person who exported it could.
    private static func summarySection(
        _ summary: IncidentSummary, redactor: Redactor
    ) -> ReportSection {
        var rows: [ReportRow] = [.prose(redactor.prose(summary.headline))]
        for conclusion in summary.conclusions {
            rows.append(.prose(redactor.prose(conclusion.display)))
        }
        for conclusion in summary.ruledOut {
            rows.append(.prose("Ruled out — " + redactor.prose(conclusion.display)))
        }
        return ReportSection(title: "Summary", rows: rows)
    }

    private static func window(_ incident: Incident) -> String {
        let began = incident.beganAt.formatted(.iso8601)
        guard let closed = incident.closedAt else { return "\(began) — still open" }
        return "\(began) — \(closed.formatted(.iso8601))"
    }
}

// MARK: - Redaction

/// Applies the user's choices while the document is built, so a hidden value never
/// enters the document. Prose is covered as well as structured fields: a process
/// name or a home directory left in a finding would defeat the whole thing.
struct Redactor {
    let options: RedactionOptions
    let attribution: CPUAttribution?
    let paths: [ProcessIdentity: String]
    /// Every other name that can reach prose in this document.
    ///
    /// The live attribution is not enough, and assuming it was is how "Hide app and
    /// process names" shipped leaking the one name the report is about. The Summary
    /// section is built from `IncidentSummary.conclusions`, which include
    /// `IncidentAttribution.conclusion` — "Slack was the largest measurable
    /// contributor while this was happening" — drawn from the *recorded*
    /// contributor list, and `IncidentSummarizer`'s lifecycle sentence, which names
    /// the command that kept exiting. Neither was ever shown to the redactor, so
    /// the structured fields went to `[redacted]` while the paragraph above them
    /// said the name out loud (FR-028, FR-029).
    var additionalNames: [String] = []

    func userName() -> ReportValue {
        options.hideUserName ? .redacted : .text(NSUserName())
    }

    func processName(_ name: String, detail: String) -> ReportValue {
        options.hideProcessNames ? .redacted : .text("\(name) — \(detail)")
    }

    /// A path recorded on the incident itself, which may not be a path at all —
    /// `IncidentContributor.applicationID` is the bundle path where the application
    /// had one and its display name where it did not.
    func recordedPath(_ applicationID: String) -> ReportValue {
        guard applicationID.hasPrefix("/") else {
            return .unavailable("path not recorded")
        }
        return options.hideFilePaths ? .redacted : .text(applicationID)
    }

    func path(for identity: ProcessIdentity) -> ReportValue {
        guard let path = paths[identity] else {
            return .unavailable("path not recorded")
        }
        return options.hideFilePaths ? .redacted : .text(path)
    }

    func prose(_ text: String) -> String {
        var result = text
        if options.hideProcessNames {
            // Longest first, so a name that contains another ("Google Chrome
            // Helper" and "Google Chrome") cannot leave the longer one half-scrubbed.
            let names = ((attribution?.contributors.map(\.label) ?? []) + additionalNames)
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
            for name in names {
                result = result.replacingOccurrences(
                    of: name, with: ExportDocument.redactedPlaceholder)
            }
        }
        if options.hideFilePaths {
            for path in paths.values {
                result = result.replacingOccurrences(
                    of: path, with: ExportDocument.redactedPlaceholder)
            }
        }
        if options.hideUserName {
            let name = NSUserName()
            if !name.isEmpty {
                result = result.replacingOccurrences(
                    of: name, with: ExportDocument.redactedPlaceholder)
            }
        }
        return result
    }
}
