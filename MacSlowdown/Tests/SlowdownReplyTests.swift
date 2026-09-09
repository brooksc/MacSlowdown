import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

// MARK: - Fixtures

private let calendar = Calendar(identifier: .gregorian)

private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(
        year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func samples(endingAt end: Date, count: Int) -> [HistorySample] {
    (0..<count).map { step in
        HistorySample(
            timestamp: end.addingTimeInterval(-Double(count - 1 - step)),
            totalBusyPercentOfOneCore: 120 + Double(step),
            attributedPercentOfOneCore: 80, unattributedPercentOfOneCore: 40,
            topContributors: [])
    }
}

private func report(
    at moment: Date = date(day: 3, hour: 14, minute: 41),
    timing: SlowdownReportTiming = .now,
    retained: [HistorySample] = [],
    conditions: Set<IncidentCondition> = []
) -> SlowdownReport {
    SlowdownReport.make(
        timing: timing, reportedAt: moment,
        retainedSamples: retained, conditionsInForce: conditions)
}

/// Every sentence the reply, the picker and the list can put on screen.
private func everySentence() -> [String] {
    let moment = date(day: 3, hour: 14, minute: 41)
    let covered = report(at: moment, retained: samples(endingAt: moment, count: 14))
    var texts = [
        SlowdownReportPresentation.nothingUnusual,
        SlowdownReportPresentation.gestureCaption(),
        SlowdownReportPresentation.gestureHelp,
        SlowdownReportPresentation.pickerTitle,
        SlowdownReportPresentation.pickerSubtitle,
        SlowdownReportPresentation.pickerFooter,
        SlowdownReportPresentation.emptyList,
        SlowdownReportPresentation.storageAssurance,
        SlowdownReportPresentation.retentionNote,
        SlowdownReportPresentation.keepTitle,
        SlowdownReportPresentation.deleteTitle,
        SlowdownReportPresentation.reportNowTitle,
        SlowdownReportPresentation.reportEarlierTitle,
        SlowdownReportPresentation.acknowledgement(covered),
        SlowdownReportPresentation.acknowledgement(
            report(at: moment, conditions: [.memoryPressure, .cpuSaturation])),
        SlowdownReportPresentation.keptReadings(covered),
        SlowdownReportPresentation.keptReadings(report(at: moment)),
        SlowdownReportPresentation.keptReadings(
            report(at: moment, timing: .recently(secondsAgo: 7200),
                   retained: samples(endingAt: moment, count: 4))),
        SlowdownReportPresentation.listRow(covered),
        SlowdownReportPresentation.listTitle(3),
        SlowdownReportPresentation.seeAllTitle(3),
    ]
    let patterns: [SlowdownReportPattern] = [
        .sharedApplication(name: "Xcode", reports: 3),
        .sameTimeOfDay(earliestHour: 14, latestHour: 15, reports: 3, days: 2),
        .noneCoincidedWithDetection(reports: 3),
    ]
    texts += patterns.map(SlowdownReportPresentation.patternHeading)
    texts += patterns.map(SlowdownReportPresentation.patternDetail)
    texts += SlowdownReportPresentation.evidenceRows(
        for: covered, allReports: [covered], calendar: calendar).map(\.text)
    return texts
}

// MARK: - The three sentences 5d forbids

/// **The reply is the feature** (S-7, FR-064). A report that is stored and not
/// answered is the extractive failure the scenario names; a report answered badly
/// is worse, because each of the obvious answers tells the user something we are
/// not entitled to say. These three tests are the record of which sentences were
/// ruled out and why, so none of them can come back in a rewrite.
@MainActor
@Suite("The reply never says any of the three forbidden things (design 5d)")
struct ForbiddenReplyTests {
    /// "Nothing was wrong" contradicts the user from measurements that cannot
    /// support it. Our copy contains the phrase exactly once, inside "That doesn't
    /// mean nothing was wrong" — the refusal of the claim, not the claim — so this
    /// checks the assertion form rather than the words.
    @Test("Nothing asserts that nothing was wrong")
    func neverAssertsNothingWasWrong() {
        for text in everySentence() {
            let lowered = text.lowercased()
            guard let range = lowered.range(of: "nothing was wrong") else { continue }
            let before = lowered[lowered.startIndex..<range.lowerBound]
            #expect(before.hasSuffix("doesn't mean "),
                    "\"nothing was wrong\" asserted in: \(text)")
        }
        // And the settled sentence still carries the refusal, so the guard above
        // cannot be satisfied by deleting the clause.
        #expect(SlowdownReportPresentation.nothingUnusual
            .contains("doesn't mean nothing was wrong"))
    }

    /// "We couldn't find anything" is the softer form of the same claim: it still
    /// leaves the user having imagined it. The limitation is ours before it is
    /// theirs, and the copy has to say so in that order.
    @Test("Nothing says we could not find anything")
    func neverSaysWeCouldNotFindAnything() {
        let forbidden = ["couldn't find", "could not find", "didn't find",
                         "did not find", "found nothing", "no problems found",
                         "nothing to report", "you may have imagined"]
        for text in everySentence() {
            for phrase in forbidden {
                #expect(!text.lowercased().contains(phrase),
                        "\"\(phrase)\" in: \(text)")
            }
        }
        // The ordering that replaces it: our instruments first.
        #expect(SlowdownReportPresentation.nothingUnusual
            .contains("isn't something we can measure"))
    }

    /// "Thanks for the feedback" is extractive — it admits we did nothing with it
    /// and moves on. What replaces it is telling them what was kept.
    @Test("Nothing thanks the user for feedback")
    func neverThanksForFeedback() {
        let forbidden = ["thanks for", "thank you", "feedback", "we appreciate",
                         "your input", "submitted"]
        for text in everySentence() {
            for phrase in forbidden {
                #expect(!text.lowercased().contains(phrase),
                        "\"\(phrase)\" in: \(text)")
            }
        }
        // Instead: what was kept, and what it is for.
        #expect(SlowdownReportPresentation.keptReadings(
            report(at: date(day: 3, hour: 14, minute: 41),
                   retained: samples(endingAt: date(day: 3, hour: 14, minute: 41), count: 9)))
            .contains("compare against next time"))
    }
}

