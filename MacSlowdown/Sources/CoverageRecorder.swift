import AppKit
import Foundation
import Metrics
import Observation

/// Keeps the coverage record while monitoring runs (TASK-113).
///
/// The model is in `Metrics.CoverageLog`, which knows nothing about launches,
/// sleep or files. This is the part that has to talk to the machine: it decides
/// **why** a gap happened, which is the one judgement in the whole device, and it
/// owns the throttled write to disk.
///
/// Three reasons, and each is established rather than assumed:
///
/// - `appNotRunning` — the first observation after this process started watching
///   follows a gap by construction, whether the app was quit, crashed, or updated.
/// - `systemAsleep` — only ever from an observed `NSWorkspace.willSleepNotification`.
///   Never inferred from a long gap, because a long gap is equally consistent with
///   the app having been killed.
/// - `noReadings` — everything else: the loop was running and readings stopped
///   arriving for longer than the tolerance. It states what is true without
///   claiming to know the cause.
///
/// Observable so a view redraws when the record changes; the store holds it, and
/// nothing but the sampling loop writes to it.
@MainActor
@Observable
final class CoverageRecorder {
    private(set) var log: CoverageLog

    /// Whether this recorder has observed anything since it started watching. The
    /// first observation of a launch is what makes the preceding gap
    /// `appNotRunning` — the fact we are here at all is the evidence.
    private var hasObservedSinceLaunch = false
    /// A sleep we were told about and have not yet accounted for. Consumed by the
    /// next observation: if that observation extends the current interval the sleep
    /// was too short to leave a hole, and if it opens a new one this is the reason.
    private var pendingSleep = false
    private var sleepObserver: (any NSObjectProtocol)?

    @ObservationIgnored private let store: CoverageStore
    /// The settings the last flush used, so the sleep handler can write without
    /// being handed them again at a moment when nothing is calling us.
    @ObservationIgnored private var settings: PrivacySettings = .default

    init(store: CoverageStore) {
        self.store = store
        // Read at construction rather than at `start()`: a window can open before
        // monitoring begins, and an empty record for those seconds is indistinguishable
        // on screen from a record that did not survive the restart.
        self.log = store.load() ?? CoverageLog()
    }

    /// Begins a watch. Registers for sleep notifications; does **not** record an
    /// observation, because starting the loop is not evidence that it sampled.
    func beginWatching(settings: PrivacySettings) {
        self.settings = settings
        hasObservedSinceLaunch = false
        guard sleepObserver == nil else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // `queue: .main` guarantees this runs on the main thread, so the
            // isolation is real rather than assumed. A `Task { @MainActor in }`
            // would be correct too and might not run before the machine sleeps,
            // which would lose both the reason and the flush.
            MainActor.assumeIsolated { self?.systemWillSleep() }
        }
    }

    /// Records that a sample arrived, and flushes if a write is due.
    ///
    /// `cadence` is the interval in force, so the continuity tolerance moves with
    /// FR-031's adaptive sampling instead of being a fixed number of seconds that
    /// means one thing at 1 s and another at 5 s.
    func observe(at date: Date, cadence: Duration, settings: PrivacySettings) {
        self.settings = settings
        // Retention first, so a machine left running for months does not accumulate
        // a record it is not allowed to keep — the same rule, and the same reason,
        // as enforcing incident retention on the sampling loop rather than when a
        // screen happens to open.
        log.prune(before: date.addingTimeInterval(-settings.retention.duration.totalSeconds))
        log.observe(
            at: date,
            tolerance: CoverageLog.tolerance(cadence: cadence),
            resumingAfter: reasonForResuming())
        hasObservedSinceLaunch = true
        pendingSleep = false
        store.flush(log, settings: settings, now: date)
    }

    /// Ends the watch and writes what we have.
    ///
    /// Forced, because the whole point of the record is that it survives the thing
    /// that stopped us — and a throttled write here would leave up to a minute of
    /// genuine coverage looking like a gap.
    func endWatching(at date: Date = Date()) {
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        store.flush(log, settings: settings, now: date, force: true)
    }

    /// What "delete all history" does to the record (FR-029).
    ///
    /// `StoredData.deleteRecordedEvidence` removes `coverage.json` along with
    /// everything else that is not the user's rules, so the in-memory record has to
    /// go the same way or every surface would keep claiming coverage whose evidence
    /// no longer exists. The record restarts from now: we are still watching, and
    /// everything before this moment is genuinely beyond our record.
    func forgetRecordedHistory(at date: Date = Date()) {
        log.forgetting(at: date)
        hasObservedSinceLaunch = true
        store.flush(log, settings: settings, now: date, force: true)
    }

    private func systemWillSleep() {
        pendingSleep = true
        // Written before the machine goes down, so the coverage up to this moment is
        // on disk. Without it a night's sleep would begin with a minute of real
        // watching recorded as a gap.
        store.flush(log, settings: settings, now: Date(), force: true)
    }

    private func reasonForResuming() -> CoverageGapReason {
        if pendingSleep { return .systemAsleep }
        if !hasObservedSinceLaunch { return .appNotRunning }
        return .noReadings
    }
}
