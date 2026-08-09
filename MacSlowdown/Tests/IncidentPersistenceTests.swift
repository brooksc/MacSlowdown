import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-72: incident history persists across restarts, retained 30 days by default.
///
/// These tests cover the *wiring* — that `MonitorStore` reads what a previous run
/// wrote and that deleting history empties both the file and the screen. The store
/// itself, its schema and its retention are covered in `MetricsTests`.
///
/// **None of this is a restart test.** A second `MonitorStore` over the same file is
/// the closest an XCTest process can get; it does not exercise app launch, the
/// sandbox container path, or `AppDelegate`.

private func temporaryHistoryURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("IncidentPersistenceTests-\(UUID().uuidString)",
                                isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("incidents.json")
}

private func closedIncident(minutesAgo: Double, now: Date = Date()) -> Incident {
    let closed = now.addingTimeInterval(-minutesAgo * 60)
    return Incident(
        id: UUID(),
        beganAt: closed.addingTimeInterval(-300),
        triggeredAt: closed.addingTimeInterval(-180),
        recoveryStartedAt: closed.addingTimeInterval(-60),
        closedAt: closed,
        conditions: [.cpuSaturation],
        severity: .high,
        peakCPUBusyFraction: 0.91,
        peakMemoryPressure: .normal)
}

/// Every store here is pointed at a scratch folder. Deleting from the running
/// user's real container would be a cost a test may not impose.
@MainActor
private func store(historyAt url: URL?) -> MonitorStore {
    MonitorStore(
        policies: PolicyStore(),
        storage: StorageScreenModel(history: StorageHistory()),
        incidentHistory: IncidentHistoryStore(url: url),
        evidenceDirectory: url?.deletingLastPathComponent())
}

@MainActor
@Suite("Incident history reaches the app across a restart")
struct IncidentPersistenceWiringTests {
    /// The launch path: a store constructed over a file a previous run wrote shows
    /// that history immediately, before monitoring starts. A window can open before
    /// `start()`, and an empty list for those seconds looks exactly like history
    /// that did not survive.
    @Test("A newly constructed store shows what a previous run wrote")
    func historyIsReadAtConstruction() {
        let url = temporaryHistoryURL()
        let previousRun = IncidentHistoryStore(url: url)
        previousRun.record(closedIncident(minutesAgo: 30), settings: .default)
        previousRun.record(closedIncident(minutesAgo: 90), settings: .default)

        let restarted = store(historyAt: url)
        #expect(restarted.recentIncidents.count == 2)
        #expect(restarted.openIncident == nil)
    }

    /// Expired records must not appear even briefly. Load applies retention.
    @Test("An incident older than the retention period is not shown at launch")
    func expiredHistoryIsNotShown() {
        let url = temporaryHistoryURL()
        let previousRun = IncidentHistoryStore(url: url)
        previousRun.record(closedIncident(minutesAgo: 60), settings: .default)
        // Written under a longer retention, then read under the default 30 days.
        previousRun.record(
            closedIncident(minutesAgo: 60 * 24 * 45),
            settings: PrivacySettings(retention: .ninetyDays))

        #expect(store(historyAt: url).recentIncidents.count == 1)
    }

    /// A store with no file on it keeps nothing — which is what every test that
    /// drives the detector directly relies on, and why the persistent store is
    /// passed explicitly by the app rather than defaulted in.
    @Test("A memory-only store starts empty and writes nothing")
    func memoryOnlyStaysInMemory() {
        #expect(store(historyAt: nil).recentIncidents.isEmpty)
    }

    /// Deleting must empty the screen as well as the disk. Clearing only the file
    /// would leave the incidents in memory to be written straight back by the next
    /// close, and the user would watch deleted history reappear.
    @Test("Deleting history empties both the file and the list on screen")
    func deleteClearsMemoryAndDisk() {
        let url = temporaryHistoryURL()
        let previousRun = IncidentHistoryStore(url: url)
        previousRun.record(closedIncident(minutesAgo: 10), settings: .default)

        let monitor = store(historyAt: url)
        #expect(monitor.recentIncidents.count == 1)

        let removed = monitor.deleteRecordedHistory()
        #expect(removed.incidents == 1)
        #expect(!removed.isEmpty)
        #expect(monitor.recentIncidents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// Nothing recorded is reported as nothing recorded, not as a successful delete.
    @Test("Deleting an empty history reports that there was nothing to delete")
    func deletingNothingSaysSo() {
        let monitor = store(historyAt: temporaryHistoryURL())
        #expect(monitor.deleteRecordedHistory().isEmpty)
    }
}
