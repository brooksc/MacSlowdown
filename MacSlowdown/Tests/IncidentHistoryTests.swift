import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private let now = Date(timeIntervalSince1970: 1_770_000_000)

private func incident(
    daysAgo: Double,
    conditions: Set<IncidentCondition> = [.cpuSaturation],
    open: Bool = false,
    severity: IncidentSeverity = .high
) -> Incident {
    let began = now.addingTimeInterval(-daysAgo * 86_400)
    return Incident(
        id: UUID(),
        beganAt: began,
        triggeredAt: began.addingTimeInterval(180),
        recoveryStartedAt: nil,
        closedAt: open ? nil : began.addingTimeInterval(600),
        conditions: conditions,
        severity: severity,
        peakCPUBusyFraction: 0.9,
        peakMemoryPressure: .normal)
}

@Suite("Incident history: range and ordering")
struct IncidentHistoryRangeTests {
    @Test("The list is scoped by the selected range")
    func rangeScopesTheList() {
        let recent = [incident(daysAgo: 1), incident(daysAgo: 12), incident(daysAgo: 40)]

        let week = IncidentHistory.entries(
            open: nil, recent: recent, range: .week, now: now)
        let month = IncidentHistory.entries(
            open: nil, recent: recent, range: .month, now: now)

        #expect(week.count == 1)
        #expect(month.count == 2)
    }

    @Test("An open incident sorts above history, then most recent first")
    func openSortsFirst() {
        let entries = IncidentHistory.entries(
            open: incident(daysAgo: 3, open: true),
            recent: [incident(daysAgo: 1), incident(daysAgo: 2)],
            range: .week, now: now)

        #expect(entries.count == 3)
        #expect(entries[0].isOpen)
        #expect(entries[1].at > entries[2].at)
    }

    @Test("A range covers whole days, so this morning's incident is inside 7 days")
    func rangeCoversWholeDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = IncidentHistory.Range.week.start(from: now, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: start, to: now).day == 6)
    }
}

@Suite("Incident outcome vocabulary")
struct IncidentOutcomeTests {
    @Test("An open incident is still going")
    func openIsStillGoing() {
        #expect(IncidentHistory.outcome(for: incident(daysAgo: 0, open: true)) == .stillOpen)
    }

    /// The evidence rule this suite exists for: a closed incident is *not*
    /// evidence that anybody did anything. With no action recorded we say so,
    /// rather than crediting the user or the machine.
    @Test("A closed incident with no recorded action says no action was recorded")
    func closedWithoutActionIsNotCreditedToAnyone() {
        let outcome = IncidentHistory.outcome(for: incident(daysAgo: 1))
        #expect(outcome == .recoveredNoActionRecorded)
        #expect(outcome.label.contains("no action was recorded"))
        #expect(!outcome.label.contains("you acted"))
    }

    @Test("Recovered-after-you-acted requires a recorded action inside the incident")
    func actionMustBeRecordedAndInsideTheWindow() {
        let closed = incident(daysAgo: 1)
        let inside = ActionVerifier.verify(
            action: .revealInFinder, target: "Handbrake", result: .succeeded,
            before: 0.9, after: 0.2, window: .seconds(30),
            requestedAt: closed.beganAt.addingTimeInterval(60))
        let before = ActionVerifier.verify(
            action: .revealInFinder, target: "Handbrake", result: .succeeded,
            before: 0.9, after: 0.2, window: .seconds(30),
            requestedAt: closed.beganAt.addingTimeInterval(-3_600))
        let didNotRun = ActionVerifier.verify(
            action: .revealInFinder, target: "Handbrake",
            result: .withheld(reason: "not available"),
            before: nil, after: nil, window: .seconds(30),
            requestedAt: closed.beganAt.addingTimeInterval(60))

        #expect(IncidentHistory.outcome(for: closed, action: inside) == .recoveredAfterAction)
        #expect(IncidentHistory.outcome(for: closed, action: before)
                == .recoveredNoActionRecorded)
        #expect(IncidentHistory.outcome(for: closed, action: didNotRun)
                == .recoveredNoActionRecorded)
    }

    /// FR-016: a rule suppresses the alert, never the record — so the row still
    /// exists and says why it was quiet.
    @Test("A suppressing rule names the application and the classification")
    func suppressionNamesTheRule() {
        let suppression = SuppressedDetection(
            application: "Handbrake", classification: .expected, severity: .high)
        let outcome = IncidentHistory.outcome(for: incident(daysAgo: 1), suppression: suppression)

        #expect(outcome == .suppressedByRule(application: "Handbrake", classification: .expected))
        #expect(outcome.label == "Not alerted — you marked Handbrake as expected")
    }

    @Test("The four outcomes read differently from each other")
    func vocabularyIsDistinct() {
        let labels = Set([
            IncidentHistory.Outcome.stillOpen.label,
            IncidentHistory.Outcome.recoveredNoActionRecorded.label,
            IncidentHistory.Outcome.recoveredAfterAction.label,
            IncidentHistory.Outcome.suppressedByRule(
                application: "Handbrake", classification: .expected).label,
        ])
        #expect(labels.count == 4)
    }
}

