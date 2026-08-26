import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// Two things in this app can produce a report: the export sheet, and the
/// `ExportLatestIncidentIntent` a shortcut runs unattended. They must be the same
/// report. The App Intent is the path where the person is least able to inspect
/// what was produced — it can end up in another app before anybody reads it — so
/// "the sheet is safe" is not an answer for it (FR-028).
private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private let secretName = "SecretProject"
private let secretPath = "/Users/someone/Private Work/SecretProject.app/Contents/MacOS/SecretProject"
/// What a **closed** incident's report carries. A recorded contributor has no
/// `(pid, start time)` — by design, so a family survives PID replacement — so there
/// is no per-process executable path in the record, only the bundle. Both are
/// sensitive and both must be redactable; the tests below check the one that is
/// actually emitted, or they would pass by asserting the absence of a string the
/// report never contained.
private let secretBundlePath = "/Users/someone/Private Work/SecretProject.app"
private let contributorIdentity = ProcessIdentity(pid: 4242, startTime: 99)

/// Closed, and carrying what it recorded — which is what a closed incident's
/// report is now built from, rather than from whatever is busy at export time.
private func incident() -> Incident {
    var subject = Incident(
        id: UUID(), beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: origin.addingTimeInterval(600),
        conditions: [.cpuSaturation], severity: .high,
        peakCPUBusyFraction: 0.94, peakMemoryPressure: .warning)
    subject.attribution = IncidentAttribution(
        sample: AttributionSample(
            applications: [IncidentContributor(
                applicationID: "/Users/someone/Private Work/SecretProject.app",
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

/// The families the store would hand the App Intent, carrying the same path the
/// sheet is given directly.
private func families() -> [ProcessFamily] {
    [ProcessFamily(
        id: secretName, displayName: secretName,
        bundlePath: "/Users/someone/Private Work/SecretProject.app",
        members: [FamilyMember(
            record: ProcessRecord(
                identity: contributorIdentity, command: secretName, uid: 501, ppid: 1,
                metrics: .measured(ProcessMetrics(cpuTicks: 1, residentBytes: 1 << 30))),
            resolved: ResolvedIdentity(executablePath: secretPath,
                                       appBundlePath: "/Users/someone/Private Work/SecretProject.app",
                                       bundleID: nil, teamID: nil),
            membership: .certain)])]
}

private func summary() -> IncidentSummary {
    IncidentSummarizer.summarize(incident: incident(), attribution: attribution())
}

private let machine = MachineContext.current()

@MainActor
private func sheetBytes(_ options: RedactionOptions, _ format: ReportFormat) -> Data {
    let model = ExportReportModel(
        incident: incident(), summary: summary(), attribution: attribution(),
        contributorPaths: IncidentReport.contributorPaths(in: families()),
        machine: machine, generatedAt: origin)
    model.options = options
    model.format = format
    return model.fileData
}

private func intentReport(_ options: RedactionOptions,
                          _ format: ReportFormat) -> UnattendedIncidentReport {
    UnattendedIncidentReport.make(
        incident: incident(), summary: summary(), attribution: attribution(),
        machine: machine, families: families(), options: options, format: format,
        generatedAt: origin)
}

private let everyCombination: [RedactionOptions] = [false, true].flatMap { user in
    [false, true].flatMap { paths in
        [false, true].map { names in
            RedactionOptions(hideUserName: user, hideFilePaths: paths, hideProcessNames: names)
        }
    }
}

@Suite("Every report path renders the same document")
@MainActor
struct ExportPathParityTests {
    /// The decisive one. If these bytes could differ, a shortcut could hand out
    /// something the preview never showed.
    @Test("The sheet and the App Intent produce identical bytes for identical choices")
    func pathsAgreeByteForByte() {
        for options in everyCombination {
            for format in ReportFormat.allCases {
                let sheet = sheetBytes(options, format)
                let intent = Data(intentReport(options, format).text.utf8)
                #expect(sheet == intent,
                        "\(format) diverged for \(options)")
            }
        }
    }

    /// Written to real files and searched, rather than compared in memory: the file
    /// is what actually leaves.
    @Test("A hidden value is absent from the file every path writes")
    func hiddenValuesAbsentFromEveryPath() throws {
        let hideAll = RedactionOptions(hideUserName: true, hideFilePaths: true,
                                       hideProcessNames: true)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for format in ReportFormat.allCases {
            let written: [(path: String, data: Data)] = [
                ("sheet", sheetBytes(hideAll, format)),
                ("intent", Data(intentReport(hideAll, format).text.utf8)),
            ].map { name, data in
                let url = directory.appendingPathComponent("\(name).\(format.fileExtension)")
                try? data.write(to: url, options: .atomic)
                return (url.path, data)
            }

            for (name, data) in written {
                let text = String(decoding: (try? Data(contentsOf: URL(fileURLWithPath: name)))
                    ?? data, as: UTF8.self)
                #expect(!text.contains(secretName), "\(name) \(format) leaked the app name")
                #expect(!text.contains(secretBundlePath),
                        "\(name) \(format) leaked the path")
                #expect(!text.contains(NSUserName()), "\(name) \(format) leaked the user name")
            }
        }
    }

    /// The control. Absence only means something if the same values are present when
    /// nothing is hidden — otherwise the test would pass on an empty report. It also
    /// guards the JSON escaping: with slashes escaped, a path is written `\/Users\/…`
    /// and an absence check on the raw path would pass while the path was present.
    @Test("The same values are present in every path when nothing is hidden")
    func shownValuesPresentInEveryPath() {
        let hideNothing = RedactionOptions(hideUserName: false, hideFilePaths: false,
                                           hideProcessNames: false)
        for format in ReportFormat.allCases {
            for text in [String(decoding: sheetBytes(hideNothing, format), as: UTF8.self),
                         intentReport(hideNothing, format).text] {
                #expect(text.contains(secretName))
                #expect(text.contains(secretBundlePath))
                #expect(text.contains(NSUserName()))
            }
        }
    }

    /// FR-028 through the path where nobody can look: the intent has to say what the
    /// preview would have shown.
    @Test("The App Intent states what it hid, with the same defaults as the sheet")
    func intentStatesItsRedaction() {
        let byDefault = intentReport(.default, .plainText)
        #expect(byDefault.document.options == RedactionOptions.default)
        #expect(byDefault.disclosure.contains("Hidden: your user name and file paths"))
        #expect(byDefault.disclosure.contains("included: app and process names"))
        #expect(byDefault.disclosure.contains("Nothing was sent anywhere."))
        #expect(byDefault.disclosure.contains(
            "\(byDefault.document.redactedFieldCount) of "
            + "\(byDefault.document.sensitiveFieldCount) sensitive fields hidden"))
        #expect(!byDefault.disclosure.contains("less redacted"))
    }

    /// AppIntents will only take literal defaults, so the automation's defaults are
    /// restated rather than referenced. If they ever drifted below the app's own
    /// default, every unattended run would quietly be less redacted than the sheet.
    @Test("The automation's defaults are the app's defaults")
    func automationDefaultsMatchTheApp() {
        #expect(ExportLatestIncidentIntent.declaredDefaults == RedactionOptions.default)
        #expect(ExportLatestIncidentIntent.declaredDefaults
            .fieldsLeftInComparedTo(.default).isEmpty)
    }

    /// The failure this task exists to prevent. Turning a toggle off in a shortcut is
    /// allowed; doing it silently is not.
    @Test("A less redacted unattended report says so before anything else")
    func weakerChoicesAreAnnounced() {
        let weaker = intentReport(
            RedactionOptions(hideUserName: false, hideFilePaths: false), .plainText)
        let disclosure = weaker.disclosure
        #expect(disclosure.hasPrefix("This report is less redacted than MacSlowdown's default"))
        #expect(disclosure.contains("your user name"))
        #expect(disclosure.contains("file paths"))
        // And the values really are in the text it hands over, so the warning is not
        // theoretical.
        #expect(weaker.text.contains(NSUserName()))
        #expect(weaker.text.contains(secretBundlePath))
    }

    /// Over-redaction is permitted on both paths, and costs the same thing on both.
    @Test("Hiding names carries its cost warning on the unattended path too")
    func costWarningTravels() {
        let quiet = intentReport(
            RedactionOptions(hideUserName: true, hideFilePaths: true, hideProcessNames: true),
            .plainText)
        #expect(quiet.disclosure.contains("harder for anyone to interpret"))
        #expect(quiet.document.redactedFieldCount == quiet.document.sensitiveFieldCount)
    }

    /// The intent offers only formats rendered from the document, exactly as the
    /// sheet does. A format the preview cannot show is a second rendering path.
    @Test("Every format an automation can ask for maps onto a document rendering")
    func formatsMapOntoTheDocument() {
        for asked in [ReportFileFormat.plainText, .json] {
            let report = intentReport(.default, asked.format)
            #expect(!report.text.isEmpty)
            #expect(report.byteCount == report.document.byteCount(as: asked.format))
        }
        #expect(ReportFormat.allCases.count == 2, "PDF is deliberately not offered")
    }
}
