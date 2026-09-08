import Foundation
import Testing

@testable import Metrics

// MARK: - Fixtures

private func samples(from start: Date, count: Int, every seconds: Double = 1) -> [HistorySample] {
    (0..<count).map { step in
        HistorySample(
            timestamp: start.addingTimeInterval(Double(step) * seconds),
            totalBusyPercentOfOneCore: 100 + Double(step),
            attributedPercentOfOneCore: 60,
            unattributedPercentOfOneCore: 40,
            topContributors: [
                ContributorSummary(pid: 4242, startTime: 99_001, command: "Xcode",
                                   percentOfOneCore: 60, residentBytes: 1_000_000)
            ])
    }
}

private func attributionSample(leader: Double = 300) -> AttributionSample {
    AttributionSample(
        applications: [
            IncidentContributor(applicationID: "/Applications/Xcode.app",
                                displayName: "Xcode",
                                bundleID: "com.apple.dt.Xcode",
                                bundlePath: "/Applications/Xcode.app",
                                peakPercentOfOneCore: leader)
        ],
        totalBusyPercentOfOneCore: 500,
        attributedPercentOfOneCore: 400,
        unattributedPercentOfOneCore: 100,
        logicalCoreCount: 8)
}

private func incident(from began: Date, to closed: Date?,
                      attribution: IncidentAttribution? = nil) -> Incident {
    var incident = Incident(
        id: UUID(),
        beganAt: began,
        triggeredAt: began.addingTimeInterval(180),
        recoveryStartedAt: nil,
        closedAt: closed,
        conditions: [.cpuSaturation],
        severity: .high,
        peakCPUBusyFraction: 0.93,
        peakMemoryPressure: .normal)
    incident.attribution = attribution
    return incident
}

// MARK: - Timing

@Suite("A report says which moment it is about")
struct SlowdownReportTimingTests {
    @Test("A report made now is about now")
    func nowIsNow() {
        let at = Date()
        #expect(SlowdownReportTiming.now.experiencedAt(reportedAt: at) == at)
        #expect(!SlowdownReportTiming.now.isRetrospective)
    }

    /// FR-064 requires the retrospective case: people often only think to tell us
    /// once the machine has come back.
    @Test("A retrospective report is about the earlier moment, not the gesture")
    func retrospectiveLooksBack() {
        let at = Date()
        let timing = SlowdownReportTiming.recently(secondsAgo: 300)
        #expect(timing.experiencedAt(reportedAt: at) == at.addingTimeInterval(-300))
        #expect(timing.isRetrospective)
    }

    /// A negative offset would put the reported moment in the future, where nothing
    /// has been sampled. Taken as magnitude rather than trusted.
    @Test("A negative offset still looks backwards")
    func negativeOffsetLooksBackwards() {
        let at = Date()
        #expect(SlowdownReportTiming.recently(secondsAgo: -120)
            .experiencedAt(reportedAt: at) == at.addingTimeInterval(-120))
    }

    @Test("The window of a report made now does not extend past now")
    func windowStopsAtNow() {
        let at = Date()
        let window = SlowdownReportPolicy.default.window(around: at, reportedAt: at)
        #expect(window.end == at)
        #expect(window.start == at.addingTimeInterval(-180))
    }

    @Test("A retrospective window has evidence on both sides of the moment")
    func retrospectiveWindowIsTwoSided() {
        let at = Date()
        let moment = at.addingTimeInterval(-600)
        let window = SlowdownReportPolicy.default.window(around: moment, reportedAt: at)
        #expect(window.start == moment.addingTimeInterval(-180))
        #expect(window.end == moment.addingTimeInterval(60))
    }
}

// MARK: - Evidence

