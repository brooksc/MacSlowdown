import Darwin
import Foundation
import Testing

@testable import Metrics

@Suite("Memory statistics")
struct MemoryStatisticsTests {
    @Test("VM statistics are readable and plausible")
    func statisticsArePlausible() throws {
        let stats = try #require(MemorySignals.statistics())
        #expect(stats.pageSize > 0)
        #expect(stats.wired > 0)
        #expect(stats.active > 0)

        // Should account for a sane fraction of physical memory. Not exact:
        // the kernel's categories do not partition RAM perfectly.
        let physical = ProcessInfo.processInfo.physicalMemory
        #expect(stats.accountedFor > physical / 4, "accounted \(stats.accountedFor) of \(physical)")
        #expect(stats.accountedFor <= physical * 2)
    }

    @Test("Statistics are reported in bytes, not pages")
    func reportedInBytes() throws {
        let stats = try #require(MemorySignals.statistics())
        // A page is 4K or 16K; byte values must be far larger than page counts.
        #expect(stats.wired > stats.pageSize)
        #expect(stats.wired % stats.pageSize == 0, "wired should be a whole number of pages")
    }
}

@Suite("Memory pressure level")
struct MemoryPressureLevelTests {
    @Test("The kernel's current level is readable")
    func currentLevelReadable() {
        let level = MemorySignals.currentPressureLevel()
        #expect(MemoryPressureLevel.allCases.contains(level))
    }

    @Test("Levels order by severity")
    func levelsOrder() {
        #expect(MemoryPressureLevel.normal < .warning)
        #expect(MemoryPressureLevel.warning < .critical)
    }

    /// FR-007: the interface must not describe cached memory as inherently
    /// wasted, and FR-036 forbids implying memory can be freed.
    @Test("No level's explanation implies cached memory is waste")
    func explanationsAvoidWasteLanguage() {
        for level in MemoryPressureLevel.allCases {
            let text = level.explanation.lowercased()
            #expect(!text.isEmpty)
            for forbidden in ["wasted", "waste", "free up", "freed", "reclaim memory",
                              "clean", "optimi", "hog", "leak"] {
                #expect(!text.contains(forbidden),
                        "\(level) explanation uses '\(forbidden)': \(level.explanation)")
            }
        }
    }

    @Test("Normal explicitly reassures that cache in use is not a problem")
    func normalExplainsCache() {
        let text = MemoryPressureLevel.normal.explanation.lowercased()
        #expect(text.contains("cache"))
        #expect(text.contains("normal") || text.contains("not a problem"))
    }
}

@Suite("Memory pressure transitions")
struct MemoryPressureMonitorTests {
    /// FR-007: transitions are captured within 2 seconds. A dispatch source
    /// reports the change when it happens, so the binding constraint is that we
    /// record it immediately rather than at the next sample.
    @Test("A transition is recorded with its timestamp")
    func transitionRecorded() throws {
        let monitor = MemoryPressureMonitor()
        let before = Date()
        let transition = try #require(monitor.record(.warning))

        #expect(transition.level == .warning)
        #expect(transition.at.timeIntervalSince(before) < 2.0)
        #expect(monitor.level == .warning)
        #expect(monitor.transitions.count == 1)
    }

    @Test("Repeated notifications at the same level are not transitions")
    func repeatsAreNotTransitions() {
        let monitor = MemoryPressureMonitor()
        monitor.record(.warning)
        monitor.record(.warning)
        monitor.record(.warning)
        #expect(monitor.transitions.count == 1, "a level that did not change is not a transition")
    }

    @Test("Every change is recorded, in order, including recovery")
    func recordsSequence() {
        let monitor = MemoryPressureMonitor()
        monitor.record(.warning)
        monitor.record(.critical)
        monitor.record(.warning)
        monitor.record(.normal)

        #expect(monitor.transitions.map(\.level) == [.warning, .critical, .warning, .normal])
        #expect(monitor.level == .normal)
    }

    @Test("Transition history is bounded")
    func historyIsBounded() {
        let monitor = MemoryPressureMonitor(maximumTransitions: 10)
        for index in 0..<100 {
            monitor.record(index.isMultiple(of: 2) ? .warning : .normal)
        }
        #expect(monitor.transitions.count == 10)
    }

    @Test("Starting the monitor reads the live level without crashing")
    func startsAgainstLiveSystem() async throws {
        let monitor = MemoryPressureMonitor()
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(MemoryPressureLevel.allCases.contains(monitor.level))
    }
}
