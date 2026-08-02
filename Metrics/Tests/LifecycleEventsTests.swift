import Darwin
import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

private func snapshot(
    _ processes: [(pid: Int32, start: UInt64, command: String)],
    enumeration: EnumerationOutcome = .succeeded
) -> ProcessSnapshot {
    var records: [ProcessIdentity: ProcessRecord] = [:]
    for process in processes {
        let identity = ProcessIdentity(pid: process.pid, startTime: process.start)
        records[identity] = ProcessRecord(
            identity: identity, command: process.command, uid: 501, ppid: 1,
            metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1 << 20)))
    }
    return ProcessSnapshot(records: records, takenAt: ContinuousClock.now,
                           sweepDuration: .milliseconds(2), enumeration: enumeration)
}

@Suite("Lifecycle events")
struct LifecycleEventTests {
    /// AC#1: launches, exits and PID replacements recorded with timestamps.
    @Test("A new process is a launch and a departed one is an exit")
    func launchesAndExits() {
        let tracker = LifecycleTracker()
        let before = snapshot([(100, 1, "Safari"), (200, 1, "Mail")])
        let after = snapshot([(100, 1, "Safari"), (300, 2, "Xcode")])

        let events = tracker.events(from: before, to: after, at: at(10))
        #expect(events.count == 2)
        #expect(events.contains { $0.command == "Xcode" && $0.at == at(10) })
        #expect(events.contains {
            if case .exited(_, let command, _) = $0 { return command == "Mail" }
            return false
        })
        // Safari was present throughout and generates nothing.
        #expect(!events.contains { $0.command == "Safari" })
    }

    /// A PID reused by a different process must read as one exit plus one launch,
    /// not as the same process continuing.
    @Test("A reused PID is an exit and a launch, not continuity")
    func reusedPidIsReplacement() {
        let tracker = LifecycleTracker()
        let before = snapshot([(100, 1_000, "OldThing")])
        let after = snapshot([(100, 2_000, "NewThing")])  // same pid, new start time

        let events = tracker.events(from: before, to: after, at: at(5))
        #expect(events.count == 2)
        #expect(events.contains { $0.command == "OldThing" })
        #expect(events.contains { $0.command == "NewThing" })
    }

    @Test("An unchanged process table produces no events")
    func noChangeNoEvents() {
        let tracker = LifecycleTracker()
        let table = snapshot([(100, 1, "Safari"), (200, 1, "Mail")])
        #expect(tracker.events(from: table, to: table, at: at(0)).isEmpty)
    }

    /// If enumeration failed we know nothing about what changed, and reporting
    /// "everything exited" would be catastrophic nonsense (FR-002).
    @Test("A failed enumeration produces no events rather than mass exits")
    func failedEnumerationProducesNothing() {
        let tracker = LifecycleTracker()
        let before = snapshot([(100, 1, "Safari"), (200, 1, "Mail")])
        let denied = snapshot([], enumeration: .failed(errno: EPERM))

        #expect(tracker.events(from: before, to: denied, at: at(1)).isEmpty)
        #expect(tracker.events(from: denied, to: before, at: at(1)).isEmpty)
    }
}

@Suite("Relaunch patterns")
struct RelaunchPatternTests {
    private func exits(_ command: String, times: [TimeInterval]) -> [LifecycleEvent] {
        times.enumerated().map { index, seconds in
            .exited(identity: ProcessIdentity(pid: Int32(1000 + index), startTime: UInt64(index)),
                    command: command, at: at(seconds))
        }
    }

    /// AC#2: a relaunch loop appears as related events, not unrelated incidents.
    @Test("Repeated exits of one app become a single pattern")
    func repeatedExitsGroup() throws {
        let tracker = LifecycleTracker(minimumExits: 3, window: .seconds(900))
        let events = exits("Final Cut Pro", times: [0, 300, 720])

        let patterns = tracker.relaunchPatterns(in: events, now: at(800))
        #expect(patterns.count == 1, "three exits should be one pattern, not three incidents")

        let pattern = try #require(patterns.first)
        #expect(pattern.exits == 3)
        #expect(pattern.command == "Final Cut Pro")
        #expect(pattern.summary.contains("3 times"))
    }

