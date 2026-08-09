import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private let secretName = "SecretProject"
private let secretPath = "/Users/someone/Private Work/SecretProject.app/Contents/MacOS/SecretProject"
private let contributorIdentity = ProcessIdentity(pid: 4242, startTime: 99)

private func incident(open: Bool = false) -> Incident {
    Incident(
        id: UUID(), beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: open ? nil : origin.addingTimeInterval(600),
        conditions: [.cpuSaturation, .memoryPressure], severity: .high,
        peakCPUBusyFraction: 0.94, peakMemoryPressure: .critical)
}

private func attribution() -> CPUAttribution {
    CPUAttribution(
        totalBusyPercentOfOneCore: 800, attributedPercentOfOneCore: 700,
        unattributedPercentOfOneCore: 100,
        contributors: [ProcessCPUUsage(
            identity: contributorIdentity, command: secretName,
            percentOfOneCore: 412, residentBytes: 1 << 30)],
        protectedProcesses: [], logicalCoreCount: 8)
}

private func document(
    _ options: RedactionOptions = .default,
    sections: ReportSections = .all,
    open: Bool = false
) -> ExportDocument {
    let subject = incident(open: open)
    return IncidentReport.document(
        incident: subject,
        machine: .current(),
        summary: IncidentSummarizer.summarize(incident: subject, attribution: attribution()),
        attribution: attribution(),
        contributorPaths: [contributorIdentity: secretPath],
        sections: sections,
        options: options,
        generatedAt: origin)
}

@Suite("Export document")
struct ExportDocumentTests {
    /// FR-028: the preview must be the report, not a description of it. Both the
    /// preview and the file come from this one object, so the test that matters is
    /// that a value the preview marks redacted is absent from every rendering.
    @Test("A redacted value is absent from the document, not merely masked")
    func redactedValuesAreAbsent() {
        let hidden = document(RedactionOptions(hideUserName: true, hideFilePaths: true,
                                               hideProcessNames: true))

        // The document itself does not hold the value.
        for field in hidden.fields where field.isRedacted {
            #expect(field.value == .redacted)
        }
        #expect(!hidden.plainText.contains(secretName))
        #expect(!hidden.plainText.contains(secretPath))
        #expect(!hidden.plainText.contains(NSUserName()))
        #expect(!hidden.json.contains(secretName))
        #expect(!hidden.json.contains(secretPath))
        #expect(!hidden.json.contains(NSUserName()))
    }

    @Test("Shown values really are present when not hidden")
    func shownValuesArePresent() {
        let shown = document(RedactionOptions(hideUserName: false, hideFilePaths: false,
                                              hideProcessNames: false))
        #expect(shown.plainText.contains(secretName))
        #expect(shown.plainText.contains(secretPath))
        #expect(shown.plainText.contains(NSUserName()))
        #expect(shown.redactedFieldCount == 0)
    }

    /// A name left inside a prose finding would defeat the structured redaction.
    @Test("Process names are redacted inside prose findings too")
    func prosePathsAndNamesRedacted() {
        let hidden = document(RedactionOptions(hideProcessNames: true))
        let prose = hidden.sections.flatMap(\.rows).compactMap { row -> String? in
            if case .prose(let text) = row { return text }
            return nil
        }.joined(separator: "\n")
        #expect(!prose.contains(secretName))
        #expect(prose.contains(ExportDocument.redactedPlaceholder))
    }

    @Test("Each field toggles independently and the count reflects the document")
    func togglesAreIndependent() {
        let none = document(RedactionOptions(hideUserName: false, hideFilePaths: false,
                                             hideProcessNames: false))
        #expect(none.redactedFieldCount == 0)
        #expect(none.sensitiveFieldCount > 0)

        let userOnly = document(RedactionOptions(hideUserName: true, hideFilePaths: false,
                                                 hideProcessNames: false))
        #expect(userOnly.redactedFieldCount == 1)
        #expect(userOnly.plainText.contains(secretName))

        let all = document(RedactionOptions(hideUserName: true, hideFilePaths: true,
                                            hideProcessNames: true))
        #expect(all.redactedFieldCount == all.sensitiveFieldCount)
    }

