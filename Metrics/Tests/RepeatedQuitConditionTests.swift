import Foundation
import Testing

@testable import Metrics

/// The lifecycle incident condition (TASK-71, FR-011, FR-045, FR-046).
///
/// The premise these tests defend is the one the design screen was built on and the
/// product could not reach: **an application failing while the machine is fine.**
/// Every observation below is deliberately quiet — 5% of the machine busy, normal
/// pressure, nominal thermals, plenty of disk — so nothing here can be passing
/// because a resource threshold happened to be crossed as well.

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

private func pattern(
    _ command: String = "Photocopier",
    exits: Int = 3,
    from: TimeInterval,
    to: TimeInterval,
    confidence: Confidence = .moderate
) -> RelaunchPattern {
    RelaunchPattern(
        command: command, exits: exits,
        firstAt: at(from), lastAt: at(to), confidence: confidence)
}

/// A machine with nothing whatever wrong with it.
private func calm(_ seconds: TimeInterval, findings: [RelaunchPattern] = []) -> SystemObservation {
    SystemObservation(
        at: at(seconds), cpuBusyFraction: 0.05, memoryPressure: .normal,
        thermalState: .nominal, lowStorage: false, lifecycleFindings: findings)
}

private func run(
    _ observations: [SystemObservation], policy: IncidentPolicy = .default
) -> [IncidentEvent] {
    let detector = IncidentDetector(policy: policy)
    var state = IncidentDetector.State()
    return observations.compactMap { detector.observe($0, state: &state) }
}

private func opened(_ events: [IncidentEvent]) -> [Incident] {
    events.compactMap { if case .opened(let incident) = $0 { incident } else { nil } }
}

private func closed(_ events: [IncidentEvent]) -> [Incident] {
    events.compactMap { if case .closed(let incident) = $0 { incident } else { nil } }
}

@Suite("A repeated-quit episode opens an incident of its own")
struct RepeatedQuitConditionTests {
    /// The whole point of TASK-71. Before it, this sequence produced nothing at all.
    @Test("A relaunch pattern opens an incident with no resource condition breached")
    func patternOpensAnIncident() throws {
        let events = run([
            calm(0),
            calm(60, findings: [pattern(from: 0, to: 50)]),
        ])
        let incident = try #require(opened(events).first)
        #expect(incident.conditions == [.repeatedApplicationQuits])
        #expect(incident.conditions.allSatisfy { !$0.isResourceCondition })
        #expect(incident.peakCPUBusyFraction < 0.1, "this must not be a CPU incident")
    }

    /// FR-006. `LifecycleTracker.minimumExits` is the threshold, and it is upstream:
    /// one exit never becomes a `RelaunchPattern`, so the detector is never offered
    /// one and no incident can open.
    @Test("A single unexpected quit is not an incident")
    func oneQuitIsNotAnIncident() {
        let tracker = LifecycleTracker()
        let identity = ProcessIdentity(pid: 501, startTime: 1)
        let single: [LifecycleEvent] = [
            .exited(identity: identity, command: "Photocopier", at: at(10))
        ]
        let patterns = tracker.relaunchPatterns(in: single, now: at(60))
        #expect(patterns.isEmpty, "one exit became a pattern")

        // And with no pattern, nothing opens — through the detector, not by assertion.
        #expect(run([calm(0), calm(60, findings: patterns)]).isEmpty)
    }

