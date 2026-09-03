import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-66: four framework capabilities that existed, were tested, and had no owner
/// in the running app. These tests are about the wiring, not about the capabilities
/// — each of those is covered in `MetricsTests` already.

// MARK: - Fixtures

private func volume(
    availableBytes: UInt64, totalBytes: UInt64, isStartup: Bool = true
) -> VolumeCapacity {
    VolumeCapacity(
        url: URL(fileURLWithPath: isStartup ? "/" : "/Volumes/Other"),
        name: isStartup ? "Macintosh HD" : "Other",
        isStartupVolume: isStartup, isRemovable: false, isNetwork: false,
        totalBytes: totalBytes, availableBytes: availableBytes,
        purgeableEstimateBytes: nil)
}

private func snapshot(_ records: [ProcessRecord]) -> ProcessSnapshot {
    ProcessSnapshot(
        records: Dictionary(records.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a }),
        takenAt: ContinuousClock().now, sweepDuration: .milliseconds(2))
}

private func record(_ pid: pid_t, command: String, startTime: UInt64) -> ProcessRecord {
    ProcessRecord(
        identity: ProcessIdentity(pid: pid, startTime: startTime),
        command: command, uid: getuid(), ppid: 1,
        metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1024)))
}

private func sample(at timestamp: Date, busy: Double) -> HistorySample {
    HistorySample(
        timestamp: timestamp, totalBusyPercentOfOneCore: busy,
        attributedPercentOfOneCore: busy, unattributedPercentOfOneCore: 0,
        topContributors: [])
}

// MARK: - 1. Low storage reaches the detector (FR-041, FR-042)

@Suite("Low storage reaches the incident detector")
struct LowStorageWiringTests {
    private let detector = LowStorageDetector()

    @Test("A startup volume below both thresholds reads as low storage")
    func belowBothThresholds() {
        // 2 GB free of 128 GB: under 10% and under the 5 GB absolute floor.
        #expect(MonitorStore.isLowStorage(
            startupVolume: volume(availableBytes: 2 * 1_073_741_824,
                                  totalBytes: 128 * 1_073_741_824),
            detector: detector))
    }

    @Test("A large disk under 10% but with plenty of room is not low storage")
    func proportionalAloneIsNotEnough() {
        // 200 GB free of 4 TB is 4.9% — proportionally low, and not a problem.
        #expect(!MonitorStore.isLowStorage(
            startupVolume: volume(availableBytes: 200 * 1_073_741_824,
                                  totalBytes: 4096 * 1_073_741_824),
            detector: detector))
    }

    @Test("An unreadable startup volume claims nothing, in either direction")
    func noReadingClaimsNothing() {
        #expect(!MonitorStore.isLowStorage(startupVolume: nil, detector: detector))
    }

    /// The defect TASK-66 was opened for: `MonitorStore` built its observation
    /// without `lowStorage`, so this stream could never occur in the running app and
    /// a low-storage incident could never open however full the disk got.
    @Test("A sustained low-storage observation opens an incident, and it closes again")
    func sustainedLowStorageOpensAndCloses() {
        let incidentDetector = IncidentDetector()
        var state = IncidentDetector.State()
        let start = Date()

        func observe(_ offset: TimeInterval, lowStorage: Bool) -> IncidentEvent? {
            incidentDetector.observe(
                SystemObservation(
                    at: start.addingTimeInterval(offset), cpuBusyFraction: 0.1,
                    lowStorage: lowStorage),
                state: &state)
        }

        // Below the line, but not yet for the 60 s the condition must be sustained.
        #expect(observe(0, lowStorage: true) == nil)
        #expect(observe(30, lowStorage: true) == nil)

        guard case .opened(let incident)? = observe(60, lowStorage: true) else {
            Issue.record("a minute of low storage did not open an incident")
            return
        }
        #expect(incident.conditions == [.lowStorage])

        // Recovery holds for the hysteresis period before it closes. The first
        // clear observation starts the clock and reports nothing — an incident that
        // closed the moment space came back would be the transient-as-episode
        // mistake FR-006 and FR-011 exist to prevent.
        #expect(observe(90, lowStorage: false) == nil)
        #expect(observe(120, lowStorage: false) == nil)
        guard case .closed(let closed)? = observe(160, lowStorage: false) else {
            Issue.record("space came back and the incident never closed")
            return
        }
        #expect(closed.closedAt != nil)
        #expect(closed.conditions == [.lowStorage])
    }
}

