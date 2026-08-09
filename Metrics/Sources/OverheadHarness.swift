import Darwin
import Foundation

/// What a monitoring run cost the machine.
public struct OverheadMeasurement: Sendable {
    public let wallDuration: Duration
    public let sweeps: Int
    /// Our own CPU consumption over the whole run, as a percentage of one core.
    /// Includes process launch and the first-sighting pass, so a short run reads
    /// high. Reported, but not what the budget is judged on.
    public let selfCPUPercentOfOneCore: Double
    /// CPU consumption once every cache is warm.
    ///
    /// This is the figure FR-030's "idle CPU median" actually describes. Startup
    /// happens once per launch; the steady state is what a user lives with, and
    /// what a regression would show up in.
    public let steadyStateCPUPercentOfOneCore: Double
    /// CPU spent before steady state began — process launch plus the first pass
    /// over every process. Called out rather than averaged away.
    public let startupCPUSeconds: Double
    public let residentBytesAtEnd: UInt64
    public let residentGrowthBytes: Int64
    /// Projected disk traffic at the configured flush interval.
    public let bytesWrittenPerHour: Double
    public let medianSweep: Duration

    /// Judged on steady state, per FR-030's wording. `selfCPUPercentOfOneCore`
    /// stays visible so the startup cost is never hidden.
    public var withinCPUBudget: Bool {
        steadyStateCPUPercentOfOneCore <= FR030Budget.cpuPercentOfOneCore
    }
    public var withinMemoryBudget: Bool { residentBytesAtEnd <= FR030Budget.residentBytes }
    public var withinDiskBudget: Bool { bytesWrittenPerHour <= FR030Budget.bytesPerHour }
    public var withinAllBudgets: Bool { withinCPUBudget && withinMemoryBudget && withinDiskBudget }

    public var summary: String {
        String(
            format: """
                sweeps: %d over %.1fs
                cpu:    %.3f%% of one core steady state (budget %.1f%%) %@
                memory: %.1f MB resident, %+.1f MB growth (budget %.0f MB) %@
                disk:   %.2f MB/hour projected (budget %.0f MB/hour) %@
                sweep:  %.2f ms median
                whole:  %.3f%% over the whole run, including %.0f ms of startup
                """,
            sweeps, wallDuration.totalSeconds,
            steadyStateCPUPercentOfOneCore, FR030Budget.cpuPercentOfOneCore,
            withinCPUBudget ? "OK" : "OVER",
            Double(residentBytesAtEnd) / 1_048_576,
            Double(residentGrowthBytes) / 1_048_576,
            Double(FR030Budget.residentBytes) / 1_048_576,
            withinMemoryBudget ? "OK" : "OVER",
            bytesWrittenPerHour / 1_048_576,
            Double(FR030Budget.bytesPerHour) / 1_048_576,
            withinDiskBudget ? "OK" : "OVER",
            medianSweep.totalSeconds * 1000,
            selfCPUPercentOfOneCore, startupCPUSeconds * 1000
        )
    }
}

/// The FR-030 budget, in one place so it cannot drift between code and tests.
public enum FR030Budget {
    /// Idle CPU median, as a percentage of one core.
    public static let cpuPercentOfOneCore: Double = 1.0
    public static let residentBytes: UInt64 = 100 * 1_048_576
    public static let bytesPerHour: Double = 10 * 1_048_576
}

/// Runs a realistic monitoring loop and measures what it cost.
///
/// This is the permanent guard for FR-030: the budget is a test, not an
/// aspiration. It exercises the real sampling path — enumerate, read metrics,
/// resolve identity through the cache, attribute, record history, flush — so a
/// regression anywhere in that chain shows up here.
public enum OverheadHarness {
    /// Our own resident size, read the same way we read any other process.
    ///
    /// NOTE: this and `selfCPUTicks` measure the whole process. That is correct for
    /// the shipping app, where the process is only us, but inside a parallel test
    /// run it also counts other suites' work. Treat standalone runs as the
    /// authoritative FR-030 measurement.
    public static func selfResidentBytes() -> UInt64 {
        guard case .measured(let metrics) = ProcessSampler.metrics(for: getpid()) else { return 0 }
        return metrics.residentBytes
    }

    static func selfCPUTicks() -> UInt64 {
        guard case .measured(let metrics) = ProcessSampler.metrics(for: getpid()) else { return 0 }
        return metrics.cpuTicks
    }

