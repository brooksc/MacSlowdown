import Darwin
import Foundation
import Testing

@testable import Metrics

@Suite("Mach time conversion")
struct MachTimeTests {
    @Test("Timebase matches the kernel's own value")
    func timebaseMatchesKernel() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let expected = Double(info.numer) / Double(info.denom)
        #expect(MachTime.nanosPerTick == expected)
    }

    @Test("Timebase is positive and plausible")
    func timebaseIsPlausible() {
        // Apple Silicon is 125/3 = 41.667; Intel is 1.0. Anything outside this
        // range means we have misread the timebase.
        #expect(MachTime.nanosPerTick >= 1.0)
        #expect(MachTime.nanosPerTick <= 1000.0)
    }

    @Test("Ticks convert to nanoseconds via the timebase, not 1:1")
    func ticksConvertToNanos() {
        let ticks: UInt64 = 1_000_000
        #expect(MachTime.nanos(fromTicks: ticks) == Double(ticks) * MachTime.nanosPerTick)
        #expect(MachTime.seconds(fromTicks: ticks) == MachTime.nanos(fromTicks: ticks) / 1e9)
    }

    /// Ground truth: mach_absolute_time deltas converted through the timebase must
    /// agree with wall-clock elapsed time. This is the property that, when broken,
    /// makes every CPU percentage in the app ~42x too low.
    @Test("Converted mach deltas agree with wall clock")
    func convertedDeltaMatchesWallClock() async throws {
        let machStart = mach_absolute_time()
        let clockStart = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(200))
        let machElapsed = MachTime.seconds(fromTicks: mach_absolute_time() - machStart)
        let wallElapsed = (ContinuousClock.now - clockStart).totalSeconds

        #expect(abs(machElapsed - wallElapsed) < 0.05,
                "mach \(machElapsed)s vs wall \(wallElapsed)s")
    }
}

@Suite("Duration.totalSeconds")
struct DurationTotalSecondsTests {
    @Test("Sub-second durations")
    func subSecond() {
        #expect(abs(Duration.milliseconds(250).totalSeconds - 0.25) < 1e-9)
    }

    /// Regression guard: reading `components.attoseconds` alone truncates whole
    /// seconds, so a 3s duration measured 4.86ms during the Tier 0 probe.
    @Test("Durations of one second or more are not truncated")
    func multiSecondNotTruncated() {
        #expect(abs(Duration.seconds(3).totalSeconds - 3.0) < 1e-9)
        #expect(abs(Duration.milliseconds(3500).totalSeconds - 3.5) < 1e-9)
        #expect(Duration.seconds(3).totalSeconds > 1.0)
    }
}
