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

/// FR-028 has one structural guarantee: redaction is decided when the document is
/// built, so there is exactly one place these options are interpreted. What is
/// tested here is the vocabulary every path uses to *state* those choices — the
/// export sheet shows them, an App Intent has to say them.
@Suite("Redaction options")
struct RedactionOptionsTests {
    @Test("Defaults hide the two identifying fields and keep the report readable")
    func defaultsAreTheFloor() {
        let subject = RedactionOptions.default
        #expect(subject.hideUserName)
        #expect(subject.hideFilePaths)
        #expect(!subject.hideProcessNames, "hiding names by default would gut the report")
        #expect(subject.costWarning == nil)
    }

    @Test("Hiding names is allowed and states its cost")
    func costWarningShown() {
        #expect(RedactionOptions(hideProcessNames: true).costWarning != nil)
        #expect(RedactionOptions(hideProcessNames: false).costWarning == nil)
    }

    /// The comparison an unattended path depends on: it must be able to tell that it
    /// is about to produce something less redacted than a person would have got.
    @Test("A weaker set of choices is detected and named")
    func weakeningIsDetected() {
        #expect(RedactionOptions.default.isAtLeastAsRedacted(as: .default))
        #expect(RedactionOptions(hideUserName: true, hideFilePaths: true,
                                 hideProcessNames: true)
            .isAtLeastAsRedacted(as: .default))

        let weaker = RedactionOptions(hideUserName: false, hideFilePaths: true)
        #expect(!weaker.isAtLeastAsRedacted(as: .default))
        #expect(weaker.fieldsLeftInComparedTo(.default) == ["your user name"])
        #expect(weaker.weakerThanDefaultWarning?.contains("less redacted") == true)
        #expect(weaker.weakerThanDefaultWarning?.contains("your user name") == true)
    }

    @Test("A report at least as redacted as the default carries no weakening warning")
    func noWarningWhenNotWeaker() {
        #expect(RedactionOptions.default.weakerThanDefaultWarning == nil)
        #expect(RedactionOptions(hideUserName: true, hideFilePaths: true,
                                 hideProcessNames: true).weakerThanDefaultWarning == nil)
    }

    @Test("The disclosure names what is hidden and what is not")
    func disclosureNamesBothSides() {
        let subject = RedactionOptions.default.disclosure
        #expect(subject.contains("Hidden: your user name and file paths"))
        #expect(subject.contains("included: app and process names"))

        let everything = RedactionOptions(hideUserName: true, hideFilePaths: true,
                                          hideProcessNames: true).disclosure
        #expect(everything.contains("nothing sensitive was included"))

        let nothing = RedactionOptions(hideUserName: false, hideFilePaths: false,
                                       hideProcessNames: false).disclosure
        #expect(nothing.contains("Nothing was hidden"))
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