@Suite("Incident pattern summary")
struct IncidentPatternTests {
    @Test("The summary counts what fell in the range")
    func countsTheRange() {
        let entries = IncidentHistory.entries(
            open: nil, recent: [incident(daysAgo: 1), incident(daysAgo: 2)],
            range: .week, now: now)
        #expect(IncidentHistory.pattern(for: entries, range: .week).headline
                == "2 incidents in the last 7 days")
    }

    @Test("One incident is singular, and none says so plainly")
    func singularAndEmpty() {
        let one = IncidentHistory.entries(
            open: nil, recent: [incident(daysAgo: 1)], range: .week, now: now)
        #expect(IncidentHistory.pattern(for: one, range: .week).headline
                == "1 incident in the last 7 days")
        #expect(IncidentHistory.pattern(for: [], range: .month).headline
                == "No incidents in the last 30 days")
    }

    /// The rule the design turns on: one incident is an event, several sharing a
    /// condition is a finding. Two is neither.
    @Test("Two incidents state no pattern")
    func twoIsNotAPattern() {
        let entries = IncidentHistory.entries(
            open: nil, recent: [incident(daysAgo: 1), incident(daysAgo: 2)],
            range: .week, now: now)
        #expect(IncidentHistory.pattern(for: entries, range: .week).recurrence == nil)
    }

    @Test("A condition recurring across several incidents is named with its count")
    func recurrenceIsNamed() {
        let entries = IncidentHistory.entries(
            open: nil,
            recent: [
                incident(daysAgo: 1), incident(daysAgo: 2), incident(daysAgo: 3),
                incident(daysAgo: 4, conditions: [.memoryPressure]),
            ],
            range: .week, now: now)
        #expect(IncidentHistory.pattern(for: entries, range: .week).recurrence
                == "CPU saturation in 3 of them")
    }

    @Test("Four incidents with no shared condition state no recurrence")
    func noSharedConditionMeansNoClaim() {
        let entries = IncidentHistory.entries(
            open: nil,
            recent: [
                incident(daysAgo: 1, conditions: [.cpuSaturation]),
                incident(daysAgo: 2, conditions: [.memoryPressure]),
                incident(daysAgo: 3, conditions: [.thermalPressure]),
                incident(daysAgo: 4, conditions: [.lowStorage]),
            ],
            range: .week, now: now)
        #expect(IncidentHistory.pattern(for: entries, range: .week).recurrence == nil)
    }
}

@Suite("Incident day strip")
struct IncidentDayStripTests {
    @Test("The strip has one column per day in the range")
    func columnCount() {
        #expect(IncidentHistory.days(for: [], range: .week, now: now).count == 7)
        #expect(IncidentHistory.days(for: [], range: .month, now: now).count == 30)
    }

    @Test("Incidents land on the day they began, and quiet days read as zero")
    func bucketsByDay() {
        let entries = IncidentHistory.entries(
            open: nil, recent: [incident(daysAgo: 1), incident(daysAgo: 1)],
            range: .week, now: now)
        let days = IncidentHistory.days(for: entries, range: .week, now: now)

        #expect(days.map(\.count).reduce(0, +) == 2)
        #expect(days.last?.count == 0)  // today
        #expect(days.dropLast().last?.count == 2)  // yesterday
    }

