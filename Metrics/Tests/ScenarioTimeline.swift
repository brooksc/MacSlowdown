import Darwin
import Foundation

@testable import Metrics

/// A scripted machine, replayed deterministically through the real engine.
///
/// **Why this exists.** Every piece of the engine was already tested in
/// isolation — grouping from synthetic process records, the detector from
/// synthetic observations, the alert gate from synthetic incidents. What nothing
/// tested was the whole chain against a *machine that behaves a certain way over
/// time*, because per-process load could only enter the pipeline through
/// `proc_pidinfo`. The one end-to-end test therefore had to spawn real `yes`
/// processes, which is why it is machine-sensitive, fails under load, and is
/// skipped in CI.
///
/// So the product's actual claims — the seven situations in `scenarios.md` —
/// were asserted only in prose. "A capped build must not notify" is the
/// difference between this product being kept and being uninstalled, and nothing
/// checked it.
///
/// This replays a written-down machine: which processes exist, how much CPU each
/// burns, what the host total is, sample by sample. Same sampler, same
/// attribution, same detector, same gate as the app runs.
///
/// **What it deliberately does not test.** The sandbox (only a signed `.app` can
/// — see `probe/build-sandboxed.sh`), real kernel behaviour, or whether the
/// numbers below resemble a real machine. That last one is a genuine limit: a
/// scripted timeline tests the engine against what we *believe* a build looks
/// like. The figures used here are taken from `probe/FINDINGS.md` measurements
/// rather than invented, which narrows the gap without closing it.

// MARK: - Writing a machine down

/// One process in a scripted machine.
struct ScriptedProcess {
    let pid: pid_t
    let command: String
    /// Own-uid processes are measurable; anything else is denied, exactly as the
    /// kernel denies them (`probe/FINDINGS.md`: measurability is decided by uid).
    var uid: uid_t = getuid()
    var ppid: pid_t = 1
    /// Executable path, which is what family grouping keys on — the outermost
    /// `.app`, never the bundle id.
    var executablePath: String?
    /// Percent of one core this process burns during a phase. 100 = one core
    /// saturated. The timeline converts this to the mach ticks the kernel would
    /// have reported.
    var percentOfOneCore: Double = 0
    var residentBytes: UInt64 = 32 * 1024 * 1024

    var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: UInt64(pid) * 1000) }
}

/// A stretch of time during which the machine behaves one way.
struct ScenarioPhase {
    let name: String
    let duration: Duration
    var processes: [ScriptedProcess]
    /// Host-wide busy fraction, 0...1, of total machine capacity.
    ///
    /// Supplied rather than derived from the per-process figures, and that is the
    /// point: on a real Mac the two do not agree, because roughly 40 percentage
    /// points of busy CPU belong to other-uid processes we are denied. A scenario
    /// that computed this from what it can see would quietly assume the product
    /// can attribute everything, which is the one thing `probe/FINDINGS.md` says
    /// it cannot.
    var hostBusyFraction: Double
    var memoryPressure: MemoryPressureLevel = .normal
    var thermalState: ThermalState = .nominal
    var lowStorage: Bool = false
}

// MARK: - Replaying it

struct ScenarioTimeline {
    let phases: [ScenarioPhase]
    var cadence: Duration = .seconds(2)
    var logicalCoreCount: Int = 8
    var policy: IncidentPolicy = .default

    /// What one replayed sample produced, kept so a test can assert on the shape
    /// of the run rather than only its last frame.
    struct Frame {
        let at: Date
        let phase: String
        let observation: SystemObservation
        let attribution: CPUAttribution?
        let event: IncidentEvent?
        let decision: NotificationDecision?
    }

    struct Outcome {
        let frames: [Frame]

        var incidentsOpened: [Incident] {
            frames.compactMap { if case .opened(let i) = $0.event { i } else { nil } }
        }
        var incidentsClosed: [Incident] {
            frames.compactMap { if case .closed(let i) = $0.event { i } else { nil } }
        }
        /// The decisions that would actually have interrupted the user. This is
        /// the number S-4 turns on.
        var notificationsSent: [NotificationDecision] {
            frames.compactMap(\.decision).filter(\.shouldSend)
        }
        var suppressions: [SuppressionCause] {
            frames.compactMap(\.decision).compactMap(\.suppressionCause)
        }
        func frames(inPhase name: String) -> [Frame] { frames.filter { $0.phase == name } }
    }