// MARK: - 2. Retained history is reachable (FR-005)

@MainActor
@Suite("Retained history is readable by the UI")
struct RetainedHistoryTests {
    private func store(_ history: MetricsHistory) -> MonitorStore {
        MonitorStore(history: history, policies: PolicyStore(),
                     storage: StorageScreenModel(history: StorageHistory()))
    }

    @Test("The samples a view reads are the ones the framework retained")
    func samplesAreTheRetainedOnes() {
        let history = MetricsHistory()
        let start = Date()
        for index in 0..<5 {
            history.append(sample(at: start.addingTimeInterval(Double(index) * 2),
                                  busy: Double(index) * 10))
        }
        let store = store(history)
        #expect(store.retainedSamples.count == 5)
        #expect(store.retainedSamples.map(\.totalBusyPercentOfOneCore)
            == [0, 10, 20, 30, 40])
        #expect(store.retainedHistorySpan.totalSeconds == 8)
    }

    @Test("An incident window returns the samples around it, with a margin")
    func samplesAroundAnIncident() {
        let history = MetricsHistory()
        let start = Date()
        for index in 0..<600 {  // 20 minutes at a 2 s cadence
            history.append(sample(at: start.addingTimeInterval(Double(index) * 2),
                                  busy: 50))
        }
        let incident = Incident(
            id: UUID(),
            beganAt: start.addingTimeInterval(600),
            triggeredAt: start.addingTimeInterval(780),
            recoveryStartedAt: nil,
            closedAt: start.addingTimeInterval(900),
            conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)

        let window = store(history).retainedSamples(around: incident, margin: .seconds(120))
        // 480 s to 1020 s inclusive, at 2 s intervals.
        #expect(window.count == 271)
        #expect(window.first?.timestamp == start.addingTimeInterval(480))
        #expect(window.last?.timestamp == start.addingTimeInterval(1020))
    }

    @Test("An incident older than anything retained returns nothing rather than a guess")
    func incidentOutsideTheWindow() {
        let history = MetricsHistory()
        let start = Date()
        history.append(sample(at: start, busy: 10))
        let ancient = Incident(
            id: UUID(),
            beganAt: start.addingTimeInterval(-86400),
            triggeredAt: start.addingTimeInterval(-86000),
            recoveryStartedAt: nil,
            closedAt: start.addingTimeInterval(-85000),
            conditions: [.cpuSaturation], severity: .moderate,
            peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
        #expect(store(history).retainedSamples(around: ancient).isEmpty)
    }
}

// MARK: - 3. The app owns one PolicyStore (FR-016)

@MainActor
@Suite("The app owns a policy store")
struct PolicyOwnershipTests {
    private func store(_ policies: PolicyStore) -> MonitorStore {
        MonitorStore(policies: policies, storage: StorageScreenModel(history: StorageHistory()))
    }

    @Test("A policy set through the store is readable back through the same store")
    func setAndRead() {
        let store = store(PolicyStore())
        let identity = ResolvedIdentity(
            executablePath: "/Applications/Xcode.app/Contents/MacOS/Xcode",
            appBundlePath: "/Applications/Xcode.app",
            bundleID: "com.apple.dt.Xcode", teamID: nil)

        #expect(store.policies.policy(for: identity, displayName: "Xcode") == nil)

        store.policies.setPolicy(ApplicationPolicy(
            bundleID: "com.apple.dt.Xcode", bundlePath: "/Applications/Xcode.app",
            displayName: "Xcode", classification: .expected))

        #expect(store.policies.policy(for: identity, displayName: "Xcode")?.classification
            == .expected)