    @Test("An ordinary single restart is not a pattern")
    func singleRestartIsNotAPattern() {
        let tracker = LifecycleTracker(minimumExits: 3)
        #expect(tracker.relaunchPatterns(in: exits("Safari", times: [0]), now: at(10)).isEmpty)
        #expect(tracker.relaunchPatterns(in: exits("Safari", times: [0, 60]), now: at(70)).isEmpty)
    }

    @Test("Exits outside the window are excluded")
    func windowExcludesOldExits() {
        let tracker = LifecycleTracker(minimumExits: 3, window: .seconds(600))
        // Two recent, one long past.
        let events = exits("Thing", times: [0, 5_000, 5_100])
        #expect(tracker.relaunchPatterns(in: events, now: at(5_200)).isEmpty,
                "only two exits fall inside the window")
    }

    @Test("Different applications form separate patterns")
    func separateApplicationsSeparate() {
        let tracker = LifecycleTracker(minimumExits: 2)
        let events = exits("AppOne", times: [0, 10]) + exits("AppTwo", times: [20, 30])
        let patterns = tracker.relaunchPatterns(in: events, now: at(40))
        #expect(patterns.count == 2)
        #expect(Set(patterns.map(\.command)) == ["AppOne", "AppTwo"])
    }

    @Test("Launch events do not count as exits")
    func launchesDoNotCount() {
        let tracker = LifecycleTracker(minimumExits: 2)
        let launches: [LifecycleEvent] = (0..<5).map {
            .launched(identity: ProcessIdentity(pid: Int32($0), startTime: 1),
                      command: "Thing", at: at(Double($0)))
        }
        #expect(tracker.relaunchPatterns(in: launches, now: at(10)).isEmpty)
    }

    /// AC#3: uncertain attribution is labeled. p_comm is truncated to 16 bytes,
    /// so a name at the limit could be several different executables.
    @Test("A truncated command name lowers confidence")
    func truncatedNameIsUncertain() throws {
        let tracker = LifecycleTracker(minimumExits: 2)

        let short = tracker.relaunchPatterns(in: exits("Mail", times: [0, 10]), now: at(20))
        #expect(try #require(short.first).confidence == .moderate)

        let truncated = tracker.relaunchPatterns(
            in: exits("com.apple.WebKit", times: [0, 10]), now: at(20))
        #expect(try #require(truncated.first).confidence == .low,
                "a name at the truncation limit could be several processes")
    }
}

/// AC#4: nothing here may claim an application was unresponsive or hung, because
/// TASK-27 established that is not observable.
@Suite("Lifecycle copy never claims a hang")
struct LifecycleCopyTests {
    @Test("Event descriptions state only what was observed")
    func eventCopyIsObservational() {
        let events: [LifecycleEvent] = [
            .launched(identity: ProcessIdentity(pid: 1, startTime: 1), command: "App", at: Date()),
            .exited(identity: ProcessIdentity(pid: 1, startTime: 1), command: "App", at: Date()),
        ]
        for event in events {
            let text = event.description.lowercased()
            for forbidden in ["hung", "hang", "froze", "frozen", "unresponsive",
                              "beachball", "crashed", "stopped responding"] {
                #expect(!text.contains(forbidden), "event copy claims \(forbidden): \(text)")
            }
        }
    }

    @Test("Pattern summaries describe what happened, not why")
    func patternCopyAvoidsCause() {
        let pattern = RelaunchPattern(
            command: "Final Cut Pro", exits: 3,
            firstAt: at(0), lastAt: at(720), confidence: .moderate)
        let text = pattern.summary.lowercased()

        #expect(text.contains("exited and restarted"))
        for forbidden in ["hung", "froze", "unresponsive", "stopped responding",
                          "crashed", "because", "caused"] {
            #expect(!text.contains(forbidden), "summary claims \(forbidden)")
        }
    }

    @Test("The limitation is stated explicitly and names the hang case")
    func limitationIsExplicit() {
        let text = RelaunchPattern.limitation.lowercased()
        #expect(text.contains("cannot see why it exited"))
        #expect(text.contains("stopped responding"),
                "the limitation must name the thing we cannot detect")
        #expect(text.contains("exactly as it reports a healthy one"))
    }
}