    /// FR-034: the strip's shape is never the only carrier.
    @Test("Every column is spoken, including empty ones")
    func everyColumnIsSpoken() {
        let days = IncidentHistory.days(for: [], range: .week, now: now)
        #expect(days.allSatisfy { $0.accessibilityLabel.contains("0 incidents") })
    }
}

@Suite("Incident list carries lifecycle findings")
struct IncidentLifecycleEntryTests {
    private func pattern(daysAgo: Double) -> RelaunchPattern {
        let first = now.addingTimeInterval(-daysAgo * 86_400)
        return RelaunchPattern(
            command: "Final Cut Pro", exits: 3, firstAt: first,
            lastAt: first.addingTimeInterval(720), confidence: .moderate)
    }

    /// Design 1f, row four: a repeated-quit finding sits in the same list as a
    /// resource incident rather than in a separate surface.
    @Test("Repeated quits appear alongside resource incidents, in time order")
    func lifecycleSitsInTheSameList() {
        let entries = IncidentHistory.entries(
            open: nil, recent: [incident(daysAgo: 3)],
            relaunches: [pattern(daysAgo: 1)], range: .week, now: now)

        #expect(entries.count == 2)
        if case .repeatedQuits(let first) = entries[0].kind {
            #expect(first.command == "Final Cut Pro")
        } else {
            Issue.record("the more recent lifecycle finding should sort first")
        }
    }

    @Test("A lifecycle finding counts towards the pattern summary")
    func lifecycleCountsInTheSummary() {
        let entries = IncidentHistory.entries(
            open: nil, recent: [], relaunches: [
                pattern(daysAgo: 1), pattern(daysAgo: 2), pattern(daysAgo: 3),
            ], range: .week, now: now)

        let summary = IncidentHistory.pattern(for: entries, range: .week)
        #expect(summary.headline == "3 incidents in the last 7 days")
        #expect(summary.recurrence == "Repeated unexpected quits in 3 of them")
    }

    @Test("A lifecycle finding is scoped by the range like any other")
    func lifecycleRespectsTheRange() {
        let entries = IncidentHistory.entries(
            open: nil, recent: [], relaunches: [pattern(daysAgo: 20)],
            range: .week, now: now)
        #expect(entries.isEmpty)
    }
}

@Suite("Incident retention and local-only wording")
@MainActor
struct IncidentRetentionTests {
    /// FR-029, and TASK-72's decision. History now persists for 30 days by default,
    /// so the design's "kept for 30 days" is finally a claim we can support — but
    /// only alongside the count bound, which is the other half of what is actually
    /// kept. A footer naming one bound would promise storage we do not provide.
    ///
    /// This test previously asserted the opposite, that the footer must *not* say
    /// "30 days". It changed with the behaviour, not before it.
    @Test("The footer states both bounds, where the file is, and that it stays local")
    func footerStatesWhatIsActuallyKept() {
        let text = IncidentHistory.retentionFooter(
            limit: MonitorStore.retainedIncidents, retention: .thirtyDays)
        #expect(text.contains("30 days"))
        #expect(text.contains("\(MonitorStore.retainedIncidents) most recent"))
        #expect(text.contains("this Mac"))
        #expect(text.contains("no other app can read"))
        #expect(text.contains("unless you export"))
        // FileVault is the user's setting and NSFileProtection is not what the word
        // implies. We never claim it.
        #expect(!text.lowercased().contains("encrypt"))
    }

    /// The stated period follows the setting. If it did not, the interface could
    /// promise a retention the store is not applying, which is precisely what
    /// FR-029 forbids.
    @Test("The footer's period is the one the user chose")
    func footerFollowsTheSetting() {
        for retention in PrivacySettings.Retention.allCases {
            let text = IncidentHistory.retentionFooter(
                limit: MonitorStore.retainedIncidents, retention: retention)
            #expect(text.contains(retention.label))
        }
    }

    @Test("The screen explains why a closed incident names no application")
    func attributionGapIsStated() {
        #expect(IncidentHistory.attributionGap.contains("does not record"))
    }
}