        // FR-016: revoking restores default behaviour completely.
        store.policies.removePolicy(id: "com.apple.dt.Xcode")
        #expect(store.policies.policy(for: identity, displayName: "Xcode") == nil)
    }

    /// The hazard the task named: two stores would disagree about what the user
    /// marked expected, and nothing would show the disagreement.
    @Test("There is one store, shared by every surface that reads a policy")
    func oneStore() {
        let policies = PolicyStore()
        let first = store(policies)
        let second = store(policies)
        first.policies.setPolicy(ApplicationPolicy(
            bundleID: "com.example.app", displayName: "Example", classification: .ignored))
        #expect(second.policies.policies.count == 1)
        #expect(MonitorStore.shared.policies === MonitorStore.defaultPolicies)
    }
}

// MARK: - 4. Storage capacity is recorded on the sampling loop

@MainActor
@Suite("Storage capacity is recorded by the store, not by the screen")
struct StorageOnTheLoopTests {
    private func store(_ model: StorageScreenModel) -> MonitorStore {
        MonitorStore(policies: PolicyStore(), storage: model)
    }

    @Test("A due check reads the volumes and appends to the capacity history")
    func recordsWithoutTheScreen() {
        // Memory-only history with no minimum interval, so this test writes nothing
        // to the container and does not wait a quarter of an hour.
        let model = StorageScreenModel(history: StorageHistory(minimumInterval: .zero))
        let store = store(model)
        #expect(model.history.readings(forVolume: "/").isEmpty)

        store.refreshStorageIfDue(now: ContinuousClock().now)

        // The startup volume is always mounted and always reports capacity.
        #expect(!model.history.readings(forVolume: "/").isEmpty)
        #expect(store.lastStorageCheck != nil)
    }

    @Test("Capacity is not re-read on every sample")
    func honoursTheCheckInterval() {
        let model = StorageScreenModel(history: StorageHistory(minimumInterval: .zero))
        let store = store(model)
        let now = ContinuousClock().now

        store.refreshStorageIfDue(now: now)
        let afterFirst = model.history.readings(forVolume: "/").count
        // Two seconds later — a sample, but not a storage check.
        store.refreshStorageIfDue(now: now.advanced(by: .seconds(2)))
        #expect(model.history.readings(forVolume: "/").count == afterFirst)

        store.refreshStorageIfDue(now: now.advanced(by: MonitorStore.storageCheckInterval))
        #expect(model.history.readings(forVolume: "/").count == afterFirst + 1)
    }
}

// MARK: - Disk rates: unavailable is not zero (FR-002, FR-009, FR-010)

@MainActor
@Suite("An unreadable disk is not an idle disk")
struct DiskAvailabilityTests {
    @Test("Before any rate has been measured, nothing is claimed")
    func nilBeforeFirstRate() {
        let store = MonitorStore(policies: PolicyStore(),
                                 storage: StorageScreenModel(history: StorageHistory()))
        #expect(store.diskRates == nil)
        #expect(store.diskThroughput == "Not available")
    }

    @Test("A measured rate is stated as a rate, and zero means measured zero")
    func measuredRate() {
        #expect(Presentation.diskThroughput(DiskRates.zero).contains("/s read"))
        #expect(Presentation.diskThroughput(nil) == "Not available")
        #expect(NowPresentation.diskWrite(nil) == "Not available")
        #expect(NowPresentation.diskWrite(DiskRates(
            readBytesPerSecond: 0, writeBytesPerSecond: 1_048_576)).hasSuffix("/s"))
    }
}

// MARK: - 5. LifecycleTracker is wired in (FR-045, FR-046 as narrowed)

@MainActor
@Suite("Relaunches come from the real lifecycle tracker")
struct LifecycleWiringTests {
    private func store() -> MonitorStore {
        MonitorStore(policies: PolicyStore(),
                     storage: StorageScreenModel(history: StorageHistory()))
    }

    @Test("A process replaced by another under the same command counts as one relaunch")
    func replacementIsARelaunch() {
        let store = store()
        let before = snapshot([record(100, command: "Helper", startTime: 1)])
        let after = snapshot([record(101, command: "Helper", startTime: 2)])

        store.recordLifecycle(from: before, to: after)

        #expect(store.lifecycleEvents.count == 2)
        #expect(store.relaunchCount(forCommands: ["Helper"]) == 1)
        #expect(store.relaunchCount(forCommands: ["Something else"]) == 0)
    }

