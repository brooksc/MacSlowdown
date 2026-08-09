import Foundation
import Synchronization
import Testing

@testable import Metrics

// MARK: - Fixtures

private let pidCounter = Atomic<Int32>(50_000)

private func nextIdentity() -> ProcessIdentity {
    ProcessIdentity(
        pid: pidCounter.wrappingAdd(1, ordering: .relaxed).newValue,
        startTime: 1_700_000_000)
}

/// A family with a known CPU contribution, so the roll-up can be checked against a
/// number rather than against itself.
private func family(
    _ name: String,
    bundlePath: String?,
    processes: [Double],
    uncertain: Bool = false
) -> (family: ProcessFamily, usage: [ProcessCPUUsage]) {
    var members: [FamilyMember] = []
    var usage: [ProcessCPUUsage] = []
    for (index, percent) in processes.enumerated() {
        let identity = nextIdentity()
        let record = ProcessRecord(
            identity: identity, command: name, uid: 501, ppid: 1,
            metrics: .measured(ProcessMetrics(cpuTicks: 1, residentBytes: 1 << 20)))
        let resolved = ResolvedIdentity(
            executablePath: bundlePath.map { "\($0)/Contents/MacOS/\(name)" },
            appBundlePath: bundlePath, bundleID: "com.example.\(name)", teamID: "TEAM")
        members.append(FamilyMember(
            record: record, resolved: resolved,
            membership: uncertain && index == 0
                ? .uncertain(reason: "path only") : .certain))
        usage.append(ProcessCPUUsage(
            identity: identity, command: name, displayName: name,
            percentOfOneCore: percent, residentBytes: 1 << 20))
    }
    return (ProcessFamily(id: bundlePath ?? name, displayName: name,
                          bundlePath: bundlePath, members: members),
            usage)
}

private func attribution(
    _ families: [(family: ProcessFamily, usage: [ProcessCPUUsage])],
    total: Double? = nil,
    cores: Int = 8
) -> CPUAttribution {
    let contributors = families.flatMap(\.usage)
        .sorted { $0.percentOfOneCore > $1.percentOfOneCore }
    let attributed = contributors.reduce(0) { $0 + $1.percentOfOneCore }
    let totalBusy = max(total ?? attributed, attributed)
    return CPUAttribution(
        totalBusyPercentOfOneCore: totalBusy,
        attributedPercentOfOneCore: attributed,
        unattributedPercentOfOneCore: totalBusy - attributed,
        contributors: contributors,
        protectedProcesses: [],
        logicalCoreCount: cores)
}

private func sample(
    _ families: [(family: ProcessFamily, usage: [ProcessCPUUsage])],
    total: Double? = nil
) -> AttributionSample {
    AttributionSample.from(
        attribution: attribution(families, total: total), families: families.map(\.family))
}

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: - Rolling processes up to applications

@Suite("Attribution samples")
struct AttributionSampleTests {
    @Test("A family's processes are summed into one application")
    func rollsUpToApplication() {
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [120, 60, 20])
        let sampled = sample([chrome])

        #expect(sampled.applications.count == 1)
        #expect(sampled.applications.first?.displayName == "Chrome")
        #expect(sampled.applications.first?.peakPercentOfOneCore == 200)
    }

    /// PIDs are reused and a standalone family's id contains one, so a key built
    /// from it would make the same daemon look like a different application in
    /// every incident.
    @Test("A standalone process keys on its name, never on a PID")
    func standaloneKeyIsStable() {
        let daemon = family("mds_stores", bundlePath: nil, processes: [40])
        let key = sample([daemon]).applications.first?.applicationID

        #expect(key == "name:mds_stores")
        #expect(key?.contains("pid:") == false)
    }

    @Test("Applications with no measurable CPU are left out, not recorded as zero")
    func zeroIsOmitted() {
        let idle = family("Idle", bundlePath: "/Applications/Idle.app", processes: [0])
        #expect(sample([idle]).applications.isEmpty)
    }

    @Test("Retained applications are bounded")
    func bounded() {
        let many = (0..<12).map {
            family("App\($0)", bundlePath: "/Applications/App\($0).app",
                   processes: [Double(100 - $0)])
        }
        #expect(sample(many).applications.count == IncidentAttribution.retainedApplications)
        #expect(sample(many).applications.first?.displayName == "App0")
    }

    @Test("An uncertain grouping is carried, not flattened away")
    func uncertaintyTravels() {
        let odd = family("Suspect", bundlePath: "/Applications/Suspect.app",
                         processes: [50], uncertain: true)
        #expect(sample([odd]).applications.first?.hasUncertainMembers == true)
    }
}

// MARK: - What an incident records