@Suite("A report keeps the evidence around it")
struct SlowdownReportEvidenceTests {
    @Test("Retained samples inside the window are kept, and ones outside are not")
    func keepsTheWindow() {
        let now = Date()
        // 600 s of history ending now, one sample every 10 s, so the 180 s window
        // holds 19 of them and the rest are outside it.
        let history = samples(from: now.addingTimeInterval(-600), count: 61, every: 10)
        let report = SlowdownReport.make(timing: .now, reportedAt: now,
                                         retainedSamples: history)

        #expect(report.evidence.samples.count == 19)
        #expect(report.evidence.observedSampleCount == 19)
        #expect(!report.evidence.samplesWereThinned)
        #expect(report.evidence.samples.allSatisfy {
            report.evidence.window.contains($0.timestamp)
        })
        guard case .retained(let from, let to) = report.evidence.coverage else {
            Issue.record("expected retained coverage")
            return
        }
        #expect(from == report.evidence.samples.first?.timestamp)
        #expect(to == report.evidence.samples.last?.timestamp)
    }

    /// FR-002 applied to our own evidence: a report with nothing behind it says so,
    /// rather than presenting an empty series as a measurement of a quiet machine.
    @Test("A report with no retained history records why, not an empty series")
    func noHistoryIsNamed() {
        let report = SlowdownReport.make(timing: .now, reportedAt: Date(), retainedSamples: [])
        #expect(report.evidence.samples.isEmpty)
        #expect(report.evidence.coverage == .noHistoryRetained)
        #expect(!report.evidence.coverage.hasSamples)
        #expect(report.evidence.observedSampleCount == 0)
    }

    @Test("A retrospective report older than the rolling buffer says so")
    func windowOlderThanHistory() {
        let now = Date()
        let history = samples(from: now.addingTimeInterval(-60), count: 60)
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: 3600), reportedAt: now, retainedSamples: history)
        #expect(report.evidence.coverage == .windowOlderThanRetainedHistory)
        #expect(report.evidence.samples.isEmpty)
    }

    /// Monitoring that stopped and started leaves a hole. That is a different fact
    /// from a buffer that never reached back far enough.
    @Test("A gap in the middle of retained history is a gap, not an empty buffer")
    func gapInHistory() {
        let now = Date()
        let old = samples(from: now.addingTimeInterval(-1800), count: 30)
        let recent = samples(from: now.addingTimeInterval(-30), count: 30)
        let report = SlowdownReport.make(
            timing: .recently(secondsAgo: 900), reportedAt: now,
            retainedSamples: old + recent)
        #expect(report.evidence.coverage == .noSamplesInWindow)
    }

    @Test("A long window is thinned to the bound, and says it was thinned")
    func thinningIsBounded() {
        let now = Date()
        let history = samples(from: now.addingTimeInterval(-180), count: 181)
        let policy = SlowdownReportPolicy(leadIn: .seconds(180), trailing: .zero,
                                          maximumSamples: 20)
        let report = SlowdownReport.make(timing: .now, reportedAt: now, policy: policy,
                                         retainedSamples: history)

        #expect(report.evidence.samples.count <= 20)
        #expect(report.evidence.observedSampleCount > report.evidence.samples.count)
        #expect(report.evidence.samplesWereThinned)
        // Every kept sample is one that was actually taken — nothing is averaged
        // into a synthetic point (FR-002).
        let taken = Set(history.map(\.timestamp))
        #expect(report.evidence.samples.allSatisfy { taken.contains($0.timestamp) })
        // The ends survive, so the series still spans what it claims to span.
        #expect(report.evidence.samples.first?.timestamp
            == history.first(where: { report.evidence.window.contains($0.timestamp) })?.timestamp)
        #expect(report.evidence.samples.last?.timestamp == history.last?.timestamp)
    }

    @Test("Contributors keep (pid, start time), so a recycled PID stays distinct")
    func contributorsCarryIdentity() {
        let now = Date()
        let report = SlowdownReport.make(
            timing: .now, reportedAt: now,
            retainedSamples: samples(from: now.addingTimeInterval(-10), count: 10))
        let contributor = try? #require(report.evidence.samples.first?.topContributors.first)
        #expect(contributor?.pid == 4242)
        #expect(contributor?.startTime == 99_001)
    }
}

// MARK: - Coincidence with what we detected

