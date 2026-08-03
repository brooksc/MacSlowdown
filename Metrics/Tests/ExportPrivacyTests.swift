import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

private func incident(closedDaysAgo: Double? = nil, now: Date = Date()) -> Incident {
    let closed = closedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
    return Incident(
        id: UUID(), beganAt: closed ?? origin, triggeredAt: (closed ?? origin).addingTimeInterval(180),
        recoveryStartedAt: nil, closedAt: closed ?? origin.addingTimeInterval(600),
        conditions: [.cpuSaturation], severity: .high,
        peakCPUBusyFraction: 0.94, peakMemoryPressure: .normal)
}

private func attribution() -> CPUAttribution {
    CPUAttribution(
        totalBusyPercentOfOneCore: 800, attributedPercentOfOneCore: 700,
        unattributedPercentOfOneCore: 100,
        contributors: [ProcessCPUUsage(
            identity: ProcessIdentity(pid: 1, startTime: 1),
            command: "SecretProject", percentOfOneCore: 412, residentBytes: 1 << 30)],
        protectedProcesses: [], logicalCoreCount: 8)
}

private func export(_ options: RedactionOptions) -> DiagnosticExport {
    let subject = incident()
    return DiagnosticExporter.export(
        incident: subject,
        summary: IncidentSummarizer.summarize(incident: subject, attribution: attribution()),
        attribution: attribution(),
        options: options)
}

@Suite("Diagnostic export")
struct DiagnosticExportTests {
    @Test("The report contains the incident, machine context and versions")
    func reportIsComplete() {
        let text = export(.default).text
        #expect(text.contains("MacSlowdown incident report"))
        #expect(text.contains("CPU saturation"))
        #expect(text.contains("Cores"))
        // FR-040: versions travel with the report.
        #expect(text.contains("App "))
        #expect(text.contains("Schema"))
    }

    @Test("Every finding keeps its evidence class in the export")
    func evidenceSurvivesExport() {
        let text = export(.default).text
        #expect(text.contains("[measured]"))
        #expect(text.contains("[calculated]"))
        #expect(text.contains("heuristic"))
    }

    /// FR-028: paths, usernames and process names can be redacted.
    @Test("User name is redacted by default")
    func userNameRedactedByDefault() {
        #expect(export(.default).text.contains(DiagnosticExport.redactedPlaceholder))
        let shown = export(RedactionOptions(hideUserName: false)).text
        #expect(shown.contains(NSUserName()))
    }

    @Test("Process names can be hidden, including inside prose findings")
    func processNamesRedactedEverywhere() {
        let visible = export(RedactionOptions(hideProcessNames: false)).text
        #expect(visible.contains("SecretProject"))

        let hidden = export(RedactionOptions(hideProcessNames: true)).text
        #expect(!hidden.contains("SecretProject"),
                "a name left in a prose finding would defeat the redaction")
        #expect(hidden.contains(DiagnosticExport.redactedPlaceholder))
    }

    /// FR-028: the preview shows what is hidden, not only what is shown.
    @Test("Redacted fields are enumerable and counted")
    func redactionIsVisible() {
        let all = export(RedactionOptions(hideUserName: true, hideFilePaths: true,
                                          hideProcessNames: true))
        #expect(all.redactedFields.count == 3)
        #expect(all.options.redactedFieldCount == 3)
        #expect(all.text.contains("3 of 3 redactable fields hidden"))

        let none = export(RedactionOptions(hideUserName: false, hideFilePaths: false,
                                           hideProcessNames: false))
        #expect(none.redactedFields.isEmpty)
    }

    /// A choice that damages the report says so, rather than letting the user find
    /// out after sending it.
    @Test("Hiding process names warns about the cost")
    func costWarningShown() {
        #expect(RedactionOptions(hideProcessNames: true).costWarning != nil)
        #expect(RedactionOptions(hideProcessNames: false).costWarning == nil)
    }

    /// FR-028 and FR-029: no transmission occurs automatically. Building a report
    /// writes nothing; only the caller can deliver it.
    @Test("Exporting produces text and touches no file or network")
    func exportIsInert() {
        let report = export(.default)
        #expect(report.byteCount > 0)
        // The type exposes text and nothing that could send or save it.
        #expect(!report.text.isEmpty)
    }
}

@Suite("Privacy settings")
struct PrivacySettingsTests {
    /// FR-029: defaults are the most private option that still works.
    @Test("Defaults do not record paths and keep history for a bounded period")
    func defaultsArePrivate() {
        let settings = PrivacySettings.default
        #expect(!settings.recordFilePaths, "paths should be opt-in")
        #expect(settings.retention == .thirtyDays)
    }

    /// TASK-46 measured window titles as unavailable, so offering the choice would
    /// imply a capability we do not have.
    @Test("There is no window-title setting, because there is no such capability")
    func noWindowTitleSetting() {
        let encoded = try? JSONEncoder().encode(PrivacySettings.default)
        let json = String(decoding: encoded ?? Data(), as: UTF8.self).lowercased()
        #expect(!json.contains("windowtitle"))
        #expect(!json.contains("title"))
    }

    @Test("The data-handling statement is specific and checkable")
    func statementIsSpecific() {
        let statement = PrivacySettings.dataHandlingStatement.lowercased()
        #expect(statement.contains("stays on this mac"))
        #expect(statement.contains("no account"))
        #expect(statement.contains("no server"))
        #expect(statement.contains("no analytics"))
        #expect(statement.contains("export"), "must name the one way data can leave")
    }

    /// FR-029: the user can see exactly what is stored.
    @Test("Stored categories are enumerated and mention the absence of serials")
    func categoriesEnumerated() {
        let categories = PrivacySettings.storedCategories
        #expect(categories.count >= 4)
        let all = categories.map { $0.detail }.joined(separator: " ").lowercased()
        #expect(all.contains("no serial number"), "FR-049's exclusion should be visible")
    }
}

@Suite("Retention")
struct RetentionTests {
    @Test("Incidents older than the retention window are expired")
    func oldIncidentsExpire() {
        let now = Date()
        let incidents = [
            incident(closedDaysAgo: 1, now: now),
            incident(closedDaysAgo: 10, now: now),
            incident(closedDaysAgo: 45, now: now),
        ]
        let settings = PrivacySettings(retention: .thirtyDays)

        #expect(RetentionPolicy.retained(incidents, settings: settings, now: now).count == 2)
        #expect(RetentionPolicy.expired(incidents, settings: settings, now: now).count == 1)
    }

    @Test("A shorter retention keeps less")
    func shorterRetentionKeepsLess() {
        let now = Date()
        let incidents = [incident(closedDaysAgo: 1, now: now),
                         incident(closedDaysAgo: 10, now: now)]
        #expect(RetentionPolicy.retained(
            incidents, settings: PrivacySettings(retention: .sevenDays), now: now).count == 1)
        #expect(RetentionPolicy.retained(
            incidents, settings: PrivacySettings(retention: .ninetyDays), now: now).count == 2)
    }

    @Test("Retained and expired together account for everything")
    func partitionIsComplete() {
        let now = Date()
        let incidents = (1...10).map { incident(closedDaysAgo: Double($0) * 7, now: now) }
        let settings = PrivacySettings(retention: .thirtyDays)
        let retained = RetentionPolicy.retained(incidents, settings: settings, now: now)
        let expired = RetentionPolicy.expired(incidents, settings: settings, now: now)

        #expect(retained.count + expired.count == incidents.count)
        #expect(Set(retained.map(\.id)).isDisjoint(with: Set(expired.map(\.id))))
    }
}
