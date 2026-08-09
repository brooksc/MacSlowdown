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

    @Test("Repeated exits rise to a stated pattern")
    func patternsAreReported() {
        let store = store()
        var last = snapshot([record(100, command: "Crashy", startTime: 1)])
        for generation in 2...5 {
            let next = snapshot([record(pid_t(100 + generation), command: "Crashy",
                                        startTime: UInt64(generation))])
            store.recordLifecycle(from: last, to: next)
            last = next
        }
        #expect(store.relaunchCount(forCommands: ["Crashy"]) == 4)
        let patterns = store.relaunchPatterns(forCommands: ["Crashy"])
        #expect(patterns.first?.exits == 4)
        #expect(patterns.first?.confidence == .moderate)
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