// MARK: - FR-063 and FR-038

@MainActor
@Suite("A report is the user's claim; our lines stay measurements (FR-063, FR-038)")
struct ReplyClaimSeparationTests {
    /// The only line permitted to say the Mac felt slow is the one attributed to
    /// the person who said it.
    @Test("Only the user's own row claims the Mac felt slow")
    func slowIsOnlyEverTheirs() {
        let moment = date(day: 3, hour: 14, minute: 41)
        let filed = report(at: moment, retained: samples(endingAt: moment, count: 12),
                           conditions: [.memoryPressure])
        let rows = SlowdownReportPresentation.evidenceRows(
            for: filed, allReports: [filed], calendar: calendar)
        for row in rows where row.text.lowercased().contains("slow") {
            #expect(row.isYours, "a measured row claims slowness: \(row.text)")
        }
        #expect(rows.contains { $0.isYours })
        #expect(rows.contains { !$0.isYours })
    }

    /// A condition being in force is not a confirmation that the user was right:
    /// the same reading is produced by work they started deliberately.
    @Test("A coincident condition is reported as a reading, not as agreement")
    func conditionIsNotAgreement() {
        let text = SlowdownReportPresentation.conditionsAcknowledgement([.memoryPressure])
        #expect(text.contains("memory pressure"))
        #expect(text.contains("marked separately"))
        for phrase in ["you were right", "confirms", "we saw it too", "proves"] {
            #expect(!text.lowercased().contains(phrase), "\"\(phrase)\" in: \(text)")
        }
    }