    /// Two exits are still not a pattern. The default threshold is three, and this
    /// records the number rather than leaving it to a constant nobody re-reads.
    @Test("Two exits are below the threshold; three are the threshold")
    func thresholdIsThreeExits() {
        let tracker = LifecycleTracker()
        #expect(tracker.minimumExits == 3)

        func exits(_ count: Int) -> [LifecycleEvent] {
            (0..<count).map {
                .exited(
                    identity: ProcessIdentity(pid: pid_t(500 + $0), startTime: UInt64($0 + 1)),
                    command: "Photocopier", at: at(Double($0) * 10))
            }
        }
        #expect(tracker.relaunchPatterns(in: exits(2), now: at(60)).isEmpty)
        #expect(tracker.relaunchPatterns(in: exits(3), now: at(60)).count == 1)

        #expect(run([calm(0), calm(60, findings:
            tracker.relaunchPatterns(in: exits(2), now: at(60)))]).isEmpty)
        #expect(opened(run([calm(0), calm(60, findings:
            tracker.relaunchPatterns(in: exits(3), now: at(60)))])).count == 1)
    }

    /// The incident is dated from the episode, not from the sweep that noticed the
    /// third exit — otherwise a quarter-hour of quitting would be recorded as
    /// having begun the moment it was already over.
    @Test("The incident spans the episode, not the moment we noticed it")
    func incidentIsDatedFromTheEpisode() throws {
        let events = run([calm(600), calm(660, findings: [pattern(from: 120, to: 600)])])
        let incident = try #require(opened(events).first)
        #expect(incident.beganAt == at(120))
        #expect(incident.triggeredAt == at(660))
    }

    /// A later pattern joining the episode must not re-date it forward over exits
    /// already recorded.
    @Test("A pattern arriving later never moves the start forward")
    func startOnlyEverMovesEarlier() throws {
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        _ = detector.observe(calm(600, findings: [pattern(from: 120, to: 600)]), state: &state)
        _ = detector.observe(
            calm(660, findings: [pattern(from: 500, to: 650)]), state: &state)
        let incident = try #require(state.current)
        #expect(incident.beganAt == at(120))
    }

    /// The quiet period is what ends the episode. Without it the condition would
    /// keep breaching until the pattern aged out of the tracker's own 15-minute
    /// window and every episode would be recorded as a quarter of an hour long.
    @Test("The episode closes a quiet period plus the recovery hysteresis after the last exit")
    func episodeClosesAfterQuietPeriod() throws {
        let policy = IncidentPolicy()
        let last: TimeInterval = 300
        let stale = pattern(from: 60, to: last)

        // Still breaching just inside the quiet period.
        let inside = calm(last + policy.repeatedQuitQuietPeriod.totalSeconds - 10,
                          findings: [stale])
        #expect(inside.breaches(.repeatedApplicationQuits, policy: policy))

        // Not breaching once it has passed, even though the tracker still holds it.
        let outside = calm(last + policy.repeatedQuitQuietPeriod.totalSeconds + 10,
                           findings: [stale])
        #expect(!outside.breaches(.repeatedApplicationQuits, policy: policy))

        let events = run([
            calm(0),
            calm(last, findings: [stale]),
            outside,
            calm(last + policy.repeatedQuitQuietPeriod.totalSeconds
                 + policy.recoveryDuration.totalSeconds + 20, findings: [stale]),
        ])
        #expect(opened(events).count == 1)
        let ended = try #require(closed(events).first)
        #expect(ended.conditions == [.repeatedApplicationQuits])
        #expect(ended.beganAt == at(60))
    }

    /// The evidence rides on the incident, because lifecycle events do not survive
    /// a restart and the tracker's window is 15 minutes wide.
    @Test("The incident records the pattern it was opened on")
    func incidentCarriesItsEvidence() throws {
        let events = run([calm(0), calm(60, findings: [pattern(exits: 4, from: 0, to: 50)])])
        let incident = try #require(opened(events).first)
        let finding = try #require(incident.lifecycleFindings.first)
        #expect(finding.command == "Photocopier")
        #expect(finding.exits == 4)
    }

    /// Widest account of the episode, per field, and never an average.
    @Test("Repeated sightings widen the recorded episode rather than replace it")
    func findingsMergeByCommand() throws {
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        _ = detector.observe(
            calm(60, findings: [pattern(exits: 3, from: 10, to: 55)]), state: &state)
        _ = detector.observe(
            calm(120, findings: [pattern(exits: 5, from: 20, to: 110)]), state: &state)
        let incident = try #require(state.current)
        #expect(incident.lifecycleFindings.count == 1)
        let finding = try #require(incident.lifecycleFindings.first)
        #expect(finding.exits == 5)
        #expect(finding.firstAt == at(10))
        #expect(finding.lastAt == at(110))
    }

    /// FR-038: two sightings of the same command must not combine into a more
    /// confident association than either supported on its own.
    @Test("Merging takes the weakest confidence, never the strongest")
    func mergingTakesTheWeakestConfidence() throws {
        let detector = IncidentDetector()
        var state = IncidentDetector.State()
        _ = detector.observe(
            calm(60, findings: [pattern(from: 10, to: 55, confidence: .high)]), state: &state)
        _ = detector.observe(
            calm(120, findings: [pattern(from: 10, to: 110, confidence: .low)]), state: &state)
        #expect(try #require(state.current?.lifecycleFindings.first).confidence == .low)
    }

    /// A second application quitting is its own finding on the same episode.
    @Test("Two commands quitting are recorded separately")
    func separateCommandsAreSeparateFindings() throws {
        let events = run([
            calm(0),
            calm(60, findings: [pattern("Photocopier", from: 0, to: 50),
                                pattern("Ledger", from: 10, to: 55)]),
        ])
        let incident = try #require(opened(events).first)
        #expect(Set(incident.lifecycleFindings.map(\.command)) == ["Photocopier", "Ledger"])
    }
}