@Suite("A report is matched against what we detected, and may match nothing")
struct SlowdownReportCoincidenceTests {
    /// **The case the feature exists for.** A slowdown the user experienced while
    /// nothing we watch had crossed a line is a first-class result, not an error,
    /// and it must be recorded as fully as one that matched.
    @Test("A report matching no condition and no incident is preserved as a result")
    func noCoincidentConditionIsAResult() {
        let now = Date()
        let report = SlowdownReport.make(
            timing: .now, reportedAt: now,
            retainedSamples: samples(from: now.addingTimeInterval(-60), count: 60),
            incidents: [],
            conditionsInForce: [])

        #expect(!report.coincidedWithDetection)
        #expect(report.evidence.incidentID == nil)
        #expect(report.evidence.conditionsInForce.isEmpty)
        #expect(report.evidence.attribution == nil)
        #expect(report.evidence.attributionOrigin == nil)
        // The evidence is kept in full regardless — this is the informative case.
        #expect(report.evidence.coverage.hasSamples)
        #expect(report.evidenceClass == .userProvided)
    }

    @Test("A condition in force with no open incident still counts as detection")
    func conditionWithoutIncidentCounts() {
        let report = SlowdownReport.make(
            timing: .now, reportedAt: Date(), conditionsInForce: [.memoryPressure])
        #expect(report.coincidedWithDetection)
        #expect(report.evidence.conditionsInForce == [.memoryPressure])
        #expect(report.evidence.incidentID == nil)
    }

    @Test("An incident covering the moment is linked, with its recorded attribution")
    func linksTheCoveringIncident() {
        let now = Date()
        let recorded = IncidentAttribution(sample: attributionSample(), at: now)
        let open = incident(from: now.addingTimeInterval(-600), to: nil, attribution: recorded)
        let report = SlowdownReport.make(
            timing: .now, reportedAt: now, incidents: [open],
            conditionsInForce: [.cpuSaturation],
            liveAttribution: attributionSample(leader: 10))

        #expect(report.evidence.incidentID == open.id)
        #expect(report.evidence.attributionOrigin == .recordedIncident)
        #expect(report.evidence.attribution?.leadingApplication?.peakPercentOfOneCore == 300)
        #expect(report.coincidedWithDetection)
    }

    /// An episode that closed a minute ago overlaps the window but did not cover the
    /// moment. It is still linked — the user is plainly describing the same episode
    /// — but an incident that covers the moment wins where both exist.
    @Test("A covering incident beats one that merely overlaps the window")
    func coveringBeatsOverlapping() {
        let now = Date()
        let closed = incident(from: now.addingTimeInterval(-900),
                              to: now.addingTimeInterval(-120))
        let covering = incident(from: now.addingTimeInterval(-60), to: nil)
        #expect(SlowdownReport.make(timing: .now, reportedAt: now,
                                    incidents: [closed, covering]).evidence.incidentID
            == covering.id)
        #expect(SlowdownReport.make(timing: .now, reportedAt: now,
                                    incidents: [closed]).evidence.incidentID == closed.id)
    }

    /// An attribution sampled at the moment of the gesture is one instant, not an
    /// episode, and the record has to say which it is (FR-038, FR-065).
    @Test("Attribution taken at report time is labelled as such")
    func liveAttributionIsLabelled() {
        let report = SlowdownReport.make(
            timing: .now, reportedAt: Date(), liveAttribution: attributionSample())
        #expect(report.evidence.attributionOrigin == .sampledAtReport)
        #expect(report.evidence.attribution?.leadingApplication?.displayName == "Xcode")
    }

    @Test("Overlap counts separate reports we detected from reports we missed")
    func overlapCounts() {
        let now = Date()
        let detected = SlowdownReport.make(timing: .now, reportedAt: now,
                                           conditionsInForce: [.cpuSaturation])
        let missed = SlowdownReport.make(timing: .now, reportedAt: now)
        let overlap = SlowdownDetectionOverlap(reports: [detected, missed, missed])
        #expect(overlap.reports == 3)
        #expect(overlap.coincidingWithDetection == 1)
        #expect(overlap.withoutDetection == 2)
    }
}