@Suite("Incident attribution")
struct IncidentAttributionTests {
    private func openIncident(
        _ sampled: AttributionSample?, at date: Date = origin
    ) -> (IncidentDetector, IncidentDetector.State) {
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        var observation = SystemObservation(at: date, cpuBusyFraction: 0.95)
        observation.attribution = sampled
        _ = detector.observe(observation, state: &state)
        var later = SystemObservation(
            at: date.addingTimeInterval(200), cpuBusyFraction: 0.95)
        later.attribution = sampled
        _ = detector.observe(later, state: &state)
        return (detector, state)
    }

    @Test("An incident is created with the applications it was attributed to")
    func recordedOnOpen() {
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [400])
        let (_, state) = openIncident(sample([chrome], total: 500))

        let recorded = try! #require(state.current?.attribution)
        #expect(recorded.leadingApplication?.displayName == "Chrome")
        #expect(recorded.peakTotalBusyPercentOfOneCore == 500)
        #expect(recorded.logicalCoreCount == 8)
    }

    @Test("Nothing is recorded when no attribution was offered")
    func absentRatherThanInvented() {
        let (_, state) = openIncident(nil)
        #expect(state.current?.attribution == nil)
    }

    @Test("Peaks accumulate while the incident stays open")
    func staysCurrentWhileOpen() {
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        let low = family("Xcode", bundlePath: "/Applications/Xcode.app", processes: [100])
        let high = family("Xcode", bundlePath: "/Applications/Xcode.app", processes: [700])

        for (offset, sampled) in [sample([low], total: 200), sample([low], total: 200),
                                  sample([high], total: 800), sample([low], total: 200)]
            .enumerated() {
            var observation = SystemObservation(
                at: origin.addingTimeInterval(Double(offset) * 200),
                cpuBusyFraction: 0.95)
            observation.attribution = sampled
            _ = detector.observe(observation, state: &state)
        }

        let recorded = try! #require(state.current?.attribution)
        #expect(recorded.leadingApplication?.peakPercentOfOneCore == 700,
                "the peak must survive a later quieter sample")
        #expect(recorded.peakTotalBusyPercentOfOneCore == 800)
        #expect(recorded.attributedPercentOfOneCoreAtPeak == 700,
                "the totals must come from one coherent sample, not from three maxima")
    }

    /// The whole point of the task: a closed incident answers from what it
    /// recorded, with no live reading involved.
    @Test("A closed incident still names the application, with no live state")
    func survivesClosing() {
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [400])
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        var busy = SystemObservation(at: origin, cpuBusyFraction: 0.95)
        busy.attribution = sample([chrome], total: 500)
        _ = detector.observe(busy, state: &state)
        var stillBusy = SystemObservation(
            at: origin.addingTimeInterval(200), cpuBusyFraction: 0.95)
        stillBusy.attribution = sample([chrome], total: 500)
        _ = detector.observe(stillBusy, state: &state)

        var closed: Incident?
        for offset in [400.0, 500.0] {
            let quiet = SystemObservation(
                at: origin.addingTimeInterval(offset), cpuBusyFraction: 0.1)
            if case .closed(let incident) = detector.observe(quiet, state: &state) {
                closed = incident
            }
        }

        let incident = try! #require(closed)
        #expect(incident.attribution?.leadingApplication?.displayName == "Chrome")

        // Live attribution says something entirely different by now, and must not
        // be able to change the story.
        let other = family("Mail", bundlePath: "/Applications/Mail.app", processes: [900])
        let summary = IncidentSummarizer.summarize(
            incident: incident, attribution: attribution([other]))
        #expect(summary.hypotheses.contains { $0.text.contains("Chrome") })
        #expect(!summary.hypotheses.contains { $0.text.contains("Mail") })
    }

    @Test("The recorded name is always a heuristic and always carries a confidence")
    func labelledAsHeuristic() {
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [400])
        let recorded = IncidentAttribution(sample: sample([chrome], total: 500), at: origin)

        #expect(recorded.evidence == .heuristic)
        let conclusion = try! #require(recorded.conclusion)
        #expect(conclusion.evidence == .heuristic)
        #expect(conclusion.confidence != nil)
        #expect(conclusion.isWellFormed)
        #expect(!conclusion.text.contains("caused"))
    }

    @Test("Confidence drops when most activity is unattributable, and stays dropped")
    func confidenceIsRecordedNotRecomputed() {
        let small = family("Chrome", bundlePath: "/Applications/Chrome.app",
                           processes: [50])
        // 50 attributed of 500 busy: 90% unattributable.
        var recorded = IncidentAttribution(sample: sample([small], total: 500), at: origin)
        #expect(recorded.confidence == .low)

        // A later, calmer, fully-attributed sample must not raise the confidence of
        // the busiest moment already recorded.
        let clean = family("Chrome", bundlePath: "/Applications/Chrome.app",
                           processes: [90])
        recorded.merge(sample([clean], total: 100), at: origin.addingTimeInterval(60))
        #expect(recorded.confidence == .low)
    }

    @Test("The caveat appears when a large share could not be attributed")
    func caveatWhenUnattributable() {
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [100])
        let recorded = IncidentAttribution(sample: sample([chrome], total: 500), at: origin)
        #expect(recorded.conclusion?.text.contains("only the largest we could see") == true)
    }

    @Test("Recorded figures sum")
    func figuresSum() {
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [300])
        let recorded = IncidentAttribution(sample: sample([chrome], total: 500), at: origin)
        #expect(recorded.attributedPercentOfOneCoreAtPeak
                + recorded.unattributedPercentOfOneCoreAtPeak
                == recorded.peakTotalBusyPercentOfOneCore)
    }

    @Test("Refreshing the attribution does not re-announce the incident")
    func mergingEmitsNoEvent() {
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        let chrome = family("Chrome", bundlePath: "/Applications/Chrome.app",
                            processes: [100])

        var first = SystemObservation(at: origin, cpuBusyFraction: 0.95)
        first.attribution = sample([chrome], total: 200)
        _ = detector.observe(first, state: &state)
        var second = SystemObservation(
            at: origin.addingTimeInterval(200), cpuBusyFraction: 0.95)
        second.attribution = sample([chrome], total: 200)
        #expect(detector.observe(second, state: &state) != nil, "this one opens it")

        var third = SystemObservation(
            at: origin.addingTimeInterval(210), cpuBusyFraction: 0.9)
        third.attribution = sample([chrome], total: 300)
        #expect(detector.observe(third, state: &state) == nil,
                "a fresher attribution is not a change the user should be told about")
        #expect(state.current?.attribution?.peakTotalBusyPercentOfOneCore == 300)
    }
}