    /// A recycled PID must read as a replacement, not as continuity. macOS wraps
    /// PID allocation at 99999 and it is not theoretical.
    @Test("A recycled PID reads as a replacement rather than as the same process")
    func recycledPIDIsAReplacement() {
        let store = store()
        let before = snapshot([record(99998, command: "Helper", startTime: 1)])
        let after = snapshot([record(99998, command: "Helper", startTime: 9_999)])

        store.recordLifecycle(from: before, to: after)
        #expect(store.relaunchCount(forCommands: ["Helper"]) == 1)
    }

    @Test("A process that exited and did not come back is not a relaunch")
    func exitAloneIsNotARelaunch() {
        let store = store()
        let before = snapshot([record(100, command: "Helper", startTime: 1)])
        let after = snapshot([])

        store.recordLifecycle(from: before, to: after)
        #expect(store.lifecycleEvents.count == 1)
        #expect(store.relaunchCount(forCommands: ["Helper"]) == 0)
    }

    @Test("An unchanged table produces no events")
    func noChangeNoEvents() {
        let store = store()
        let table = snapshot([record(100, command: "Helper", startTime: 1)])
        store.recordLifecycle(from: table, to: table)
        #expect(store.lifecycleEvents.isEmpty)
        #expect(store.relaunchCount(forCommands: ["Helper"]) == 0)
    }

    /// Four generations of one command quitting and being replaced, driven through
    /// the store the way the sampling loop drives it: **group, then record**.
    ///
    /// The pid is our own, deliberately. TASK-84 restricts a relaunch pattern to a
    /// process that resolves to a `.app`, and the only way to prove that end to end
    /// is a pid the real `ProcessIdentityResolver` really can resolve into one. This
    /// bundle is app-hosted, so `getpid()` is `MacSlowdown.app`'s own executable.
    /// A synthetic pid would resolve to nothing and — correctly — produce no
    /// pattern, which is what `commandChurnOpensNothing` below asserts.
    ///
    /// `regroup` before `recordLifecycle` is not test scaffolding: it is the order
    /// `run()` uses, and it is what makes the identity a warm cache hit rather than
    /// a resolution on the sampling path.
    private func quitAndReplace(
        _ store: MonitorStore, command: String, pid: pid_t, generations: Int
    ) {
        var last = snapshot([record(pid, command: command, startTime: 1)])
        store.regroup(from: last)
        for generation in 2...generations {
            let next = snapshot([record(pid, command: command,
                                        startTime: UInt64(generation))])
            store.regroup(from: next)
            store.recordLifecycle(from: last, to: next)
            last = next
        }
    }

    @Test("Repeated exits of an application rise to a stated pattern")
    func patternsAreReported() {
        let store = store()
        quitAndReplace(store, command: "Crashy", pid: getpid(), generations: 5)

        #expect(store.relaunchCount(forCommands: ["Crashy"]) == 4)
        let patterns = store.relaunchPatterns(forCommands: ["Crashy"])
        #expect(patterns.first?.exits == 4)
        #expect(patterns.first?.confidence == .moderate)
    }

    /// **The defect TASK-84 exists for.** Measured over one 901 s window on a
    /// developer Mac, 28 commands reached three exits — `swift-frontend` 112 times,
    /// `yes` 60, `zsh` 42 — and every one of them opened, or kept open, an incident
    /// that never closed. None was an application.
    ///
    /// The exits are still recorded and still counted, because the evidence is real
    /// and a user looking at a family should see it. What must not happen is an
    /// incident.
    @Test("Ordinary command churn is recorded but opens nothing")
    func commandChurnOpensNothing() {
        let store = store()
        // A pid that is not ours, so it resolves to no application bundle — the
        // same answer the resolver gives for a compiler that has already exited.
        quitAndReplace(store, command: "swift-frontend", pid: 999_98, generations: 20)

        #expect(store.relaunchCount(forCommands: ["swift-frontend"]) == 19,
                "the exits are evidence and must still be recorded (FR-045)")
        #expect(store.relaunchPatterns(forCommands: ["swift-frontend"]).isEmpty)

