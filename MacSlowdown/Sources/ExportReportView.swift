import AppKit
import Metrics
import SwiftUI
import UniformTypeIdentifiers

/// What the export sheet is choosing, and the document those choices produce.
///
/// The document is the single source: the preview renders it, and the saved file
/// is `document.data(as:)`. There is no second rendering path that could disagree
/// with what the user was shown — which is the whole point of FR-028.
@MainActor
@Observable
final class ExportReportModel {
    var sections: ReportSections = .all
    var options: RedactionOptions = .default
    var format: ReportFormat = .plainText

    private let incident: Incident
    private let machine: MachineContext
    private let summary: IncidentSummary
    private let attribution: CPUAttribution?
    private let contributorPaths: [ProcessIdentity: String]
    private let generatedAt: Date

    init(incident: Incident,
         summary: IncidentSummary,
         attribution: CPUAttribution?,
         contributorPaths: [ProcessIdentity: String] = [:],
         machine: MachineContext = .current(),
         generatedAt: Date = Date()) {
        self.incident = incident
        self.machine = machine
        self.summary = summary
        self.attribution = attribution
        self.contributorPaths = contributorPaths
        self.generatedAt = generatedAt
    }

    var document: ExportDocument {
        IncidentReport.document(
            incident: incident, machine: machine, summary: summary,
            attribution: attribution, contributorPaths: contributorPaths,
            sections: sections, options: options, generatedAt: generatedAt)
    }

    var statusLine: String { document.statusLine(for: format) }

    var suggestedFileName: String {
        let stamp = generatedAt.formatted(.iso8601.year().month().day())
        return "MacSlowdown report \(stamp).\(format.fileExtension)"
    }

    /// Exactly the bytes the preview describes.
    var fileData: Data { document.data(as: format) }

    /// Writes the report where the user chose. Nothing is written until this is
    /// called, and nothing is transmitted at all (FR-029).
    func write(to url: URL) throws {
        try fileData.write(to: url, options: .atomic)
    }
}

/// Export a report, showing the redacted document itself before anything leaves
/// the machine (FR-028, FR-029, FR-038). Design reference: 1k.
struct ExportReportView: View {
    @Bindable var model: ExportReportModel
    let onClose: () -> Void

    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                choices
                    .frame(width: 260, alignment: .leading)
                Divider()
                preview
                    .frame(minWidth: 380)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Share this report").font(.title2).bold()
            Text("Check what's in it before you send it. Nothing is uploaded — "
                 + "you'll get a file to attach yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var choices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("INCLUDE").font(.caption).bold().foregroundStyle(.secondary)
                    Toggle("Charts and measurements", isOn: $model.sections.measurements)
                    Toggle("Mac and macOS details", isOn: $model.sections.machineDetails)
                    Toggle("Timeline of events", isOn: $model.sections.timeline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("HIDE").font(.caption).bold().foregroundStyle(.secondary)
                    Toggle("My user name", isOn: $model.options.hideUserName)
                    Toggle("File paths", isOn: $model.options.hideFilePaths)
                    Toggle("App and process names", isOn: $model.options.hideProcessNames)
                    // Over-redaction is permitted. Its cost is stated here rather
                    // than discovered by the recipient.
                    if let warning = model.document.costWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("FORMAT").font(.caption).bold().foregroundStyle(.secondary)
                    Picker("Format", selection: $model.format) {
                        ForEach(ReportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .labelsHidden()
                    Text(ReportFormat.unofferedFormatsExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW").font(.caption).bold().foregroundStyle(.secondary)
            ScrollView {
                ReportPreview(document: model.document)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            Text(model.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(model.statusLine). This is what the file will contain.")
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel, action: onClose)
                .keyboardShortcut(.cancelAction)
            Button("Save report…", action: save)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.suggestedFileName
        panel.allowedContentTypes = [model.format == .json ? .json : .plainText]
        panel.message = "The file is written here and nowhere else. Nothing is uploaded."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.write(to: url)
            onClose()
        } catch {
            saveError = "Could not write the file: \(error.localizedDescription)"
        }
    }
}

/// The document, shown as a recipient will read it. Redacted values appear as a
/// filled block marked "redacted" — the value is not held by the document at all,
/// so this is not a mask over something still present.
struct ReportPreview: View {
    let document: ExportDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(document.title).font(.headline)
            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                if !section.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = section.title {
                            Text(title).font(.caption).bold().foregroundStyle(.secondary)
                        }
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                            RowView(row: row)
                        }
                    }
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    private struct RowView: View {
        let row: ReportRow

        var body: some View {
            switch row {
            case .field(let field):
                HStack(alignment: .top, spacing: 8) {
                    Text(field.label)
                        .frame(width: 140, alignment: .leading)
                        .foregroundStyle(.secondary)
                    value(field.value)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(field.label): \(spoken(field.value))")
            case .prose(let text):
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        @ViewBuilder
        private func value(_ value: ReportValue) -> some View {
            switch value {
            case .text(let text):
                Text(text).fixedSize(horizontal: false, vertical: true)
            case .redacted:
                HStack(spacing: 6) {
                    // Shape and text, never colour alone (FR-034).
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary)
                        .frame(width: 90, height: 11)
                    Text("redacted").foregroundStyle(.secondary)
                }
            case .unavailable(let reason):
                Text("not available — \(reason)").foregroundStyle(.secondary)
            }
        }

        private func spoken(_ value: ReportValue) -> String {
            switch value {
            case .text(let text): text
            case .redacted: "redacted, this value is not in the file"
            case .unavailable(let reason): "not available, \(reason)"
            }
        }
    }
}
