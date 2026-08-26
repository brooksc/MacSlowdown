import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private let secretName = "SecretProject"
private let secretPath = "/Users/someone/Private/SecretProject.app/Contents/MacOS/SecretProject"
private let contributorIdentity = ProcessIdentity(pid: 4242, startTime: 99)

/// Closed and carrying its own recorded attribution, which is what a closed
/// incident's report is built from — a closed incident is never narrated from the
/// live reading, because that describes a machine which has since recovered.
private func incident() -> Incident {
    var subject = Incident(
        id: UUID(), beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: origin.addingTimeInterval(600),
        conditions: [.cpuSaturation], severity: .high,
        peakCPUBusyFraction: 0.94, peakMemoryPressure: .warning)
    subject.attribution = IncidentAttribution(
        sample: AttributionSample(
            applications: [IncidentContributor(
                applicationID: "/Applications/SecretProject.app",
                displayName: secretName, peakPercentOfOneCore: 412)],
            totalBusyPercentOfOneCore: 800,
            attributedPercentOfOneCore: 700,
            unattributedPercentOfOneCore: 100,
            logicalCoreCount: 8),
        at: origin)
    return subject
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

@MainActor
private func model() -> ExportReportModel {
    let subject = incident()
    return ExportReportModel(
        incident: subject,
        summary: IncidentSummarizer.summarize(incident: subject, attribution: attribution()),
        attribution: attribution(),
        contributorPaths: [contributorIdentity: secretPath],
        generatedAt: origin)
}

@Suite("Export sheet")
@MainActor
struct ExportReportModelTests {
    /// The decisive property of this screen: the file the user receives is byte for
    /// byte the document the preview rendered. If these could diverge, the preview
    /// would be a claim about the file rather than a view of it.
    @Test("The saved file is exactly the bytes of the previewed document")
    func fileMatchesPreview() throws {
        let subject = model()
        subject.options = RedactionOptions(hideUserName: true, hideFilePaths: true,
                                           hideProcessNames: false)
        let previewed = subject.document

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try subject.write(to: url)

        let written = try Data(contentsOf: url)
        #expect(written == previewed.data(as: .plainText))
        #expect(written.count == previewed.byteCount(as: .plainText))
    }

    /// What the preview shows as a filled "redacted" block must be genuinely gone
    /// from the file, not masked in the interface.
    @Test("A field the preview hides is absent from the written file")
    func hiddenFieldsAbsentFromFile() throws {
        let subject = model()
        subject.options = RedactionOptions(hideUserName: true, hideFilePaths: true,
                                           hideProcessNames: true)

        // What the preview would render as redacted.
        let redacted = subject.document.fields.filter(\.isRedacted)
        #expect(!redacted.isEmpty)

        for format in ReportFormat.allCases {
            subject.format = format
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(UUID().uuidString).\(format.fileExtension)")
            defer { try? FileManager.default.removeItem(at: url) }
            try subject.write(to: url)
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)

            #expect(!text.contains(secretName), "\(format) leaked a hidden app name")
            #expect(!text.contains(secretPath), "\(format) leaked a hidden path")
            #expect(!text.contains(NSUserName()), "\(format) leaked the user name")
        }
    }

    @Test("Changing a toggle changes the file that would be written")
    func togglesReachTheFile() {
        let subject = model()
        subject.options = RedactionOptions(hideUserName: false, hideFilePaths: false,
                                           hideProcessNames: false)
        let full = subject.fileData
        subject.options = RedactionOptions(hideUserName: true, hideFilePaths: true,
                                           hideProcessNames: true)
        #expect(subject.fileData != full)
        #expect(subject.document.redactedFieldCount > 0)

        subject.sections = ReportSections(measurements: false, machineDetails: false,
                                          timeline: false)
        #expect(subject.fileData.count < full.count)
    }

    @Test("The status line and file name follow the chosen format")
    func statusFollowsFormat() {
        let subject = model()
        #expect(subject.suggestedFileName.hasSuffix(".txt"))
        let text = subject.statusLine
        subject.format = .json
        #expect(subject.suggestedFileName.hasSuffix(".json"))
        #expect(subject.statusLine != text, "the size shown must be the size of this format")
    }

    /// FR-038 through to the recipient.
    @Test("The exported summary keeps its confidence labelling")
    func confidenceReachesTheFile() {
        let subject = model()
        #expect(String(decoding: subject.fileData, as: UTF8.self).contains("confidence"))
    }
}