    /// Every comparison says what kind of claim it is. We can see the timing of
    /// what ran; we cannot measure what it cost.
    @Test("A comparison is offered as timing, never as a cause")
    func patternsClaimOnlyTiming() {
        let patterns: [SlowdownReportPattern] = [
            .sharedApplication(name: "Time Machine", reports: 3),
            .sameTimeOfDay(earliestHour: 14, latestHour: 15, reports: 3, days: 2),
            .noneCoincidedWithDetection(reports: 3),
        ]
        for pattern in patterns {
            let text = SlowdownReportPresentation.patternDetail(pattern)
            for phrase in ["caused", "because of", "responsible for", "to blame",
                           "was making", "slowed"] {
                #expect(!text.lowercased().contains(phrase), "\"\(phrase)\" in: \(text)")
            }
        }
        #expect(SlowdownReportPresentation.patternDetail(
            .sharedApplication(name: "Time Machine", reports: 3))
            .contains("never the cost of"))
    }

    /// The container is not encrypted, and this repo has banned the claim once
    /// already (design turn 4).
    @Test("Nothing claims the reports are encrypted")
    func neverClaimsEncryption() {
        for text in everySentence() {
            #expect(!text.lowercased().contains("encrypt"), "in: \(text)")
        }
        #expect(SlowdownReportPresentation.storageAssurance
            .contains("no other app can read"))
        #expect(SlowdownReportPresentation.storageAssurance.contains("Nothing is uploaded"))
    }
}

// MARK: - What was kept, said honestly

@MainActor
@Suite("The reply states what was kept, and no more (FR-002, FR-057)")
struct ReplyEvidenceTests {
    /// A report with nothing behind it says why. It never renders as an empty
    /// series or as a flat line at zero.
    @Test("Each coverage case has its own sentence and none of them invents readings")
    func coverageCasesAreDistinct() {
        let moment = date(day: 3, hour: 14, minute: 41)
        let nothingRetained = SlowdownReportPresentation.keptReadings(report(at: moment))
        let tooOld = SlowdownReportPresentation.keptReadings(
            report(at: moment, timing: .recently(secondsAgo: 7200),
                   retained: samples(endingAt: moment, count: 4)))
        #expect(nothingRetained != tooOld)
        // Both must say the report still counts: a window we cannot fill is the
        // ordinary outcome of a retrospective report, not a failed one.
        #expect(nothingRetained.contains("It still counts"))
        #expect(tooOld.contains("It still counts"))
        #expect(!nothingRetained.contains("0%"))
    }

    /// FR-057: a figure states its statistic and its interval, or it does not
    /// appear. A range with a reading count does; a bare percentage would not.
    @Test("The readings line names the range and how many readings it covers")
    func readingsLineStatesItsInterval() {
        let moment = date(day: 3, hour: 14, minute: 41)
        let filed = report(at: moment, retained: samples(endingAt: moment, count: 14))
        let line = SlowdownReportPresentation.readingsLine(for: filed)
        #expect(line?.contains("of one core") == true)
        #expect(line?.contains("14 readings") == true)
        // Nothing to state when nothing was kept.
        #expect(SlowdownReportPresentation.readingsLine(for: report(at: moment)) == nil)
    }

    /// "Third time this week" is arithmetic over the record, not a flourish.
    @Test("The count of reports this week is counted, and absent when there is one")
    func ordinalCountsTheRecord() {
        let now = date(day: 8, hour: 14)
        let latest = report(at: now)
        let earlier = [report(at: date(day: 7, hour: 14)),
                       report(at: date(day: 6, hour: 14))]
        #expect(SlowdownReportPresentation.ordinalThisWeek(
            for: latest, in: [latest] + earlier, calendar: calendar) == "third")
        #expect(SlowdownReportPresentation.ordinalThisWeek(
            for: latest, in: [latest], calendar: calendar) == nil)
        // Reports older than the week are not counted into it.
        let old = report(at: date(day: 1, hour: 14))
        #expect(SlowdownReportPresentation.ordinalThisWeek(
            for: latest, in: [latest, old], calendar: calendar) == nil)
    }
}

// MARK: - The picker (design 6d)

@MainActor
@Suite("The retrospective picker keeps the window its button promised (design 6d)")
struct RetrospectivePickerTests {
    /// 6d's footer is a testable claim: the record must never be vaguer than the
    /// button that made it. Each button's caption is computed by the same policy
    /// that files the report, so the two cannot drift.
    @Test("Each bucket shows the window the report will actually keep")
    func windowsMatchThePolicy() {
        let now = date(day: 3, hour: 12, minute: 44)
        let policy = SlowdownReportPolicy.default
        for choice in SlowdownReportPresentation.retrospectiveChoices(
            now: now, policy: policy) {
            let filed = SlowdownReport.make(
                timing: .recently(secondsAgo: choice.secondsAgo),
                reportedAt: now, policy: policy)
            let expected = "\(PopoverPresentation.shortTime(filed.evidence.window.start))–"
                + "\(PopoverPresentation.shortTime(filed.evidence.window.end))"
            #expect(choice.window == expected, "\(choice.title) promised \(choice.window)")
        }
    }