        let observation = store.currentObservation(at: Date(), cpuBusyFraction: 0.05)
        #expect(observation.lifecycleFindings.isEmpty)
        #expect(!observation.breaches(.repeatedApplicationQuits, policy: .default))

        var detectorState = IncidentDetector.State()
        let event = IncidentDetector().observe(observation, state: &detectorState)
        #expect(event == nil, "nineteen exits of a compiler opened an incident")
    }

    // MARK: TASK-71 — the pattern reaches the detector, not only the screen

    /// The gap TASK-71 closed. `relaunchPatterns` was published and read by views,
    /// and the detector was never offered it, so the one episode FR-046 exists for
    /// could not open an incident. Nothing failed while that was true — a gap in
    /// what is *handed over* is invisible to tests of either side, which is why this
    /// asserts on the observation rather than on either component.
    @Test("A relaunch pattern reaches the observation the detector judges")
    func patternsReachTheDetector() {
        let store = store()
        quitAndReplace(store, command: "Crashy", pid: getpid(), generations: 5)

        // A quiet machine: nothing here can pass because a resource threshold was
        // crossed as well.
        let observation = store.currentObservation(at: Date(), cpuBusyFraction: 0.05)
        #expect(observation.lifecycleFindings.first?.command == "Crashy")
        #expect(observation.breaches(.repeatedApplicationQuits, policy: .default))
        #expect(!observation.breaches(.cpuSaturation, policy: .default))

        // And through the detector, which since FR-046 amendment 5 must open
        // nothing on this evidence alone (TASK-102). The hand-over above is still
        // what this test is for: the pattern has to reach the observation, because
        // an incident opened for a *resource* reason carries it as evidence. What
        // changed is only that the pattern may no longer be the reason.
        var detectorState = IncidentDetector.State()
        let event = IncidentDetector().observe(observation, state: &detectorState)
        #expect(event == nil, "a relaunch pattern opened an incident on a calm machine")
        #expect(detectorState.current == nil)
    }

    /// With no pattern the observation must claim nothing, or every quiet sample
    /// would keep a lifecycle incident alive.
    @Test("With nothing quitting, the observation breaches no lifecycle condition")
    func noPatternNoBreach() {
        let store = store()
        let observation = store.currentObservation(at: Date(), cpuBusyFraction: 0.05)
        #expect(observation.lifecycleFindings.isEmpty)
        #expect(!observation.breaches(.repeatedApplicationQuits, policy: .default))
    }

    /// Before monitoring has run, a count of zero means "we have not been looking",
    /// and the interface must be able to tell the difference (FR-002).
    @Test("Nothing is claimed before we have watched long enough")
    func notWatchedLongEnough() {
        let store = store()
        #expect(store.observedDuration == .zero)
        #expect(!store.hasObservedLongEnough())
    }
}

/// TASK-65.14: the Now screen's per-metric freshness is only honest if the metric
/// it calls "current while the rest is late" really is pushed to us rather than
/// copied on the next sweep.
@MainActor
@Suite("Memory pressure does not wait on the sampling loop")
struct MemoryPressureLivenessTests {
    @Test("A store that is not running makes no claim that pressure is live")
    func notRunningIsNotLive() {
        let store = MonitorStore()
        #expect(!store.memoryPressureIsLive)
    }

    /// Starting the store subscribes to the kernel's dispatch source, which is what
    /// entitles the pressure card to say "current" while every other figure on the
    /// screen carries an age. Stopping withdraws the claim rather than leaving it
    /// standing over a subscription that is gone (FR-002).
    @Test("Starting subscribes to the kernel's notifications, and stopping withdraws")
    func startingMakesPressureLive() {
        let store = MonitorStore()
        store.start()
        #expect(store.memoryPressureIsLive)
        store.stop()
        #expect(!store.memoryPressureIsLive)
    }
}
