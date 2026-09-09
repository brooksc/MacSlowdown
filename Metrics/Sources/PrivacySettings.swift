import Foundation

/// What the app keeps, and for how long (FR-029).
///
/// Every default here is the most private option that still lets the product
/// work. FR-029 requires core features work without cloud disclosure, and the app
/// makes no network calls at all — there is no telemetry code path to enable,
/// which is why consent flags for it do not appear as settings that merely
/// default to off.
public struct PrivacySettings: Sendable, Codable, Equatable {
    /// How long incidents are kept.
    public var retention: Retention
    /// Whether history survives a restart. Off keeps everything in memory only.
    public var persistAcrossRestarts: Bool
    /// Whether executable paths are recorded alongside process names.
    ///
    /// Window titles are deliberately absent: TASK-46 measured them as
    /// unavailable without Screen Recording, so offering the choice would imply a
    /// capability we do not have.
    public var recordFilePaths: Bool

    public enum Retention: String, Sendable, Codable, CaseIterable {
        case sevenDays, thirtyDays, ninetyDays

        public var duration: Duration {
            switch self {
            case .sevenDays: .seconds(7 * 86_400)
            case .thirtyDays: .seconds(30 * 86_400)
            case .ninetyDays: .seconds(90 * 86_400)
            }
        }

        public var label: String {
            switch self {
            case .sevenDays: "7 days"
            case .thirtyDays: "30 days"
            case .ninetyDays: "90 days"
            }
        }
    }

    public init(retention: Retention = .thirtyDays,
                persistAcrossRestarts: Bool = true,
                recordFilePaths: Bool = false) {
        self.retention = retention
        self.persistAcrossRestarts = persistAcrossRestarts
        self.recordFilePaths = recordFilePaths
    }

    public static let `default` = PrivacySettings()

    /// What the app can truthfully say about where data goes.
    ///
    /// Stated as fact rather than as a promise, because it is checkable: the app
    /// contains no networking code.
    public static let dataHandlingStatement =
        "Everything MacSlowdown records stays on this Mac. There is no account, no "
        + "server and no analytics. The only way anything leaves is if you export a "
        + "report and send it yourself."

    /// Categories of data held, for the "see exactly what is stored" disclosure
    /// FR-029 requires.
    ///
    /// **Hand-written, and therefore the thing most likely to go stale.** It did:
    /// user-reported slowdowns became a stored category when
    /// `SlowdownReportStore` started writing `slowdown-reports.json`, and this list
    /// did not mention them for a while. An incomplete disclosure is worse than no
    /// disclosure — it reads as a complete one — so anything that writes to the
    /// container gets a row here in the same change that makes it write.
    public static let storedCategories: [(category: String, detail: String)] = [
        ("Resource measurements",
         "CPU, memory, swap, disk and storage figures sampled every few seconds."),
        ("Process names and identifiers",
         "The names, process IDs and signing identifiers of running applications."),
        ("Incidents",
         "Periods of sustained degradation, with the measurements behind them."),
        // The one row that is the user's own words rather than our measurements,
        // and it says so. What it does *not* say is that reports are kept longer
        // than everything else: design 6d proposed "kept until you delete it", and
        // the build applies the same retention period and count bound to reports as
        // to incidents. Describing the design's intention rather than the code's
        // behaviour is the failure this whole disclosure exists to avoid.
        ("Slowdowns you reported",
         "The moment you told MacSlowdown it felt slow, and the readings it had "
            + "already kept from around then. This is the one thing here that is "
            + "yours rather than ours. Kept for the same period as incidents, and "
            + "removed by the same \"Delete all history\"."),
        ("Your rules",
         "The applications and conditions you set rules for, and grouping "
            + "corrections. Kept when history is deleted, because they are your "
            + "decisions rather than recorded evidence."),
        ("Machine context",
         "Model, chip, core count, memory size and macOS version. No serial number."),
    ]
}

/// Applies retention (FR-029).
public enum RetentionPolicy {
    /// Incidents still within the retention window.
    public static func retained(
        _ incidents: [Incident],
        settings: PrivacySettings,
        now: Date = Date()
    ) -> [Incident] {
        let cutoff = now.addingTimeInterval(-settings.retention.duration.totalSeconds)
        return incidents.filter { ($0.closedAt ?? $0.beganAt) >= cutoff }
    }

    /// Incidents that have aged out and should be removed.
    public static func expired(
        _ incidents: [Incident],
        settings: PrivacySettings,
        now: Date = Date()
    ) -> [Incident] {
        let kept = Set(retained(incidents, settings: settings, now: now).map(\.id))
        return incidents.filter { !kept.contains($0.id) }
    }
}