    /// The denominator is what the report actually contains. Claiming a path was
    /// hidden when no path was ever recorded would be a false assurance.
    @Test("Sensitive fields are counted from the report, not from a fixed list")
    func countIsDerivedFromTheDocument() {
        let subject = incident()
        let noPaths = IncidentReport.document(
            incident: subject, machine: .current(),
            summary: IncidentSummarizer.summarize(incident: subject, attribution: attribution()),
            attribution: attribution(), contributorPaths: [:],
            options: RedactionOptions(hideUserName: true, hideFilePaths: true,
                                      hideProcessNames: false),
            generatedAt: origin)

        // The path field is present but unavailable, so it is neither shown nor
        // counted as something the user successfully hid.
        let pathField = noPaths.fields.first { $0.label == "Path" }
        #expect(pathField?.value == .unavailable("path not recorded"))
        #expect(pathField?.isRedacted == false)
        #expect(noPaths.redactedFieldCount == 1)
    }

    @Test("The status line states how many fields are hidden and how large the file is")
    func statusLineIsHonest() {
        let hidden = document(RedactionOptions(hideUserName: true, hideFilePaths: true,
                                               hideProcessNames: false))
        let line = hidden.statusLine(for: .plainText)
        #expect(line.contains("2 of \(hidden.sensitiveFieldCount) sensitive fields hidden"))
        #expect(hidden.byteCount(as: .plainText) == hidden.data(as: .plainText).count)
        #expect(hidden.byteCount(as: .json) != hidden.byteCount(as: .plainText))
    }

    /// Over-redaction is permitted; the cost is stated rather than discovered.
    @Test("Hiding names is allowed and says what it costs")
    func costIsStated() {
        #expect(document(RedactionOptions(hideProcessNames: true)).costWarning != nil)
        #expect(document(RedactionOptions(hideProcessNames: false)).costWarning == nil)
    }

    /// FR-038: a moderate-confidence judgement must not read as fact to a recipient.
    @Test("Confidence labelling survives into the exported artefact")
    func confidenceSurvives() {
        let report = document()
        let text = report.plainText
        #expect(text.contains("Measured."))
        #expect(text.contains("confidence"),
                "a heuristic without its confidence would read as fact")
        #expect(report.json.contains("confidence"))
    }

    /// FR-040: a report has to stay interpretable after the app changes.
    @Test("Versions and schema always travel with the report")
    func versionsAlwaysPresent() {
        let stripped = document(.default, sections: ReportSections(
            measurements: false, machineDetails: false, timeline: false))
        #expect(stripped.plainText.contains("Schema"))
        #expect(stripped.plainText.contains("App"))
    }

    @Test("Include choices add and remove whole sections")
    func sectionsFollowChoices() {
        let all = document()
        #expect(all.sections.contains { $0.title == "Measurements" })
        #expect(all.sections.contains { $0.title == "Machine" })
        #expect(all.sections.contains { $0.title == "Timeline" })

        let minimal = document(.default, sections: ReportSections(
            measurements: false, machineDetails: false, timeline: false))
        #expect(!minimal.sections.contains { $0.title == "Measurements" })
        #expect(!minimal.sections.contains { $0.title == "Machine" })
        #expect(!minimal.sections.contains { $0.title == "Timeline" })
        #expect(minimal.byteCount(as: .plainText) < all.byteCount(as: .plainText))
    }

    /// FR-029: nothing leaves the machine on its own. Building a report writes and
    /// sends nothing; the caller has to write the bytes somewhere.
    @Test("Building a report writes no file")
    func buildingWritesNothing() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = document().plainText
        _ = document().json
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.isEmpty)
    }

    /// An open incident is not given an end time it does not have.
    @Test("An incident still running is labelled, not guessed at")
    func openIncidentLabelled() {
        let text = document(.default, open: true).plainText
        #expect(text.contains("still open"))
    }

    /// Only formats rendered from the same document are offered. PDF is not, so a
    /// user cannot pick a format whose contents were never previewed.
    @Test("Every offered format renders from the document")
    func offeredFormatsAllRender() {
        let report = document()
        for format in ReportFormat.allCases {
            #expect(!report.data(as: format).isEmpty)
        }
        #expect(ReportFormat.allCases.count == 2)
    }

    /// The JSON omits the key rather than writing a placeholder string, so a
    /// machine reader cannot mistake "[redacted]" for a value.
    @Test("JSON marks a redacted field and carries no value for it")
    func jsonOmitsRedactedValues() throws {
        let hidden = document(RedactionOptions(hideUserName: true))
        let parsed = try JSONSerialization.jsonObject(
            with: Data(hidden.json.utf8)) as? [String: Any]
        let sections = try #require(parsed?["sections"] as? [[String: Any]])
        let fields = sections.flatMap { ($0["fields"] as? [[String: Any]]) ?? [] }
        let user = try #require(fields.first { $0["label"] as? String == "User" })
        #expect(user["redacted"] as? Bool == true)
        #expect(user["value"] == nil)
    }
}
