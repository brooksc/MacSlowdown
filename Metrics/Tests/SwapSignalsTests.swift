import Darwin
import Foundation
import Testing

@testable import Metrics

private func counters(
    pageIns: UInt64 = 0, pageOuts: UInt64 = 0,
    swapIns: UInt64 = 0, swapOuts: UInt64 = 0,
    compressions: UInt64 = 0, decompressions: UInt64 = 0
) -> PagingCounters {
    PagingCounters(pageIns: pageIns, pageOuts: pageOuts, swapIns: swapIns,
                   swapOuts: swapOuts, compressions: compressions,
                   decompressions: decompressions)
}

@Suite("Swap usage")
struct SwapUsageTests {
    @Test("Swap usage is readable and internally consistent")
    func swapUsageReadable() throws {
        let usage = try #require(SwapSignals.swapUsage())
        #expect(usage.used <= usage.total)
        if usage.total > 0 {
            // used + available should account for total, within rounding.
            let accounted = usage.used + usage.available
            #expect(accounted >= usage.total - usage.total / 100)
        }
    }
}

@Suite("Paging counters")
struct PagingCountersTests {
    @Test("Counters are readable and monotonic across two reads")
    func countersAreMonotonic() async throws {
        let first = try #require(SwapSignals.pagingCounters())
        try await Task.sleep(for: .milliseconds(300))
        let second = try #require(SwapSignals.pagingCounters())

        #expect(second.pageIns >= first.pageIns)
        #expect(second.compressions >= first.compressions)
    }

    @Test("A machine that has been up a while has non-zero lifetime totals")
    func lifetimeTotalsAreLarge() throws {
        let now = try #require(SwapSignals.pagingCounters())
        // These are counts since boot. Any running Mac has paged something in.
        #expect(now.pageIns > 0)
    }
}

/// FR-008's core requirement: rates never derive from cumulative totals without a
/// delta, and counter reset and wrap are handled.
@Suite("Paging rates come only from deltas")
struct PagingRateTests {
    @Test("A rate is the difference over the interval, not the total")
    func rateIsDelta() throws {
        let before = counters(pageIns: 1_000_000, swapOuts: 500)
        let after = counters(pageIns: 1_000_100, swapOuts: 520)
        let rates = try #require(SwapSignals.rates(from: before, to: after, seconds: 10))

        // 100 page-ins over 10s is 10/s — not the 1,000,000 lifetime total.
        #expect(rates.pageInsPerSecond == 10)
        #expect(rates.swapOutsPerSecond == 2)
    }

    @Test("An unchanged counter yields a zero rate, not its total")
    func unchangedCounterIsZero() throws {
        let steady = counters(pageIns: 987_654_321, compressions: 42_000)
        let rates = try #require(SwapSignals.rates(from: steady, to: steady, seconds: 5))
        #expect(rates.pageInsPerSecond == 0)
        #expect(rates.compressionsPerSecond == 0)
        #expect(!rates.isSwapping)
    }

    @Test("A zero or negative interval yields no rate rather than a division")
    func nonPositiveIntervalYieldsNil() {
        let before = counters(pageIns: 10)
        let after = counters(pageIns: 20)
        #expect(SwapSignals.rates(from: before, to: after, seconds: 0) == nil)
        #expect(SwapSignals.rates(from: before, to: after, seconds: -1) == nil)
    }

    /// A counter going backwards means a reboot or a wrap. Neither is a
    /// measurement, and reporting the unsigned underflow would produce an
    /// astronomical spike presented as fact.
    @Test("A counter that goes backwards reports zero, not a spike")
    func resetIsNotASpike() throws {
        let before = counters(pageIns: 5_000_000, swapOuts: 900)
        let after = counters(pageIns: 12, swapOuts: 0)  // rebooted
        let rates = try #require(SwapSignals.rates(from: before, to: after, seconds: 2))

        #expect(rates.pageInsPerSecond == 0, "underflow would report ~9.2e18")
        #expect(rates.swapOutsPerSecond == 0)
    }

    @Test("One field resetting does not corrupt the others")
    func partialResetIsIsolated() throws {
        let before = counters(pageIns: 5_000, swapOuts: 900)
        let after = counters(pageIns: 5_200, swapOuts: 100)
        let rates = try #require(SwapSignals.rates(from: before, to: after, seconds: 2))

        #expect(rates.pageInsPerSecond == 100)
        #expect(rates.swapOutsPerSecond == 0)
    }

    @Test("Swapping is reported only when swap counters actually move")
    func swappingDetection() throws {
        let quiet = try #require(SwapSignals.rates(
            from: counters(pageIns: 100), to: counters(pageIns: 200), seconds: 1))
        #expect(!quiet.isSwapping, "page-ins alone are not swapping")

        let swapping = try #require(SwapSignals.rates(
            from: counters(swapOuts: 10), to: counters(swapOuts: 30), seconds: 1))
        #expect(swapping.isSwapping)
    }

    @Test("Rates computed from the live system are finite and non-negative")
    func liveRatesAreSane() async throws {
        let before = try #require(SwapSignals.pagingCounters())
        try await Task.sleep(for: .milliseconds(500))
        let after = try #require(SwapSignals.pagingCounters())
        let rates = try #require(SwapSignals.rates(from: before, to: after, seconds: 0.5))

        for value in [rates.pageInsPerSecond, rates.pageOutsPerSecond,
                      rates.swapInsPerSecond, rates.swapOutsPerSecond,
                      rates.compressionsPerSecond, rates.decompressionsPerSecond] {
            #expect(value >= 0)
            #expect(value.isFinite)
        }
    }
}
