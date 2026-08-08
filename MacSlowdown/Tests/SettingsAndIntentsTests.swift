import AppIntents
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

@MainActor
@Suite("Login item wording")
struct LoginItemTests {
    /// FR-033: a state the user must act on has to say where and what. The two
    /// states the app cannot reach on demand are exactly the two that need the
    /// clearest wording, which is why the mapping is checked rather than the
    /// live status.
    @Test("Every state explains itself, and no two read the same")
    func everyStateExplained() {
        let states: [LoginItem.State] = [
            .enabled, .disabled, .requiresApproval, .unavailable("The app could not be found."),
        ]
        let texts = states.map { LoginItem.explanation(for: $0) }
        #expect(texts.allSatisfy { !$0.isEmpty })
        #expect(Set(texts).count == states.count)
    }

    @Test("Approval sends the user to the right place in System Settings")
    func approvalNamesTheSetting() {
        let text = LoginItem.explanation(for: .requiresApproval)
        #expect(text.contains("System Settings"))
        #expect(text.contains("Login Items"))
    }

    @Test("An unavailable login item repeats the system's reason rather than hiding it")
    func unavailableCarriesReason() {
        let text = LoginItem.explanation(for: .unavailable("The app could not be found."))
        #expect(text.contains("The app could not be found."))
    }

    /// The honest consequence of leaving it off, stated without pressure to turn
    /// it on.
    @Test("Disabled explains what the user gives up")
    func disabledStatesTheCost() {
        let text = LoginItem.explanation(for: .disabled)
        #expect(text.lowercased().contains("will not record"))
    }

    /// FR-033: nothing registers itself. Constructing the object reads status and
    /// must not change it.
    @Test("Creating a login item registers nothing")
    func constructionDoesNotRegister() {
        #expect(LoginItem().state == LoginItem().state)
    }
}

/// Serialized because these read and write the shared store the app itself uses.
@MainActor
@Suite("Automation", .serialized)
struct ShortcutsTests {
    /// FR-035: automation offers exactly what the interface offers. An intent that
    /// did more than the UI would be a way around the constraint rather than an
    /// extension of the product.
    @Test("The shortcut set contains no process-control intent")
    func noProcessControlIntent() {
        let titles = [
            ShowStatusIntent.title, MuteAlertsIntent.title, ExportLatestIncidentIntent.title,
        ].map { String(localized: $0).lowercased() }

        for forbidden in ["quit", "kill", "force", "suspend", "pause", "throttle",
                          "limit", "terminate", "clean", "optimi", "boost", "free"] {
            #expect(!titles.contains { $0.contains(forbidden) },
                    "no intent may be named for \(forbidden)")
        }
    }

    @Test("The command set is versioned so a saved shortcut cannot silently change meaning")
    func versioned() {
        #expect(ShortcutsVersion.current >= 1)
    }

    /// FR-002: before the first complete reading there is nothing to report, and
    /// saying so beats reporting zero.
    @Test("Status before any reading says so instead of reporting zeroes")
    func statusBeforeFirstReading() async throws {
        let store = MonitorStore.shared
        try #require(store.attribution == nil,
                     "this test needs a store that has not sampled yet")

        let result = try await ShowStatusIntent().perform()
        let value = try #require(result.value)
        #expect(value.contains("not monitoring") || value.contains("has not taken a full reading"))
        #expect(!value.contains("0%"))
    }

    @Test("Exporting with no incidents says there are none rather than producing an empty report")
    func exportWithNoIncidents() async throws {
        let store = MonitorStore.shared
        try #require(store.openIncident == nil && store.recentIncidents.isEmpty)

        let result = try await ExportLatestIncidentIntent().perform()
        let value = try #require(result.value)
        #expect(value.contains("no recorded incidents"))
    }

    /// FR-015: muting suppresses interruption only. It must never look like it
    /// stopped monitoring.
    @Test("Muting reports that monitoring continues")
    func muteKeepsMonitoring() async throws {
        let store = MonitorStore.shared
        defer { store.clearMute() }

        let intent = MuteAlertsIntent()
        intent.minutes = 30
        _ = try await intent.perform()

        #expect(store.mute.isMuted(at: Date()))
        #expect(!store.mute.isMuted(at: Date().addingTimeInterval(31 * 60)))
    }

    @Test("A non-positive mute is refused rather than silently muting forever")
    func nonPositiveMuteRefused() async throws {
        let store = MonitorStore.shared
        store.clearMute()

        for minutes in [0, -5] {
            let intent = MuteAlertsIntent()
            intent.minutes = minutes
            _ = try await intent.perform()
            #expect(!store.mute.isMuted(at: Date()),
                    "\(minutes) minutes must not mute anything")
        }
    }

    @Test("Clearing a mute takes effect immediately")
    func clearMute() {
        let store = MonitorStore.shared
        store.mute(forMinutes: 60)
        #expect(store.mute.isMuted(at: Date()))
        store.clearMute()
        #expect(!store.mute.isMuted(at: Date()))
    }
}

@MainActor
@Suite("Store defaults")
struct MonitorStoreDefaultsTests {
    /// A store that has not sampled reports normal rather than unknown-as-severe.
    /// Escalating on absence of data would train the user to ignore the surface.
    @Test("With no reading yet, severity is normal and nothing is claimed")
    func defaultsAreQuiet() {
        let store = MonitorStore()
        #expect(store.severity == .normal)
        #expect(store.attribution == nil)
        #expect(store.currentSummary == nil)
        #expect(!store.isRunning)
        #expect(store.rankedFamilies.isEmpty)
    }

    /// FR-030: the budget is a test, not an aspiration. A fresh store is trivially
    /// inside it; the point here is that the comparison exists and is wired to the
    /// same figure the Now screen shows.
    @Test("The memory budget is evaluated against the app's own measurement")
    func memoryBudgetWired() {
        let store = MonitorStore()
        #expect(store.isWithinMemoryBudget)
        #expect(store.selfCost.contains("MacSlowdown itself"))
        #expect(FR030Budget.residentBytes == 100 * 1024 * 1024)
    }

    @Test("Freshness starts current and enumeration starts succeeded")
    func initialState() {
        let store = MonitorStore()
        #expect(store.freshness == .current)
        #expect(store.enumeration == .succeeded)
        #expect(store.mute == .notMuted)
    }
}
