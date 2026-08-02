import Foundation
import Testing

@testable import Metrics

private func sample(at offset: TimeInterval, contributors: Int = 5) -> HistorySample {
    HistorySample(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
        totalBusyPercentOfOneCore: 250,
        attributedPercentOfOneCore: 150,
        unattributedPercentOfOneCore: 100,
        topContributors: (0..<contributors).map {
            ContributorSummary(
                pid: Int32(1000 + $0), startTime: 1_700_000_000,
                command: "process-\($0)", percentOfOneCore: 30, residentBytes: 128 << 20)
        }
    )
}

@Suite("Rolling history")
struct MetricsHistoryTests {
    /// AC#1: FR-005 requires at least 15 minutes by default.
    @Test("Default retention spans at least 15 minutes at the default cadence")
    func defaultRetentionCoversFifteenMinutes() {
        let history = MetricsHistory()
        #expect(MetricsHistory.defaultRetention.totalSeconds >= 15 * 60)

        // Fill past capacity, then confirm the retained window still spans the
        // full 15 minutes rather than falling one sample short.
        for index in 0..<(history.capacity * 2) {
            history.append(sample(at: Double(index) * 2))
        }
        #expect(history.coveredDuration.totalSeconds >= 15 * 60,
                "covered only \(history.coveredDuration.totalSeconds)s")
    }

    /// AC#2, memory half: bounded by construction.
    @Test("Appending past capacity evicts the oldest, so memory is bounded")
    func evictsOldest() throws {
        let history = MetricsHistory(retention: .seconds(20), cadence: .seconds(2))
        for index in 0..<500 {
            history.append(sample(at: Double(index)))
        }
        #expect(history.sampleCount == history.capacity)
        #expect(history.capacity <= 12)

        // The survivors are the most recent ones.
        let oldest = history.samples.first
        let first = try #require(oldest)
        let expectedOldest = Date(timeIntervalSince1970: 1_700_000_000 + Double(500 - history.capacity))
        #expect(first.timestamp == expectedOldest)
    }

    @Test("A full 15 minutes of history stays far inside the memory budget")
    func memoryFootprintIsSmall() throws {
        let history = MetricsHistory()
        for index in 0..<history.capacity {
            history.append(sample(at: Double(index) * 2))
        }

        // Encoded size is a reasonable proxy for retained size and is what the disk
        // budget sees. FR-030 allows 100MB resident for the whole app; history must
        // be a rounding error against that.
        let encoded = try JSONEncoder().encode(history.samples)
        #expect(encoded.count < 5_000_000,
                "15 minutes of history encodes to \(encoded.count) bytes")
    }

    @Test("Only leading contributors are retained, not the whole process table")
    func retainsOnlyLeadingContributors() {
        let history = MetricsHistory(topContributorCount: 3)
        let contributors = (0..<50).map {
            ProcessCPUUsage(
                identity: ProcessIdentity(pid: Int32(2000 + $0), startTime: 1),
                command: "p\($0)",
                percentOfOneCore: Double(50 - $0),
                residentBytes: 1 << 20)
        }
        let attribution = CPUAttribution(
            totalBusyPercentOfOneCore: 800,
            attributedPercentOfOneCore: 600,
            unattributedPercentOfOneCore: 200,
            contributors: contributors,
            protectedProcesses: [],
            logicalCoreCount: 8)

        history.record(attribution)
        #expect(history.samples.first?.topContributors.count == 3)
        #expect(history.samples.first?.topContributors.first?.command == "p0")
    }

    @Test("Recording preserves the attribution breakdown intact")
    func recordPreservesBreakdown() throws {
        let history = MetricsHistory()
        let attribution = CPUAttribution(
            totalBusyPercentOfOneCore: 300,
            attributedPercentOfOneCore: 180,
            unattributedPercentOfOneCore: 120,
            contributors: [],
            protectedProcesses: [],
            logicalCoreCount: 8)

        history.record(attribution)
        let stored = try #require(history.samples.first)
        #expect(stored.totalBusyPercentOfOneCore == 300)
        #expect(stored.attributedPercentOfOneCore == 180)
        #expect(stored.unattributedPercentOfOneCore == 120)
    }
}