// MARK: - Recurrence across incidents

@Suite("Application recurrence")
struct ApplicationRecurrenceTests {
    private func closed(_ leader: String, total: Double = 500) -> Incident {
        let app = family(leader, bundlePath: "/Applications/\(leader).app",
                         processes: [total * 0.9])
        var incident = Incident(
            id: UUID(), beganAt: origin, triggeredAt: origin, recoveryStartedAt: nil,
            closedAt: origin.addingTimeInterval(300), conditions: [.cpuSaturation],
            severity: .high, peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
        incident.attribution = IncidentAttribution(
            sample: sample([app], total: total), at: origin)
        return incident
    }

    @Test("An application that leads repeatedly is reported by name")
    func counted() {
        let incidents = [closed("Chrome"), closed("Chrome"), closed("Xcode"),
                         closed("Chrome"), closed("Mail")]
        let recurring = IncidentRecurrence.leadingApplications(in: incidents)

        #expect(recurring.count == 1)
        #expect(recurring.first?.displayName == "Chrome")
        #expect(recurring.first?.incidentCount == 3)
        #expect(recurring.first?.attributedIncidentCount == 5)
        #expect(recurring.first?.conclusion.evidence == .heuristic)
        #expect(recurring.first?.conclusion.confidence != nil)
    }

    @Test("No pattern is claimed from too few incidents")
    func gated() {
        #expect(IncidentRecurrence.leadingApplications(
            in: [closed("Chrome"), closed("Chrome")]).isEmpty)
        #expect(IncidentRecurrence.leadingApplications(
            in: [closed("Chrome"), closed("Chrome"), closed("Xcode")]).isEmpty,
            "two of three is not three of three")
    }

    @Test("Incidents with nothing recorded are counted in neither half")
    func unattributedIgnored() {
        var blank = closed("Chrome")
        blank.attribution = nil
        let recurring = IncidentRecurrence.leadingApplications(
            in: [closed("Chrome"), closed("Chrome"), closed("Chrome"), blank])

        #expect(recurring.first?.attributedIncidentCount == 3,
                "an incident we could not attribute is not evidence either way")
    }

    /// Two low-confidence records must not average into a confident-looking claim.
    @Test("Recurrence carries the weakest confidence it was built from")
    func weakestConfidenceWins() {
        var weak = closed("Chrome")
        // 90 attributed of 900 busy: mostly unattributable, so low confidence.
        let app = family("Chrome", bundlePath: "/Applications/Chrome.app",
                         processes: [90])
        weak.attribution = IncidentAttribution(
            sample: sample([app], total: 900), at: origin)
        #expect(weak.attribution?.confidence == .low)

        let recurring = IncidentRecurrence.leadingApplications(
            in: [closed("Chrome"), closed("Chrome"), weak])
        #expect(recurring.first?.confidence == .low)
    }
}

