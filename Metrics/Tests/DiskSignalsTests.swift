import Foundation
import Testing

@testable import Metrics

@Suite("Aggregate disk counters")
struct DiskCountersTests {
    /// Also a sandbox feasibility check: IOKit access from a sandboxed build was
    /// not covered by the Tier 0 probe.
    @Test("Block storage counters are readable")
    func countersReadable() throws {
        let counters = try #require(
            DiskSignals.counters(),
            "no IOBlockStorageDriver readable — IOKit may be unavailable here")
        #expect(counters.deviceCount > 0)
        // Any booted Mac has read from disk.
        #expect(counters.bytesRead > 0)
    }

    @Test("Counters are monotonic across two reads")
    func countersMonotonic() async throws {
        let first = try #require(DiskSignals.counters())
        try await Task.sleep(for: .milliseconds(300))
        let second = try #require(DiskSignals.counters())

        #expect(second.bytesRead >= first.bytesRead)
        #expect(second.bytesWritten >= first.bytesWritten)
    }
}

@Suite("Disk rates come only from deltas")
struct DiskRateTests {
    private func counters(read: UInt64, written: UInt64) -> DiskCounters {
        DiskCounters(bytesRead: read, bytesWritten: written, deviceCount: 1)
    }

    @Test("A rate is the difference over the interval, not the lifetime total")
    func rateIsDelta() throws {
        let before = counters(read: 900_000_000, written: 400_000_000)
        let after = counters(read: 900_010_000, written: 400_002_000)
        let rates = try #require(DiskSignals.rates(from: before, to: after, seconds: 2))

        #expect(rates.readBytesPerSecond == 5_000)
        #expect(rates.writeBytesPerSecond == 1_000)
    }

    @Test("An idle disk reports zero, not its lifetime total")
    func idleReportsZero() throws {
        let steady = counters(read: 12_345_678_900, written: 987_654_321)
        let rates = try #require(DiskSignals.rates(from: steady, to: steady, seconds: 3))
        #expect(rates.readBytesPerSecond == 0)
        #expect(rates.writeBytesPerSecond == 0)
    }

    @Test("A non-positive interval yields no rate")
    func nonPositiveInterval() {
        let before = counters(read: 1, written: 1)
        let after = counters(read: 2, written: 2)
        #expect(DiskSignals.rates(from: before, to: after, seconds: 0) == nil)
    }

    @Test("A counter going backwards reports zero, not an underflowed spike")
    func resetIsNotASpike() throws {
        let before = counters(read: 5_000_000_000, written: 2_000_000_000)
        let after = counters(read: 1_000, written: 500)
        let rates = try #require(DiskSignals.rates(from: before, to: after, seconds: 1))
        #expect(rates.readBytesPerSecond == 0)
        #expect(rates.writeBytesPerSecond == 0)
    }

    @Test("Live rates are finite and non-negative")
    func liveRatesAreSane() async throws {
        let before = try #require(DiskSignals.counters())
        try await Task.sleep(for: .milliseconds(400))
        let after = try #require(DiskSignals.counters())
        let rates = try #require(DiskSignals.rates(from: before, to: after, seconds: 0.4))

        #expect(rates.readBytesPerSecond >= 0)
        #expect(rates.writeBytesPerSecond >= 0)
        #expect(rates.readBytesPerSecond.isFinite)
        #expect(rates.writeBytesPerSecond.isFinite)
    }
}

@Suite("Disk copy states the per-app limitation")
struct DiskCopyTests {
    /// FR-009 as amended in spec v1.2: the absence of per-application attribution
    /// must be stated in the interface, not left as a silent omission.
    @Test("The limitation is stated plainly and without blame")
    func limitationStated() {
        let text = DiskSignals.perApplicationUnavailable
        #expect(text.lowercased().contains("whole mac"))
        #expect(text.lowercased().contains("per-application"))
        #expect(text.lowercased().contains("app store"))

        for forbidden in ["denied", "blocked", "error", "unfortunately", "sorry"] {
            #expect(!text.lowercased().contains(forbidden), "copy is defensive: \(forbidden)")
        }
    }
}

/// TASK-96 finding 16. The counters are a sum across every `IOBlockStorageDriver`,
/// so the set of devices is part of what makes two readings comparable.
@Suite("A change of devices is not a rate")
struct DiskTopologyChangeTests {
    private func counters(read: UInt64, written: UInt64, devices: Int) -> DiskCounters {
        DiskCounters(bytesRead: read, bytesWritten: written, deviceCount: devices)
    }

    @Test("Mounting a disk reports no rate rather than its lifetime bytes")
    func mountingReportsNothing() {
        // The newly mounted drive brings 400 GB of lifetime writes with it.
        let before = counters(read: 1_000, written: 1_000, devices: 1)
        let after = counters(read: 1_000, written: 400_000_000_000, devices: 2)
        #expect(DiskSignals.rates(from: before, to: after, seconds: 1) == nil)
    }

    @Test("Unmounting one reports no rate either")
    func unmountingReportsNothing() {
        let before = counters(read: 500_000, written: 500_000, devices: 2)
        let after = counters(read: 400_000, written: 400_000, devices: 1)
        #expect(DiskSignals.rates(from: before, to: after, seconds: 1) == nil)
    }

    @Test("A steady set of devices still yields a rate")
    func unchangedTopologyStillMeasures() throws {
        let before = counters(read: 0, written: 0, devices: 2)
        let after = counters(read: 2_000, written: 4_000, devices: 2)
        let rates = try #require(DiskSignals.rates(from: before, to: after, seconds: 2))
        #expect(rates.readBytesPerSecond == 1_000)
        #expect(rates.writeBytesPerSecond == 2_000)
    }
}