@Suite("Cause confidence for a repeated quit cannot rise")
struct RepeatedQuitConfidenceTests {
    /// The thing that would raise it — the reason a process ended — is not
    /// observable at all, so no strength of pattern improves it.
    @Test("However strong the pattern, the cause confidence is low",
          arguments: [Confidence.low, .moderate, .high])
    func causeConfidenceStaysLow(patternConfidence: Confidence) {
        let observed = pattern(exits: 40, from: 0, to: 800, confidence: patternConfidence)
        #expect(observed.causeConfidence == .low)
    }

    /// And it is capped rather than fixed, so a weak association cannot come out
    /// looking better than the pattern it rests on.
    @Test("A low-confidence association does not become a low-confidence cause by luck")
    func causeConfidenceIsCappedNotFixed() {
        #expect(pattern(from: 0, to: 10, confidence: .low).causeConfidence == .low)
        #expect(pattern(from: 0, to: 10, confidence: .high).causeConfidence
                <= pattern(from: 0, to: 10, confidence: .high).confidence)
    }

    /// FR-046: the hang caveat has exactly one home and everything else points at it.
    @Test("The hang limitation says nothing is knowable about unresponsiveness")
    func hangLimitationIsHonest() {
        let text = RelaunchPattern.limitation
        #expect(text.contains("cannot see why it exited"))
        #expect(text.contains("cannot tell whether an app has stopped responding"))
        #expect(!text.lowercased().contains("hung"))
        #expect(!text.lowercased().contains("beachball"))
    }

    /// The condition's own label and the copy that goes with it must never claim a
    /// crash, a freeze or a hang. What we saw is a process ending.
    @Test("No copy for the condition claims a cause")
    func conditionCopyClaimsNothing() {
        let forbidden = ["crash", "hang", "hung", "froze", "frozen",
                         "unresponsive", "beachball"]
        let text = IncidentCondition.repeatedApplicationQuits.label.lowercased()
        for word in forbidden {
            #expect(!text.contains(word), "\"\(word)\" appears in the condition label")
        }
    }
}

@Suite("A lifecycle incident stores and reloads like any other")
struct RepeatedQuitPersistenceTests {
    private func lifecycleIncident() -> Incident {
        var incident = Incident(
            id: UUID(),
            beganAt: at(120), triggeredAt: at(660),
            recoveryStartedAt: nil, closedAt: at(900),
            conditions: [.repeatedApplicationQuits],
            severity: .moderate,
            peakCPUBusyFraction: 0.05,
            peakMemoryPressure: .normal)
        incident.lifecycleFindings = [pattern(exits: 4, from: 120, to: 640, confidence: .low)]
        incident.attribution = IncidentAttribution(
            sample: AttributionSample(
                applications: [IncidentContributor(
                    applicationID: "/Applications/Photocopier.app",
                    displayName: "Photocopier",
                    bundleID: "com.example.photocopier",
                    bundlePath: "/Applications/Photocopier.app",
                    peakPercentOfOneCore: 4.5,
                    hasUncertainMembers: true)],
                totalBusyPercentOfOneCore: 40,
                attributedPercentOfOneCore: 30,
                unattributedPercentOfOneCore: 10,
                logicalCoreCount: 10),
            at: at(300))
        return incident
    }