    public static func measure(
        duration: Duration,
        cadence: Duration = MetricsHistory.defaultCadence,
        history: MetricsHistory
    ) async -> OverheadMeasurement {
        let sampler = ProcessSampler()
        let resolver = ProcessIdentityResolver()
        let clock = ContinuousClock()
        // Incident detection runs on the hot path in the shipping app, so it runs
        // here too — a budget measured without it would flatter us.
        let detector = IncidentDetector()
        var detectorState = IncidentDetector.State()
        let cadenceController = CadenceController(normalInterval: cadence)
        var cadenceState = CadenceController.State()
        let lifecycle = LifecycleTracker()

        let startedAt = clock.now
        let cpuAtStart = selfCPUTicks()
        let residentAtStart = selfResidentBytes()

        var sweepDurations: [Duration] = []
        // Steady state begins once every process has been seen once. Two sweeps
        // is enough: the first populates the identity cache, the second confirms
        // it is being served from it.
        let warmupSweeps = 2
        var steadyStartedAt: ContinuousClock.Instant?
        var cpuAtSteadyStart: UInt64 = 0
        var previous = sampler.snapshot()
        var previousHost = HostCPU.sample()
        var bytesWritten = 0
        var sweeps = 0

        while clock.now - startedAt < duration {
            try? await Task.sleep(for: cadence)

            let snapshot = sampler.snapshot()
            sweepDurations.append(snapshot.sweepDuration)
            let host = HostCPU.sample()

            if let previousHost, let host {
                let attribution = CPUAttributionCalculator.attribution(
                    from: previous, to: snapshot,
                    hostEarlier: previousHost, hostLater: host,
                    naming: { resolver.identity(for: $0).friendlyName })
                history.record(attribution)

                // Group every process, which is what the app does on each sweep —
                // the inventory lists all families, not just the leading few. This
                // resolves identity and friendly names for the whole table, so the
                // filesystem work naming added is inside the measurement rather
                // than outside it. Measuring only the top contributors flattered
                // the figure and would have hidden exactly the regression FR-030
                // exists to catch.
                _ = FamilyGrouper.group(snapshot: snapshot, resolver: resolver)

                // Detection, summarisation and cadence selection, as the app does.
                let observation = SystemObservation(
                    at: Date(),
                    cpuBusyFraction: attribution.totalBusyPercentOfOneCore
                        / (Double(MachineTopology.logicalCoreCount) * 100),
                    memoryPressure: MemorySignals.currentPressureLevel(),
                    thermalState: .current)
                if case .opened(let incident)? = detector.observe(
                    observation, state: &detectorState) {
                    _ = IncidentSummarizer.summarize(incident: incident, attribution: attribution)
                }
                _ = cadenceController.cadence(
                    at: Date(), incidentOpen: detectorState.current != nil,
                    conditionBreaching: false, state: &cadenceState)
                _ = lifecycle.events(from: previous, to: snapshot)
            }

            resolver.prune(keeping: Set(snapshot.records.keys))
            bytesWritten += (try? history.flushIfNeeded()) ?? 0

            previous = snapshot
            previousHost = host
            sweeps += 1

            if sweeps == warmupSweeps {
                steadyStartedAt = clock.now
                cpuAtSteadyStart = selfCPUTicks()
            }
        }

        let wall = clock.now - startedAt
        let cpuSeconds = MachTime.seconds(fromTicks: selfCPUTicks() &- cpuAtStart)
        let resident = selfResidentBytes()

        sweepDurations.sort { $0 < $1 }
        let median = sweepDurations.isEmpty
            ? Duration.zero
            : sweepDurations[sweepDurations.count / 2]

        // Project observed disk traffic to an hourly rate. A run shorter than one
        // flush interval writes nothing, so fall back to the worst case: one full
        // rewrite per flush interval.
        let bytesPerHour: Double
        if bytesWritten > 0 {
            bytesPerHour = Double(bytesWritten) / wall.totalSeconds * 3600
        } else if case .acrossRestarts(_, let interval) = history.persistence {
            let encoded = (try? JSONEncoder().encode(history.samples).count) ?? 0
            bytesPerHour = Double(encoded) * (3600 / interval.totalSeconds)
        } else {
            bytesPerHour = 0
        }

        let steadyWall = steadyStartedAt.map { (clock.now - $0).totalSeconds } ?? 0
        let steadyCPU = MachTime.seconds(fromTicks: selfCPUTicks() &- cpuAtSteadyStart)

        return OverheadMeasurement(
            wallDuration: wall,
            sweeps: sweeps,
            selfCPUPercentOfOneCore: wall.totalSeconds > 0
                ? cpuSeconds / wall.totalSeconds * 100 : 0,
            steadyStateCPUPercentOfOneCore: steadyWall > 0
                ? steadyCPU / steadyWall * 100 : 0,
            startupCPUSeconds: MachTime.seconds(fromTicks: cpuAtSteadyStart &- cpuAtStart),
            residentBytesAtEnd: resident,
            residentGrowthBytes: Int64(resident) - Int64(residentAtStart),
            bytesWrittenPerHour: bytesPerHour,
            medianSweep: median
        )
    }
}