    @Test("Two fixed buckets, no form and no free-text time")
    func twoFixedBuckets() {
        let choices = SlowdownReportPresentation.retrospectiveChoices(
            now: date(day: 3, hour: 12, minute: 44))
        #expect(choices.count == 2)
        #expect(choices[0].secondsAgo < choices[1].secondsAgo)
    }

    /// An hour that has not happened yet is not offered, and just after midnight
    /// the row is absent rather than empty (FR-062).
    @Test("Earlier today offers only hours that have passed")
    func earlierTodayOffersPastHoursOnly() {
        let midMorning = date(day: 3, hour: 10, minute: 20)
        let hours = SlowdownReportPresentation.earlierTodayChoices(
            now: midMorning, calendar: calendar)
        #expect(hours.count == 10)
        #expect(hours.first?.id == 9)
        #expect(hours.last?.id == 0)
        #expect(SlowdownReportPresentation.earlierTodayChoices(
            now: date(day: 3, hour: 0, minute: 30), calendar: calendar).isEmpty)
    }

    /// The offsets are real: a report filed from the picker points at the hour the
    /// user chose, not at the moment they pressed the button.
    @Test("A chosen hour files a report pointing at that hour")
    func chosenHourIsRecorded() {
        let now = date(day: 3, hour: 15, minute: 5)
        let choice = SlowdownReportPresentation.earlierTodayChoices(
            now: now, calendar: calendar).first { $0.id == 11 }
        let filed = SlowdownReport.make(
            timing: .recently(secondsAgo: choice?.secondsAgo ?? 0), reportedAt: now)
        #expect(calendar.component(.hour, from: filed.experiencedAt) == 11)
        #expect(filed.timing.isRetrospective)
    }
}

// MARK: - The gesture is wired, and reversible

/// Serialized, and every store built with `evidenceDirectory: nil`. The report
/// store is a process-wide singleton — one file per launch, as the app has — so
/// two of these running at once would each see the other's reports, and a store
/// pointed at the real container would delete the developer's own evidence.
@MainActor
@Suite("Reporting and withdrawing reach the store (FR-064)", .serialized)
struct SlowdownReportWiringTests {
    /// The gesture has to reach the observable list, or the reply, the comparison
    /// and the list are all describing a record nobody can see.
    @Test("A report appears in the store's reports and can be withdrawn")
    func reportsAreObservableAndReversible() {
        let store = MonitorStore(evidenceDirectory: nil)
        let before = store.reportedSlowdowns.count
        let filed = store.reportSlowdown()
        #expect(store.reportedSlowdowns.count == before + 1)
        #expect(store.reportedSlowdowns.first?.id == filed.id)

        store.deleteReportedSlowdown(id: filed.id)
        #expect(!store.reportedSlowdowns.contains { $0.id == filed.id })
        #expect(store.reportedSlowdowns.count == before)
    }

    /// A retrospective report records the moment the user pointed at, not the
    /// moment they told us.
    @Test("A retrospective report is dated by the moment it points at")
    func retrospectiveIsDatedByItsMoment() {
        let store = MonitorStore(evidenceDirectory: nil)
        let now = Date()
        let filed = store.reportSlowdown(timing: .recently(secondsAgo: 1800), at: now)
        defer { store.deleteReportedSlowdown(id: filed.id) }
        #expect(abs(filed.experiencedAt.timeIntervalSince(now) + 1800) < 1)
        #expect(filed.reportedAt == now)
    }

    /// Deleting recorded history takes the reports with it, in memory as well as
    /// on disk — otherwise the next report writes them straight back.
    @Test("Delete all recorded history clears the reports too")
    func deleteAllClearsReports() {
        let store = MonitorStore(evidenceDirectory: nil)
        store.reportSlowdown()
        #expect(!store.reportedSlowdowns.isEmpty)
        store.deleteRecordedHistory()
        #expect(store.reportedSlowdowns.isEmpty)
    }
}