    /// Everything, not just the times: the recorded pattern, the attribution and the
    /// confidence it carried all have to come back exactly, or a reloaded incident
    /// would be a weaker claim than the one that was written.
    @Test("A repeated-quit incident round-trips through the stored form")
    func roundTripsExactly() throws {
        let original = lifecycleIncident()
        let data = try IncidentHistoryStore.encoder.encode(
            StoredIncidentHistory(retentionDays: 30, limit: 200, incidents: [original]))
        let decoded = try IncidentHistoryStore.decoder.decode(
            StoredIncidentHistory.self, from: data)
        let restored = try #require(decoded.incidents.first)

        #expect(restored == original)
        #expect(restored.conditions == [.repeatedApplicationQuits])
        #expect(restored.lifecycleFindings == original.lifecycleFindings)
        #expect(restored.lifecycleFindings.first?.exits == 4)
        #expect(restored.lifecycleFindings.first?.confidence == .low)
        #expect(restored.attribution?.confidence == original.attribution?.confidence)
    }

    /// Through the real store and a real file, because an encoder round trip is not
    /// evidence that the thing survives a restart.
    @Test("It survives a write and a fresh load from disk")
    func survivesARestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepeatedQuit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("incidents.json")
        let now = Date()
        var incident = lifecycleIncident()
        // Inside retention, so this test is about persistence and not about pruning.
        incident.closedAt = now.addingTimeInterval(-3600)

        IncidentHistoryStore(url: url).record(
            incident, settings: PrivacySettings(retention: .thirtyDays), now: now)

        let reloaded = IncidentHistoryStore(url: url)
            .load(settings: PrivacySettings(retention: .thirtyDays), now: now)
        let restored = try #require(reloaded.first)
        #expect(restored.conditions.contains(.repeatedApplicationQuits))
        #expect(restored.lifecycleFindings.first?.command == "Photocopier")
        #expect(restored.lifecycleFindings.first?.exits == 4)
    }

    /// The version step exists so an *older* build refuses a newer file instead of
    /// calling it malformed and discarding the user's history. It must not have cost
    /// us the ability to read what earlier builds wrote.
    @Test("A version-1 file written before this condition existed still loads")
    func olderFilesStillLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepeatedQuit-v1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("incidents.json")
        let now = Date()

        // Hand-built to be exactly what version 1 wrote: no `lifecycleFindings` key
        // at all, and a condition set an older build could produce.
        let identifier = UUID()
        let began = now.addingTimeInterval(-7200)
        let json = """
            {"schemaVersion":1,"writtenAt":\(now.timeIntervalSinceReferenceDate),
             "retentionDays":30,"limit":200,
             "incidents":[{"id":"\(identifier.uuidString)",
             "beganAt":\(began.timeIntervalSinceReferenceDate),
             "triggeredAt":\(began.addingTimeInterval(180).timeIntervalSinceReferenceDate),
             "closedAt":\(began.addingTimeInterval(900).timeIntervalSinceReferenceDate),
             "conditions":["cpuSaturation"],"severity":1,
             "peakCPUBusyFraction":0.93,"peakMemoryPressure":1}]}
            """
        try Data(json.utf8).write(to: url)

        let store = IncidentHistoryStore(url: url)
        let loaded = store.load(settings: PrivacySettings(retention: .thirtyDays), now: now)
        #expect(store.lastLoadFailure == nil, "a version-1 file no longer loads")
        let restored = try #require(loaded.first)
        #expect(restored.id == identifier)
        #expect(restored.conditions == [.cpuSaturation])
        #expect(restored.lifecycleFindings.isEmpty, "absent must decode as empty, not fail")
    }

    /// Why the version was stepped at all, stated as a test rather than as a comment.
    @Test("The schema version was stepped for the new condition")
    func schemaVersionWasStepped() {
        #expect(StoredIncidentHistory.currentSchemaVersion == 2)
    }
}