    /// Mach ticks a process burning `percent` of one core would accumulate over
    /// `seconds`.
    ///
    /// Through the real timebase rather than a constant. CPU times are mach ticks,
    /// not nanoseconds, and treating them as nanoseconds under-reports by ~42x on
    /// Apple Silicon — a defect this project already had once. Using the same
    /// conversion the engine uses means a scenario cannot pass by agreeing with a
    /// mistake.
    private func ticks(percent: Double, seconds: Double) -> UInt64 {
        let nanos = seconds * 1_000_000_000 * (percent / 100)
        return UInt64(max(0, nanos / MachTime.nanosPerTick))
    }

    func run(gate: NotificationGate? = nil, startingAt start: Date = Date()) -> Outcome {
        var frames: [Frame] = []
        var detectorState = IncidentDetector.State()
        let detector = IncidentDetector(policy: policy)
        var gateState = NotificationGate.State()

        // Cumulative per-process ticks and host ticks. Counters are monotonic, and
        // the engine derives rates from deltas — so the timeline must accumulate
        // exactly as the kernel does rather than handing over pre-computed rates.
        var cpuTicks: [pid_t: UInt64] = [:]
        var hostBusy: UInt64 = 0
        var hostTotal: UInt64 = 0

        let clockOrigin = ContinuousClock().now
        var previousSnapshot: ProcessSnapshot?
        var previousHost = HostCPUSample(busy: 0, total: 0)
        var elapsed = Duration.zero

        for phase in phases {
            let steps = max(1, Int(phase.duration.totalSeconds / cadence.totalSeconds))
            for _ in 0..<steps {
                let step = cadence.totalSeconds

                for process in phase.processes {
                    cpuTicks[process.pid, default: 0] +=
                        ticks(percent: process.percentOfOneCore, seconds: step)
                }
                // Host counters advance by the whole machine's capacity, of which
                // `hostBusyFraction` was busy.
                let capacity = ticks(percent: 100 * Double(logicalCoreCount), seconds: step)
                hostBusy += UInt64(Double(capacity) * phase.hostBusyFraction)
                hostTotal += capacity

                // Snapshotted into immutables before the closures capture them:
                // the sampler's seams are @Sendable, and a captured `var` would
                // let the reader observe ticks from a later sample than the
                // enumeration it belongs to.
                let ticksNow = cpuTicks
                let running = phase.processes
                // The simulated instant this sample is taken at. Without this the
                // sampler stamps real wall-clock time, consecutive samples land
                // microseconds apart, and every CPU percentage comes out in the
                // millions.
                let sampledAt = clockOrigin + elapsed + cadence
                let sampler = ProcessSampler(
                    enumerator: {
                        .success(running.map {
                            ProcessSampler.TableEntry(
                                identity: $0.identity, command: $0.command,
                                uid: $0.uid, ppid: $0.ppid)
                        })
                    },
                    metricsReader: { pid in
                        guard let process = running.first(where: { $0.pid == pid })
                        else { return .exited }
                        // The uid rule, honoured rather than simulated loosely:
                        // another user's process is denied, and that is what puts
                        // load into the unattributable share.
                        guard process.uid == getuid() else { return .notPermitted }
                        return .measured(ProcessMetrics(
                            cpuTicks: ticksNow[pid] ?? 0,
                            residentBytes: process.residentBytes))
                    },
                    clock: { sampledAt })

                let snapshot = sampler.snapshot()
                let host = HostCPUSample(busy: hostBusy, total: hostTotal)
                elapsed += cadence
                let now = start.addingTimeInterval(elapsed.totalSeconds)

                var attribution: CPUAttribution?
                if let previousSnapshot {
                    attribution = CPUAttributionCalculator.attribution(
                        from: previousSnapshot, to: snapshot,
                        hostEarlier: previousHost, hostLater: host,
                        logicalCoreCount: logicalCoreCount)
                }

                var observation = SystemObservation(
                    at: now,
                    cpuBusyFraction: phase.hostBusyFraction,
                    memoryPressure: phase.memoryPressure,
                    thermalState: phase.thermalState,
                    lowStorage: phase.lowStorage)
                if let attribution {
                    observation.attribution = AttributionSample.from(
                        attribution: attribution, families: [])
                }

                let event = detector.observe(observation, state: &detectorState)

                var decision: NotificationDecision?
                if case .opened(let incident) = event {
                    decision = gate?.decide(incident: incident, state: &gateState)
                }

                frames.append(Frame(at: now, phase: phase.name, observation: observation,
                                    attribution: attribution, event: event, decision: decision))
                previousSnapshot = snapshot
                previousHost = host
            }
        }
        return Outcome(frames: frames)
    }
}