// MARK: - Actions and suppressions linked to an incident

@Suite("Incident outcome")
struct IncidentOutcomeTests {
    private func incident(closedAt: Date? = origin.addingTimeInterval(600)) -> Incident {
        Incident(
            id: UUID(), beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
            recoveryStartedAt: nil, closedAt: closedAt, conditions: [.cpuSaturation],
            severity: .high, peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
    }

    private func verification(
        at date: Date, result: ActionResult = .succeeded
    ) -> ActionVerification {
        ActionVerifier.verify(
            action: .activate, target: "Chrome", result: result,
            before: 0.9, after: 0.3, window: .seconds(60), requestedAt: date)
    }

    @Test("An open incident is open, whatever else happened")
    func openIsOpen() {
        var open = incident(closedAt: nil)
        let linked = open.record(verification(at: origin.addingTimeInterval(300)))
        #expect(linked)
        #expect(open.outcome == .open)
    }

    @Test("A recovery with nothing recorded says so, rather than guessing")
    func recoveredWithoutAction() {
        #expect(incident().outcome == .recovered)
        #expect(incident().outcome.statement.text.contains("no action was recorded"))
        #expect(incident().outcome.statement.evidence == .measured)
    }

    @Test("An action inside the window is linked")
    func actionLinked() {
        var subject = incident()
        let linked = subject.record(verification(at: origin.addingTimeInterval(300)))
        #expect(linked)
        #expect(subject.actions.count == 1)
        if case .recoveredAfterRecordedAction = subject.outcome {} else {
            Issue.record("expected the recorded action to be the outcome")
        }
        #expect(subject.outcome.statement.text.contains("Recovered after you used"))
    }

    /// FR-050: the outcome is never read out of the fact that things got better.
    @Test("An action outside the window is refused, however well the timing fits")
    func timingIsNotEvidence() {
        var before = incident()
        let tooEarly = before.record(verification(at: origin.addingTimeInterval(-10)))
        var after = incident()
        let tooLate = after.record(verification(at: origin.addingTimeInterval(9999)))
        #expect(!tooEarly)
        #expect(!tooLate)
        #expect(before.outcome == .recovered)
        #expect(after.outcome == .recovered)
        #expect(before.actions.isEmpty && after.actions.isEmpty)
    }

    @Test("An action that did not run is not an action taken")
    func withheldActionIsNotLinked() {
        var subject = incident()
        let withheld = subject.record(verification(
            at: origin.addingTimeInterval(300),
            result: .withheld(reason: "not a foreground application")))
        let failed = subject.record(verification(
            at: origin.addingTimeInterval(300), result: .failed(reason: "macOS refused")))
        #expect(!withheld)
        #expect(!failed)
        #expect(subject.outcome == .recovered)
    }

    @Test("A suppressed detection says why the user was not told")
    func suppressionLinked() {
        var subject = incident()
        let suppression = SuppressedDetection(
            application: "Xcode", classification: .expected,
            at: origin.addingTimeInterval(200), severity: .high,
            incidentID: subject.id)
        let linked = subject.record(suppression)
        #expect(linked)

        if case .notAlerted = subject.outcome {} else {
            Issue.record("expected the suppression to be the outcome")
        }
        #expect(subject.outcome.statement.evidence == .userProvided,
                "the reason is something the user told us, not something we measured")
        #expect(subject.outcome.statement.text.contains("Xcode"))
        #expect(subject.outcome.statement.text.contains("still recorded"))
    }

    @Test("A suppression outside the window belongs to no incident")
    func suppressionWindowed() {
        var subject = incident()
        let linked = subject.record(SuppressedDetection(
            application: "Xcode", classification: .ignored,
            at: origin.addingTimeInterval(-60), severity: .high))
        #expect(!linked)
    }

    @Test("The policy store can find the suppressions of one incident")
    func auditTrailJoinsBack() {
        let store = PolicyStore()
        let mine = UUID()
        store.recordSuppression(SuppressedDetection(
            application: "Xcode", classification: .expected, severity: .high,
            incidentID: mine))
        store.recordSuppression(SuppressedDetection(
            application: "Mail", classification: .ignored, severity: .moderate,
            incidentID: UUID()))
        store.recordSuppression(SuppressedDetection(
            application: "Loose", classification: .ignored, severity: .moderate))

        #expect(store.suppressedDetections(forIncident: mine).count == 1)
        #expect(store.suppressedDetections(forIncident: mine).first?.application == "Xcode")
        #expect(store.suppressedDetections.count == 3, "the full trail is still complete")
    }
}