@Suite("History persistence")
struct HistoryPersistenceTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("macslowdown-tests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
    }

    /// AC#3: persistence is configurable, and memory-only genuinely writes nothing.
    @Test("Memory-only persistence writes nothing to disk")
    func memoryOnlyWritesNothing() throws {
        let history = MetricsHistory(persistence: .memoryOnly)
        history.append(sample(at: 0))
        #expect(try history.flushIfNeeded() == 0)
    }

    @Test("History survives a restart when persistence is enabled")
    func survivesRestart() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = MetricsHistory(
            persistence: .acrossRestarts(url: url, flushInterval: .seconds(0)))
        for index in 0..<10 { original.append(sample(at: Double(index) * 2)) }
        let written = try original.flushIfNeeded()
        #expect(written > 0)

        let restored = MetricsHistory(
            persistence: .acrossRestarts(url: url, flushInterval: .seconds(0)))
        restored.restore()
        #expect(restored.sampleCount == 10)
        #expect(restored.samples == original.samples)
    }

    @Test("Restoring truncates to capacity rather than exceeding it")
    func restoreRespectsCapacity() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let large = MetricsHistory(
            retention: .seconds(600), cadence: .seconds(2),
            persistence: .acrossRestarts(url: url, flushInterval: .seconds(0)))
        for index in 0..<300 { large.append(sample(at: Double(index) * 2)) }
        try large.flushIfNeeded()

        let small = MetricsHistory(
            retention: .seconds(20), cadence: .seconds(2),
            persistence: .acrossRestarts(url: url, flushInterval: .seconds(0)))
        small.restore()
        #expect(small.sampleCount == small.capacity)
    }

    @Test("Missing or corrupt state does not block startup")
    func missingStateIsNotAnError() throws {
        let url = temporaryURL()
        let history = MetricsHistory(
            persistence: .acrossRestarts(url: url, flushInterval: .seconds(0)))
        history.restore()
        #expect(history.sampleCount == 0)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("not json".utf8).write(to: url)

        history.restore()
        #expect(history.sampleCount == 0)
    }

    /// AC#2, disk half: FR-030 caps writes at 10 MB/hour absent incidents. Flushes
    /// are batched so traffic does not scale with the sample rate.
    @Test("Batched flushing stays far inside the 10 MB/hour disk budget")
    func diskWritesWithinBudget() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // The default configuration is what ships, so that is what must fit.
        let flushInterval = MetricsHistory.defaultFlushInterval
        let history = MetricsHistory(persistence: .acrossRestarts(url: url))
        for index in 0..<history.capacity { history.append(sample(at: Double(index) * 2)) }

        // A flush at full history is the worst case: the file is rewritten whole.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bytesPerFlush = try history.flushIfNeeded(now: start)
        #expect(bytesPerFlush > 0)

        let flushesPerHour = 3600.0 / flushInterval.totalSeconds
        let bytesPerHour = Double(bytesPerFlush) * flushesPerHour
        let detail = "\(Int(bytesPerHour)) bytes/hour from \(bytesPerFlush)-byte flushes"
        #expect(bytesPerHour < 10_000_000, "\(detail) exceeds the 10MB budget")
    }

    @Test("Flushes are skipped until the interval has elapsed")
    func flushIsRateLimited() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let history = MetricsHistory(
            persistence: .acrossRestarts(url: url, flushInterval: .seconds(60)))
        history.append(sample(at: 0))

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(try history.flushIfNeeded(now: start) > 0)
        #expect(try history.flushIfNeeded(now: start.addingTimeInterval(30)) == 0)
        #expect(try history.flushIfNeeded(now: start.addingTimeInterval(61)) > 0)
    }
}
