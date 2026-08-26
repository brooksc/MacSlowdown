import AppKit
import Darwin
import Foundation
import Metrics
import Observation

/// How fresh the displayed readings are.
///
/// FR-002 requires stale or unavailable values to be labeled, and FR-032 requires
/// the app to stay usable under severe load — which is exactly when sampling falls
/// behind. Showing a stale number as though it were current would be the kind of
/// unsupported claim FR-038 forbids, so freshness is part of the state.
enum Freshness: Equatable {
    case current
    /// The last complete reading, with its age. Nothing is estimated forward.
    case stale(age: Duration)

    var isStale: Bool { if case .stale = self { true } else { false } }
}

/// Overall condition, for the compact status surface (FR-001).
///
/// Severity is never conveyed by colour alone (FR-034), so each case carries a
/// word and a symbol as well.
enum Severity: Int, Comparable, CaseIterable {
    case normal, elevated, severe

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .severe: "Severe"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "gauge.with.dots.needle.33percent"
        case .elevated: "gauge.with.dots.needle.67percent"
        case .severe: "gauge.with.dots.needle.100percent"
        }
    }

    /// Derived from the share of total machine capacity in use. Thresholds are
    /// provisional; FR-006's configurable, hysteresis-backed detection is m-2 work.
    static func forBusyShareOfMachine(_ share: Double) -> Severity {
        switch share {
        case ..<0.6: .normal
        case ..<0.85: .elevated
        default: .severe
        }
    }
}

/// Observable state for the whole app.
///
/// Owns the sampling loop and every state transition; views read from it and never
/// sample, compute or cache on their own.
@MainActor
@Observable
final class MonitorStore {
    /// Shared because the app delegate starts monitoring at launch, independently
    /// of any view. Tying the sampling loop to a view's lifecycle meant that
    /// hiding the menu bar item stopped monitoring altogether.
    static let shared = MonitorStore(
        alertSettings: .shared, incidentHistory: MonitorStore.persistentIncidentHistory)

    private(set) var attribution: CPUAttribution?
    private(set) var families: [ProcessFamily] = []
    private(set) var freshness: Freshness = .current
    /// Whether the process table could be read at all. An empty inventory means
    /// opposite things depending on this.
    private(set) var enumeration: EnumerationOutcome = .succeeded
    /// The incident currently open, if any (FR-011).
    private(set) var openIncident: Incident?
    /// Incidents that have closed, most recent first. Bounded.
    private(set) var recentIncidents: [Incident] = []
    /// Current sampling cadence, exposed so the user can inspect it (FR-031).
    private(set) var cadence: SamplingCadence?
    private(set) var memoryPressure: MemoryPressureLevel = .normal
    /// Whether the kernel's pressure notifications are reaching this store, rather
    /// than the level only being copied on the sampling loop's next pass.
    ///
    /// This is what makes the Now screen's per-metric freshness a fact rather than
    /// a decoration: when it is true, memory pressure is current even while every
    /// other figure on the screen is late, because a dispatch source pushed it
    /// (FR-007's two-second requirement, FR-032). When it is false — a store that
    /// was never started — pressure is exactly as old as the last sample and the
    /// screen says so.
    private(set) var memoryPressureIsLive = false
    private(set) var thermalState: ThermalState = .nominal
    private(set) var power: PowerContext = PowerSignals.current()
    private(set) var pagingRates: PagingRates = .zero
    /// Swap bytes in use, as the sampling loop last read them (FR-008).
    ///
    /// Read here rather than by a view for the same reason `startupVolume` is:
    /// every surface has to quote the same figure. Two views calling
    /// `SwapSignals.swapUsage()` independently would read at different moments and
    /// could disagree about how much swap exists, which a user would reasonably
    /// read as one of them being wrong.
    ///
    /// Nil until the first sample, and nil again if `sysctl vm.swapusage` stops
    /// answering. Never defaulted to a zeroed `SwapUsage`: a swap file we could not
    /// read is not an empty one (FR-002).
    private(set) var swapUsage: SwapUsage?
    /// Aggregate disk throughput, or nil when there is no rate to report (FR-009).
    ///
    /// Optional rather than `.zero` deliberately. A driver that will not report its
    /// statistics and a genuinely idle disk are different facts, and defaulting to
    /// zero presented the first as the second — the unavailable-reported-as-measured
    /// failure FR-002 and FR-010 forbid. Nil also covers the first sample, where no
    /// delta exists yet: a rate needs two readings.
    private(set) var diskRates: DiskRates?
    /// Whether the startup volume is currently below the low-storage warning line
    /// (FR-041, FR-042).
    ///
    /// Scoped to the startup volume deliberately: it is the one whose exhaustion
    /// degrades the machine. A full external disk is a problem for the user's files,
    /// not a cause of the slowdown this app exists to explain, and raising an
    /// incident for it would be a claim we cannot support.
    ///
    /// False when the startup volume did not report its capacity. That is "no
    /// measurement", not "plenty of room" — but it is also not evidence of a
    /// shortage, and FR-002 forbids inventing one.
    private(set) var isLowStorage = false
    /// When the volumes were last read, or nil before the first read.
    private(set) var lastStorageCheck: Date?

    /// The startup volume's capacity as the sampling loop last read it, or nil if
    /// it has not been read yet or did not report.
    ///
    /// Exposed so every surface quotes the same figure. Two views calling
    /// `StorageSignals.snapshot()` independently would read at different moments
    /// and could disagree about free space, which a user would reasonably read as
    /// one of them being wrong.
    var startupVolume: VolumeCapacity? { storage.startupVolume?.capacity }
    /// Our own cost, measured the same way we measure anything else.
    ///
    /// The headless OverheadHarness reports ~16 MB, but that runs no SwiftUI. The
    /// real app measured 92 MB against FR-030's 100 MB budget, so the figure the
    /// budget actually applies to has to come from the app itself.
    private(set) var ownResidentBytes: UInt64 = 0
    private(set) var ownCPUPercentOfOneCore: Double = 0
    private(set) var mute: MuteState = .notMuted

    /// FR-030 self-report, as the design's Now screen shows it.
    var selfCost: String {
        Presentation.selfCost(cpuPercentOfOneCore: ownCPUPercentOfOneCore,
                              residentBytes: ownResidentBytes)
    }

    var isWithinMemoryBudget: Bool { ownResidentBytes <= FR030Budget.residentBytes }

    /// Aggregate disk throughput, with the per-application limitation stated
    /// alongside it rather than left as a silent omission (FR-009).
    var diskThroughput: String { Presentation.diskThroughput(diskRates) }

    /// Swap activity, described without implying memory can be freed (FR-036).
    var swapActivity: String { Presentation.swapActivity(pagingRates) }

    /// An evidence-based account of the open incident, or the most recent one.
    var currentSummary: IncidentSummary? {
        guard let incident = openIncident ?? recentIncidents.first else { return nil }
        return IncidentSummarizer.summarize(incident: incident, attribution: attribution)
    }

    /// Applications that led the attribution in several recent slowdowns (FR-013).
    ///
    /// Empty until there is enough recorded to claim a pattern — three attributable
    /// incidents with one application leading three of them. Nothing here is
    /// reconstructed from live state; it reads only what each incident recorded
    /// while it was happening.
    var recurringApplications: [ApplicationRecurrence] {
        IncidentRecurrence.leadingApplications(
            in: (openIncident.map { [$0] } ?? []) + recentIncidents)
    }

    /// Links a completed user action to the incident it happened during (FR-050).
    ///
    /// Returns whether a link was made. It is `false` whenever the action did not
    /// run or fell outside every incident's window — and a caller must not read a
    /// `false` as "it worked anyway", because the whole point of the link is that
    /// "recovered after you acted" may only be said when an action was genuinely
    /// recorded. Nothing here infers that a user acted from the machine improving.
    @discardableResult
    func record(action verification: ActionVerification) -> Bool {
        if detectorState.record(verification) {
            openIncident = detectorState.current
            return true
        }
        if let index = recentIncidents.firstIndex(
            where: { $0.covers(verification.requestedAt) }) {
            let linked = recentIncidents[index].record(verification)
            if linked { persistRecentIncidents() }
            return linked
        }
        return false
    }

    /// Writes the closed-incident list back after one of them was mutated in place.
    ///
    /// Without this an action or a suppression linked to a closed incident lived
    /// only in memory, and the restart that the history now survives would have
    /// dropped exactly the evidence that lets a report say "recovered after you
    /// acted" (FR-050) or "not alerted, because you marked this expected" (FR-016).
    private func persistRecentIncidents() {
        recentIncidents = incidents.replace(recentIncidents, settings: privacySettings)
    }

    /// Links a policy-suppressed detection to the incident it suppressed (FR-016).
    @discardableResult
    func record(suppression: SuppressedDetection) -> Bool {
        if let current = detectorState.current, current.covers(suppression.at) {
            // Keyed both ways: the incident carries the suppression for its own
            // account of itself, and the suppression carries the incident id so
            // the policy store's audit trail can be joined back to it.
            _ = detectorState.record(suppression.linked(to: current.id))
            openIncident = detectorState.current
            return true
        }
        if let index = recentIncidents.firstIndex(where: { $0.covers(suppression.at) }) {
            let linked = suppression.linked(to: recentIncidents[index].id)
            let recorded = recentIncidents[index].record(linked)
            if recorded { persistRecentIncidents() }
            return recorded
        }
        return false
    }

    // MARK: - Announcing an incident (FR-014, FR-015, FR-016, FR-019)

    /// Decides whether an incident interrupts the user, writes down a decision not
    /// to, and hands an approved one to delivery.
    ///
    /// A method rather than a block inside `run()` for exactly the reason TASK-76
    /// exists: the gate's `.suppress` was computed in the sampling loop and dropped
    /// on the floor, and neither side's tests could see that. The gate was correct
    /// and `PolicyStore.recordSuppression` was correct; nothing joined them. This is
    /// the join, and it is drivable without running the sampler.
    ///
    /// Returns the decision so a caller — and a test — can assert on what was
    /// decided rather than on whether a notification appeared, which is a separate
    /// fact macOS owns.
    @discardableResult
    func announce(
        incident: Incident,
        leadingContributor: String?,
        context: InterruptionContext,
        at date: Date = Date()
    ) -> NotificationDecision {
        // The gate decides; delivery only carries out an approved decision.
        let decision = notificationGate.decide(
            incident: incident,
            leadingContributor: leadingContributor,
            mute: mute,
            context: context,
            at: date,
            state: &notificationState)

        // Only a per-application rule is written to the audit trail. A mute or an
        // audio deferral withheld the alert too, but neither is a rule about an
        // application, and listing them under "what your rules hid" would be the
        // misattribution FR-016's trail exists to prevent.
        if case .applicationPolicy(let application) = decision.suppressionCause {
            recordPolicySuppression(application: application, incident: incident, at: date)
        }

        Task { [notifications] in
            await notifications.deliver(
                decision: decision, incident: incident,
                leadingContributor: leadingContributor)
        }
        return decision
    }

    /// FR-016's audit trail: a rule that withholds an alert writes down that it did.
    ///
    /// Recorded in two places on purpose. `PolicyStore` holds the standalone trail
    /// the Apps tab lists — "what your rules hid" — and the incident holds the same
    /// event so its own row can say *not alerted, because you marked this expected*
    /// without the reader having to correlate two lists by hand.
    ///
    /// The classification comes from the rule that actually matched, never from a
    /// default: writing `.expected` for a rule we could not find would be inventing
    /// the user's decision. If no rule is found nothing is recorded, and the gate's
    /// own reason string still explains the suppression.
    private func recordPolicySuppression(
        application: String, incident: Incident, at date: Date
    ) {
        guard let rule = policies.policies.first(where: { $0.displayName == application })
        else { return }
        let detection = SuppressedDetection(
            application: application,
            classification: rule.classification,
            at: date,
            severity: incident.severity,
            incidentID: incident.id)
        policies.recordSuppression(detection)
        record(suppression: detection)
    }

    private(set) var lastUpdate: Date?
    private(set) var isRunning = false
    let machine = MachineContext.current()

    var severity: Severity {
        guard let attribution else { return .normal }
        return .forBusyShareOfMachine(Presentation.busyShareOfMachine(
            percentOfOneCore: attribution.totalBusyPercentOfOneCore,
            logicalCores: machine.logicalCores))
    }

    /// One row of the inventory: a family with its aggregated usage.
    struct FamilyRow: Identifiable {
        let family: ProcessFamily
        let percentOfOneCore: Double
        let residentBytes: UInt64
        var id: String { family.id }
        /// Exposed as a stored-looking value so the table can sort on it with a
        /// key path; `members.count` is not reachable as one.
        var processCount: Int { family.members.count }
    }

    /// Families with measurable usage, largest first, for the inventory view.
    var rankedFamilies: [FamilyRow] {
        Presentation.rankedFamilies(families, contributions: contributionIndex)
    }

    /// The inventory as a tree: families with their processes beneath them, plus
    /// the processes we are not permitted to measure collected into one group.
    var inventory: [InventoryRow] {
        annotatedWithTrailingUsage(Presentation.inventory(
            families, contributions: contributionIndex,
            unattributedPercentOfOneCore: attribution?.unattributedPercentOfOneCore ?? 0))
    }

    /// Attaches each row's trailing minute (TASK-95).
    ///
    /// Done here rather than inside `Presentation.inventory` because that function
    /// is pure over one sample and this is the only place that holds the history.
    /// Rows the history has nothing for keep a nil `trailing`, which every surface
    /// renders as "—" rather than as zero (FR-002).
    ///
    /// "System processes" is not a family, so its mean comes from the retained
    /// unattributed series instead — the same column has to mean the same thing on
    /// every row it appears on.
    private func annotatedWithTrailingUsage(_ rows: [InventoryRow]) -> [InventoryRow] {
        rows.map { row in
            var row = row
            switch row.kind {
            case .application:
                row.trailing = familyHistory.trailing(for: row.id)
            case .systemProcesses:
                row.trailing = TrailingPresentation.trailing(
                    of: SparklinePresentation.unattributedSeries(history.samples))
            case .member:
                // Keyed on the family: a member has no series of its own, because
                // a family outlives its processes and pids are recycled.
                break
            }
            return row
        }
    }

    private var contributionIndex: [ProcessIdentity: Double] = [:]

    /// A recognisable name for a contributor (FR-003, FR-013).
    ///
    /// Served from the identity resolver's cache, so this costs a dictionary
    /// lookup rather than filesystem work. Views call it; nothing computes a name
    /// of its own, or the popover, the table and the notification would drift
    /// apart — which is exactly how the popover came to show "Spotify Helper (".
    func displayName(for usage: ProcessCPUUsage) -> String { usage.label }

    /// The application's own icon, or nil. Nil means "no icon", never a generic
    /// placeholder standing in for one (FR-002).
    func icon(for usage: ProcessCPUUsage) -> NSImage? {
        icons.icon(forExecutablePath: resolver.identity(for: usage.identity).executablePath)
    }

    func icon(for family: ProcessFamily) -> NSImage? {
        icons.icon(forExecutablePath: family.members.first?.resolved.executablePath)
    }

    func icon(forExecutablePath path: String?) -> NSImage? {
        icons.icon(forExecutablePath: path)
    }

    func accessibilityName(for usage: ProcessCPUUsage) -> String {
        usage.displayName ?? ProcessNaming.accessibilityLabel(command: usage.command)
    }

    private let sampler = ProcessSampler()
    private let resolver = ProcessIdentityResolver()
    private let history: MetricsHistory
    /// Per-family history (FR-005, FR-043).
    ///
    /// **Moved here from `ProcessInventoryView` on 2026-08-25 (TASK-95).** It was a
    /// `@State` inside that view, so it only recorded while Apps & Processes was on
    /// screen and its series died with the view. That made it useless to every other
    /// surface — which is why the Now table said "Not retained" against every
    /// application row while an inspector two screens away was drawing curves from
    /// the same data. Owned by the store, it records on the sampling pass and every
    /// surface reads one series.
    let familyHistory = FamilyHistory()
    /// The family the inventory has selected, if any. Held here only so
    /// `FamilyHistory` can keep tracking it when it falls out of the busiest few;
    /// nothing else reads it.
    var selectedFamilyID: String?
    private let baseCadence: Duration
    private var task: Task<Void, Never>?

    // MARK: - Retained history (FR-005)

    /// The retained series, for a view that wants to draw what we actually kept.
    ///
    /// Read access only. `MetricsHistory` is a reference type with `record` and
    /// `removeAll` on it, so handing the object itself to a view would let the UI
    /// write to the evidence; the sampling loop is the only thing that records.
    ///
    /// A view drawing these samples draws the same series FR-005 retains, rather
    /// than accumulating a second one of its own — which would diverge the moment
    /// the view appeared later than the store, or refreshed at a different rate.
    var retainedSamples: [HistorySample] { history.samples }

    /// The wall-clock span actually retained, which is never assumed to be the
    /// retention window: the app may only have been running for a minute.
    var retainedHistorySpan: Duration { history.coveredDuration }

    /// The retained samples covering a closed or open incident, with a margin
    /// either side so the run-up and the recovery are visible.
    ///
    /// Empty when the incident predates anything we still hold — the caller is
    /// expected to say so rather than draw a shorter window as if it were the whole
    /// episode.
    func retainedSamples(around incident: Incident, margin: Duration = .seconds(120))
        -> [HistorySample] {
        let from = incident.beganAt.addingTimeInterval(-margin.totalSeconds)
        let to = (incident.closedAt ?? Date()).addingTimeInterval(margin.totalSeconds)
        return history.samples.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    /// `var`, because a threshold the user changes has to reach the running
    /// detector (TASK-69). Changed only through `applyAlertSettings()`, which
    /// routes every change through `IncidentDetector.adopt` so no call site can
    /// assign a policy and silently restart the sustained-duration clock.
    private var detector: IncidentDetector
    private var detectorState = IncidentDetector.State()
    private let cadenceController: CadenceController
    private var cadenceState = CadenceController.State()
    private let icons = ProcessIconCache()
    private let pressureMonitor = MemoryPressureMonitor()
    private var notificationGate = NotificationGate()
    private var notificationState = NotificationGate.State()
    /// Injectable only so a test can drive `announce` without a banner appearing on
    /// the user's screen. The app always uses the system centre.
    let notifications: NotificationDelivery
    private var previousPaging: PagingCounters?
    private var previousDisk: DiskCounters?
    private var previousOwn: UInt64?

    /// Volume capacity, read on the sampling loop rather than by the storage screen.
    ///
    /// Driven from here so the capacity series accumulates whether or not anyone is
    /// looking at it: a fortnight-long trend that only advances while the screen is
    /// open would never fill in. The screen shares this model, so opening it shows
    /// history already gathered instead of starting a new series.
    private let storage: StorageScreenModel
    private var lastStorageCheckAt: ContinuousClock.Instant?

    private let lifecycle = LifecycleTracker()
    /// Launches and exits observed since the app started, bounded to the tracker's
    /// own window (FR-045, FR-046-as-narrowed).
    private(set) var lifecycleEvents: [LifecycleEvent] = []
    /// When monitoring began, so "no relaunches" can be told apart from "we have
    /// not been watching long enough for that to mean anything".
    private(set) var monitoringStartedAt: Date?

    /// How often volume capacity is re-read.
    ///
    /// Not every sample: capacity reads touch the filesystem, and at a 2 s cadence
    /// that is filesystem work on the measurement path FR-030 budgets. Half a minute
    /// is well inside the 60 s the low-storage condition must be sustained for, so
    /// nothing is missed by reading it this way — a shortage is still seen within
    /// 30 s of appearing.
    static let storageCheckInterval: Duration = .seconds(30)

    /// The count bound on incident history, alongside the age bound the user sets
    /// (TASK-72).
    ///
    /// Both are real and both are stated in the interface. A period alone bounds
    /// nothing on a machine that is in trouble all day, which is why FR-005's
    /// "bounded" is not satisfied by "30 days" on its own; a count alone throws away
    /// last week's evidence on a busy afternoon. Whichever bites first is what is
    /// kept, and `IncidentHistory.retentionFooter` says both.
    static let retainedIncidents = IncidentHistoryStore.defaultLimit

    /// The single on-disk incident history, beside the policy store and separate
    /// from it: rules are the user's decisions and history is recorded evidence, so
    /// "delete all history" must be able to take one without the other (FR-029).
    static let persistentIncidentHistory: IncidentHistoryStore = {
        IncidentHistoryStore(url: storageURL(named: "incidents.json"))
    }()

    /// A file in the app's own storage, or in a throwaway directory under test.
    ///
    /// **The test case is the point** (TASK-91). The app-hosted bundle runs inside
    /// the real container, so `MonitorStore.shared` loaded the developer's actual
    /// incident history and a test requiring an empty store failed the moment this
    /// Mac recorded its first incident. That is a test asserting on the developer's
    /// world, and clearing the file to make it pass would leave the defect for the
    /// next person — the same shape as `MemoryPressureMonitor` seeding from live
    /// memory pressure (TASK-92).
    ///
    /// A per-launch temporary directory rather than a fixed one, so two runs cannot
    /// leak state into each other either.
    static func storageURL(named name: String) -> URL? {
        guard !AppDelegate.isHostingTests else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("MacSlowdownTests-\(ProcessInfo.processInfo.processIdentifier)",
                                        isDirectory: true)
                .appendingPathComponent(name)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MacSlowdown", isDirectory: true)
            .appendingPathComponent(name)
    }

    // MARK: - User policies (FR-016)

    /// The app's rules about applications. One store for the whole app: a policy is
    /// about an application, not about a window, so setting it in the inspector and
    /// reading it in Settings has to be the same fact. A second store would disagree
    /// with this one and the disagreement would be invisible.
    let policies: PolicyStore

    /// The single on-disk policy store, at the location the inspector already used.
    /// Isolated under test for the same reason as the incident history: a test that
    /// reads the developer's real rules is asserting on their machine, not on the
    /// code.
    static let defaultPolicies: PolicyStore = {
        PolicyStore(url: storageURL(named: "policies.json"))
    }()

    // MARK: - Grouping corrections (FR-039)

    /// The last snapshot the sampling loop read, kept only so a correction can take
    /// effect at once instead of at the next cadence tick.
    ///
    /// Nil before the first sample, in which case a correction is stored and applies
    /// from the next sweep — never silently discarded.
    private var latestSnapshot: ProcessSnapshot?

    /// The grouping step of one sample.
    ///
    /// Exists as a named method with exactly one implementation because TASK-77's
    /// defect was precisely that there were two paths to grouping in principle and
    /// only one of them — the one without corrections — was ever taken. Both the
    /// sampling loop and `correctGrouping` come through here, so a correction cannot
    /// reach the interface without also reaching `FamilyGrouper`.
    @discardableResult
    func regroup(from snapshot: ProcessSnapshot) -> [ProcessFamily] {
        latestSnapshot = snapshot
        let grouped = FamilyGrouper.group(
            snapshot: snapshot, resolver: resolver,
            overrides: policies.overrides(for: snapshot, resolver: resolver))
        families = grouped
        return grouped
    }

    /// What the user has corrected, most recent first, for a screen that lists them.
    var groupingCorrections: [GroupingCorrection] {
        policies.corrections.sorted { $0.createdAt > $1.createdAt }
    }

    /// Records a correction and regroups from the reading already in hand (FR-039).
    ///
    /// Nothing recorded is touched: the correction changes where a process is
    /// *shown*, and the per-PID samples, the attribution the current sweep measured,
    /// and every incident already written keep saying what was true when they were
    /// taken (TASK-68).
    func correctGrouping(_ correction: GroupingCorrection) {
        correctGrouping([correction])
    }

    /// Records several corrections and regroups once.
    ///
    /// Batched because moving a 23-process family is 23 corrections, and regrouping
    /// after each one would do the same work 23 times on a single button press.
    func correctGrouping(_ corrections: [GroupingCorrection]) {
        for correction in corrections { policies.addCorrection(correction) }
        if let latestSnapshot { regroup(from: latestSnapshot) }
    }

    /// Reverses a correction, restoring the heuristic grouping (FR-039).
    func removeGroupingCorrection(id: String) {
        removeGroupingCorrections(ids: [id])
    }

    func removeGroupingCorrections(ids: [String]) {
        for id in ids { policies.removeCorrection(id: id) }
        if let latestSnapshot { regroup(from: latestSnapshot) }
    }

    /// The corrections that apply to any of these processes, so an inspector can
    /// show the user what they changed about the family in front of them.
    func groupingCorrections(
        affecting members: [(command: String, executablePath: String?)]
    ) -> [GroupingCorrection] {
        groupingCorrections.filter { correction in
            members.contains { correction.matches(command: $0.command,
                                                  executablePath: $0.executablePath) }
        }
    }

    /// The user's alert preferences, or nil for a store that is not meant to read
    /// them — which is every test that drives the detector directly, and is why
    /// this is injected rather than reached for through `AlertSettings.shared`.
    private let alertSettings: AlertSettings?

    /// Incident history that survives a restart (TASK-72).
    ///
    /// Defaults to memory-only so a test gets a hermetic store; the shipping app
    /// passes `persistentIncidentHistory`. Every write goes through this object,
    /// which applies retention before anything reaches disk — there is no path that
    /// stores an incident without pruning first.
    private let incidents: IncidentHistoryStore

    /// Where "delete all history" looks for anything else we have written.
    /// Injectable only so a test can delete from a scratch folder rather than from
    /// the running user's container.
    private let evidenceDirectory: URL?

    init(cadence: Duration = MetricsHistory.defaultCadence,
         history: MetricsHistory = MetricsHistory(),
         policy: IncidentPolicy = .default,
         policies: PolicyStore = MonitorStore.defaultPolicies,
         storage: StorageScreenModel = .shared,
         alertSettings: AlertSettings? = nil,
         incidentHistory: IncidentHistoryStore = IncidentHistoryStore(url: nil),
         evidenceDirectory: URL? = StoredData.directory,
         notifications: NotificationDelivery = NotificationDelivery()) {
        self.notifications = notifications
        self.evidenceDirectory = evidenceDirectory
        self.baseCadence = cadence
        self.history = history
        self.detector = IncidentDetector(policy: policy)
        self.cadenceController = CadenceController(normalInterval: cadence)
        self.policies = policies
        self.storage = storage
        self.alertSettings = alertSettings
        self.incidents = incidentHistory
        // Read at construction rather than at `start()`: a window can open before
        // monitoring begins, and showing an empty history for those seconds would
        // look exactly like history that had not survived the restart.
        //
        // Retention is applied by `load` itself, so a machine that was off for two
        // months never displays expired incidents even briefly.
        recentIncidents = incidentHistory.load(
            settings: alertSettings?.privacySettings ?? .default)
    }

    /// The retention and persistence choices in force, or the framework's defaults
    /// for a store with no settings attached (which is every test that drives the
    /// detector directly).
    private var privacySettings: PrivacySettings {
        alertSettings?.privacySettings ?? .default
    }

    // MARK: - "Record file paths" (FR-029, TASK-79)

    /// An attribution sample as it will be **recorded**, honouring the user's
    /// choice about executable locations.
    ///
    /// The distinction this rests on is between reading a path and keeping one.
    /// MacSlowdown cannot stop reading them: the outermost `.app` in the executable
    /// path is what groups an application's processes and what finds its icon, so a
    /// setting that stopped path *resolution* would stop the product working, and a
    /// setting that claimed to and did not would be worse. What is a genuine choice
    /// is whether a location is written into the incident history that persists on
    /// disk for up to ninety days — and the shipped default says no, which until
    /// now the app did not honour.
    ///
    /// `applicationID` is rewritten too, and has to be: it *is* the bundle path
    /// wherever one exists, so leaving it would keep the location on disk under a
    /// different field name. The name-keyed form is the same fallback the framework
    /// already uses for the ~85% of processes that live in no bundle, so recurrence
    /// across incidents still works — it just cannot tell two applications with the
    /// same display name apart, which is the cost of the choice.
    ///
    /// `bundleID` is kept. A signing identifier is not a location on this Mac; it
    /// says which application, not where the user put it.
    nonisolated static func withoutFilePaths(_ sample: AttributionSample)
        -> AttributionSample {
        AttributionSample(
            applications: sample.applications.map {
                IncidentContributor(
                    applicationID: "name:\($0.displayName)",
                    displayName: $0.displayName,
                    bundleID: $0.bundleID,
                    bundlePath: nil,
                    peakPercentOfOneCore: $0.peakPercentOfOneCore,
                    hasUncertainMembers: $0.hasUncertainMembers)
            },
            totalBusyPercentOfOneCore: sample.totalBusyPercentOfOneCore,
            attributedPercentOfOneCore: sample.attributedPercentOfOneCore,
            unattributedPercentOfOneCore: sample.unattributedPercentOfOneCore,
            logicalCoreCount: sample.logicalCoreCount)
    }

    /// Applies the setting to one sample on its way to the detector.
    ///
    /// Applied here rather than at the point of writing to disk because an incident
    /// holds its attribution in memory too, and a screen showing a path the user
    /// asked not to record would be the same broken promise a moment earlier.
    /// Changing the setting mid-incident leaves whatever was already merged as it
    /// was; only later samples are affected.
    func recordable(_ sample: AttributionSample) -> AttributionSample {
        privacySettings.recordFilePaths ? sample : Self.withoutFilePaths(sample)
    }

    // MARK: - Applying the user's alert settings (TASK-69, FR-006, FR-014)

    /// Pushes the saved alert settings into the running detector and notification
    /// gate, and records that they are in force.
    ///
    /// Polled from the sampling loop rather than pushed from the Settings window.
    /// A change therefore takes effect within one cadence — a few seconds — which
    /// is the honest cost of not adding an observation path whose only job would be
    /// to shave those seconds off. `markAppliedToMonitoring()` is what retires the
    /// interface's "saved, but not yet in effect" notice; nothing else calls it, so
    /// the notice is a live statement about this method rather than a constant.
    ///
    /// Returns whether the CPU breach start was re-dated from retained readings, so
    /// a caller — and a test — can tell that case from an ordinary application.
    @discardableResult
    func applyAlertSettings() -> Bool {
        guard let alertSettings else { return false }
        let redated = detector.adopt(
            alertSettings.incidentPolicy,
            state: &detectorState,
            retainedCPU: retainedCPUReadings)
        notificationGate.settings = alertSettings.notificationSettings
        alertSettings.markAppliedToMonitoring()
        return redated
    }

    /// The thresholds the running detector is actually judging against.
    ///
    /// Exposed because "the setting is stored" and "the monitor is using it" were
    /// the same claim in this app once, and were not the same fact. Anything that
    /// wants to state what is in force reads it from the detector rather than
    /// re-deriving it from the saved preference.
    var incidentPolicyInForce: IncidentPolicy { detector.policy }

    /// The rules the running notification gate is actually applying, for the same
    /// reason.
    var notificationSettingsInForce: NotificationSettings { notificationGate.settings }

    /// The retained CPU series in the units the detector judges — fraction of total
    /// machine capacity — so a changed threshold is re-decided against readings that
    /// actually happened (FR-005, TASK-69).
    private var retainedCPUReadings: [IncidentDetector.RetainedCPUReading] {
        let capacity = Double(machine.logicalCores) * 100
        guard capacity > 0 else { return [] }
        return history.samples.map {
            IncidentDetector.RetainedCPUReading(
                at: $0.timestamp, busyFraction: $0.totalBusyPercentOfOneCore / capacity)
        }
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        monitoringStartedAt = Date()
        // Before the first sample, so the settings are in force from the first
        // observation rather than from the second.
        applyAlertSettings()
        // A dispatch source catches pressure transitions between samples, which
        // the cadence alone could not guarantee within FR-007's 2 seconds.
        // ...and the transition is adopted here rather than waited for, so a
        // pressure change reaches the interface within FR-007's two seconds even
        // when the loop is minutes behind (TASK-65.14).
        pressureMonitor.start { [weak self] transition in
            Task { @MainActor in self?.memoryPressure = transition.level }
        }
        memoryPressureIsLive = true
        task = Task { [weak self] in await self?.run() }
    }

    /// FR-015: muting suppresses interruption only. Monitoring continues, which is
    /// why this touches `mute` and nothing else.
    func mute(forMinutes minutes: Int) {
        mute = MuteState(until: Date().addingTimeInterval(Double(minutes) * 60))
    }

    func clearMute() { mute = .notMuted }

    func stop() {
        task?.cancel()
        task = nil
        pressureMonitor.stop()
        memoryPressureIsLive = false
        isRunning = false
    }

    private func run() async {
        var previous = sampler.snapshot()
        var previousHost = HostCPU.sample()
        let clock = ContinuousClock()
        var lastSampleAt = clock.now

        while !Task.isCancelled {
            try? await Task.sleep(for: self.cadence?.interval ?? baseCadence)
            if Task.isCancelled { return }

            let snapshot = sampler.snapshot()
            let host = HostCPU.sample()
            let now = clock.now

            // If the interval ran materially long the machine was too busy to
            // sample on time; surface that rather than presenting a late reading
            // as current.
            let elapsed = now - lastSampleAt
            let expected = self.cadence?.interval ?? baseCadence
            let overdue = elapsed.totalSeconds > expected.totalSeconds * 2
            lastSampleAt = now

            guard let earlierHost = previousHost, let host else {
                previous = snapshot
                previousHost = host
                continue
            }

            let result = CPUAttributionCalculator.attribution(
                from: previous, to: snapshot, hostEarlier: earlierHost, hostLater: host,
                // Served from the resolver's (pid, start time) cache, so this adds
                // a dictionary lookup per contributor, not filesystem work.
                naming: { [resolver] in resolver.identity(for: $0).friendlyName })
            let grouped = regroup(from: snapshot)
            // One wall-clock instant for this pass. `now` is a monotonic
            // `ContinuousClock.Instant` used for scheduling; retained history is
            // read back against dates a user sees, so it needs this one.
            let sampledAt = Date()

            attribution = result
            contributionIndex = Dictionary(
                result.contributors.map { ($0.identity, $0.percentOfOneCore) },
                uniquingKeysWith: { first, _ in first })
            // On the sampling pass, so history accrues whether or not a window is
            // open. The aggregates come from `inventory`, which is built from this
            // same grouping pass, so this is bookkeeping rather than a measurement.
            familyHistory.record(
                rows: inventory, families: grouped,
                selected: selectedFamilyID, at: sampledAt)
            // We are in our own snapshot, so measuring ourselves costs nothing extra.
            let ownIdentity = snapshot.records.values.first { $0.identity.pid == getpid() }
            if let metrics = ownIdentity?.measurements {
                ownResidentBytes = metrics.residentBytes
                if let previousOwn, metrics.cpuTicks >= previousOwn {
                    let deltaNanos = MachTime.nanos(fromTicks: metrics.cpuTicks - previousOwn)
                    ownCPUPercentOfOneCore = deltaNanos / (elapsed.totalSeconds * 1e9) * 100
                }
                previousOwn = metrics.cpuTicks
            }

            enumeration = snapshot.enumeration
            freshness = overdue ? .stale(age: elapsed) : .current
            lastUpdate = Date()

            // MARK: Incident detection (FR-011)

            memoryPressure = pressureMonitor.level
            thermalState = .current
            power = PowerSignals.current()

            // Rates only ever from deltas over the measured interval.
            let seconds = elapsed.totalSeconds
            // Swap usage is a level, not a rate: it is whatever the current reading
            // says, and it does not need two samples the way paging does. Assigned
            // unconditionally so a reading that stops being available reverts to
            // nil rather than leaving the last good figure on screen as if it were
            // current (FR-002, FR-008).
            swapUsage = SwapSignals.swapUsage()
            if let counters = SwapSignals.pagingCounters() {
                if let previous = previousPaging,
                   let rates = SwapSignals.rates(from: previous, to: counters, seconds: seconds) {
                    pagingRates = rates
                }
                previousPaging = counters
            }
            if let counters = DiskSignals.counters() {
                if let previous = previousDisk,
                   let rates = DiskSignals.rates(from: previous, to: counters, seconds: seconds) {
                    diskRates = rates
                }
                previousDisk = counters
            }
            refreshStorageIfDue(now: now)
            // Before the observation is built, not after it. This used to run at the
            // end of the loop, which was harmless while lifecycle evidence only fed
            // screens; now that a repeated-quit pattern can open an incident of its
            // own (TASK-71, FR-046), recording exits after the detector has already
            // judged the sample would delay every lifecycle incident by one cadence
            // and would date it from the wrong sweep.
            recordLifecycle(from: previous, to: snapshot)
            // Read the user's thresholds before judging this observation, so a
            // setting changed a moment ago is what this sample is judged against
            // (TASK-69). Placed after `history.record` of the previous pass and
            // before the observation, so a re-dated breach start is decided over
            // readings that are already retained.
            applyAlertSettings()
            // `var` because the attribution is folded in below: an incident records
            // what it was judged on (TASK-68), and that has to travel with the
            // observation the detector sees.
            var observation = currentObservation(
                at: Date(),
                cpuBusyFraction: result.totalBusyPercentOfOneCore
                    / (Double(machine.logicalCores) * 100))

            let breaching = IncidentCondition.allCases.contains {
                observation.breaches($0, policy: detector.policy)
            }
            // Rolling attribution up to applications costs more than the rest of
            // the observation and there is nothing to record it on unless something
            // is wrong, so it is built only when a condition is breaching or an
            // incident is already open. A breach always precedes an incident by the
            // sustained duration, so the snapshot is always there before the
            // detector needs it.
            if breaching || detectorState.current != nil {
                observation.attribution = recordable(
                    AttributionSample.from(attribution: result, families: grouped))
            }

            let event = detector.observe(observation, state: &detectorState)
            // Attribution is refreshed on every sample while an incident is open,
            // and refreshing it deliberately emits no event — so the open incident
            // is read back from the detector rather than only from events, or the
            // screen would show the attribution as it stood when the incident last
            // changed severity.
            openIncident = detectorState.current
            switch event {
            case .opened(let incident), .updated(let incident):
                announce(
                    incident: incident,
                    leadingContributor: result.contributors.first?.label,
                    // `focusActive` is deliberately left at its default. No public
                    // API reports the current Focus mode to a sandboxed app, and
                    // guessing would be a fabricated measurement. Focus is still
                    // respected — macOS enforces it at delivery, which is why this
                    // is a gap in our reasoning rather than in the behaviour. The
                    // gate's own check stands ready for a signal we can measure.
                    context: InterruptionContext(
                        audioActive: AudioSignals.isAnyProcessPlaying(),
                        audioApplication: AudioSignals.firstActiveProcessName()))
            case .closed(let incident):
                openIncident = nil
                // The store applies both bounds and writes; what it returns is what
                // is actually kept, so the screen and the disk cannot disagree
                // (FR-029).
                recentIncidents = incidents.record(incident, settings: privacySettings)
            case nil:
                break
            }

            // Retention, enforced on a machine that is simply left running: nothing
            // has to close and no screen has to be opened for an incident to age
            // out. Costs a date comparison per retained incident, and writes only
            // when something actually expired.
            if !self.incidents.enforceRetention(settings: privacySettings).isEmpty {
                recentIncidents = self.incidents.incidents
            }

            // MARK: Adaptive cadence (FR-031)

            self.cadence = cadenceController.cadence(
                at: Date(), incidentOpen: openIncident != nil,
                conditionBreaching: breaching, state: &cadenceState)

            history.record(result)
            resolver.prune(keeping: Set(snapshot.records.keys))
            // Persisting history is best-effort: it is evidence, not configuration,
            // and a write failure must never interrupt monitoring.
            _ = try? history.flushIfNeeded()

            previous = snapshot
            previousHost = host
        }
    }

    /// Everything the detector is asked to judge this sample.
    ///
    /// A method rather than four lines inside `run()` because this is the seam
    /// TASK-71 is about. The framework could open a repeated-quit incident and the
    /// app never offered it one, and nothing failed when that was true — a gap in
    /// what is *handed over* is invisible to tests of either side. It is testable
    /// here without running the sampler.
    func currentObservation(at: Date, cpuBusyFraction: Double) -> SystemObservation {
        SystemObservation(
            at: at,
            cpuBusyFraction: cpuBusyFraction,
            memoryPressure: memoryPressure,
            thermalState: thermalState,
            lowStorage: isLowStorage,
            // FR-046 as narrowed: an application failing while the machine is fine
            // is an episode no resource threshold can ever open, so the lifecycle
            // findings are part of what the detector judges rather than a
            // decoration on a screen.
            lifecycleFindings: relaunchPatterns)
    }

    // MARK: - Storage (FR-041, FR-042)

    /// Re-reads volume capacity if enough time has passed, records it, and updates
    /// the low-storage condition the detector is given.
    func refreshStorageIfDue(now: ContinuousClock.Instant) {
        if let last = lastStorageCheckAt,
           now - last < Self.storageCheckInterval { return }
        lastStorageCheckAt = now

        // `refresh` reads the volumes and appends to the capacity history, which
        // coalesces to its own quarter-hour interval. Driving it from here rather
        // than from the storage screen is what makes the fortnight trend continuous.
        storage.refresh()
        lastStorageCheck = storage.lastChecked
        isLowStorage = Self.isLowStorage(
            startupVolume: storage.startupVolume?.capacity, detector: storage.detector)
    }

    /// Whether a startup-volume reading breaches the low-storage line.
    ///
    /// No reading means no claim either way — false, because absence of a
    /// measurement is not evidence of a shortage (FR-002). Leaving a stale `true`
    /// standing would keep an incident open on evidence we no longer hold.
    nonisolated static func isLowStorage(
        startupVolume: VolumeCapacity?, detector: LowStorageDetector
    ) -> Bool {
        guard let startupVolume else { return false }
        return detector.isBelowThreshold(startupVolume)
    }

    // MARK: - Lifecycle (FR-045, FR-046 as narrowed)

    /// Records launches and exits between two consecutive snapshots.
    ///
    /// This is the real `LifecycleTracker`, keyed on `(pid, start time)`, so a
    /// recycled PID reads as one exit and one launch rather than as continuity.
    /// Nothing here implies a hang: TASK-27 established that macOS reports a stalled
    /// application exactly as it reports a healthy one.
    /// Whether a process ran from inside a `.app`, answered from cache only.
    ///
    /// This is the seam TASK-84 needed and `ProcessRecord` could not provide: the
    /// tracker sees commands and identities, and "is this an application" lives in
    /// `ResolvedIdentity.appBundlePath`. It is a cache **read**, never a resolution.
    /// The order in `run()` is what makes that sound — `regroup(from: snapshot)`
    /// resolves every process in this sweep before `recordLifecycle` is called, and
    /// `resolver.prune` runs after it, so both the process that just launched and
    /// the one that just disappeared are still in the cache. Resolving here instead
    /// would cost ~1 ms of syscalls per exiting process on the sampling path and
    /// would ask a dead PID a question it cannot answer.
    ///
    /// A cache miss reads as `false`, i.e. not known to be an application, which
    /// withholds an incident rather than opening one on a guess.
    ///
    /// The predicate is `isApplicationMainExecutable`, not `!isStandalone`. The
    /// latter asks which family a process is grouped into, and answers yes for every
    /// binary Xcode ships inside its own bundle — which is how a build opened a
    /// repeated-quit incident for `git` (TASK-86).
    func isApplication(_ identity: ProcessIdentity) -> Bool {
        resolver.cachedIdentity(for: identity)?.isApplicationMainExecutable ?? false
    }

    func recordLifecycle(from earlier: ProcessSnapshot, to later: ProcessSnapshot) {
        let events = lifecycle.events(
            from: earlier, to: later, isApplication: isApplication)
        guard !events.isEmpty || !lifecycleEvents.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-lifecycle.window.totalSeconds)
        lifecycleEvents = (lifecycleEvents + events).filter { $0.at >= cutoff }
    }

    /// How long monitoring has been running, which bounds every claim above.
    var observedDuration: Duration {
        guard let monitoringStartedAt else { return .zero }
        return .seconds(Date().timeIntervalSince(monitoringStartedAt))
    }

    /// Whether we have watched long enough for a count of zero to mean anything.
    /// Before that, zero means "we have not been looking" (FR-002).
    func hasObservedLongEnough(minimum: Duration = .seconds(120)) -> Bool {
        observedDuration.totalSeconds >= minimum.totalSeconds
    }

    /// Relaunches observed for any of these commands within the tracker's window.
    ///
    /// A relaunch is an exit *matched by* a launch of the same command, counted as
    /// `min(exits, launches)`. Exits alone would overstate it: an application the
    /// user quit and did not reopen exited once and relaunched never, and reporting
    /// that as a relaunch would be a claim the events do not support.
    ///
    /// Commands rather than identities, because a relaunched process has a new PID
    /// by construction. `p_comm` is truncated to 16 bytes, so two applications whose
    /// commands truncate to the same fragment are counted together — the
    /// low-confidence case `RelaunchPattern` already names.
    func relaunchCount(forCommands commands: Set<String>) -> Int {
        var exits: [String: Int] = [:]
        var launches: [String: Int] = [:]
        for event in lifecycleEvents where commands.contains(event.command) {
            switch event {
            case .exited: exits[event.command, default: 0] += 1
            case .launched: launches[event.command, default: 0] += 1
            }
        }
        return exits.reduce(0) { $0 + min($1.value, launches[$1.key] ?? 0) }
    }

    /// Repeated exits that rise to a pattern, for the commands given (FR-046).
    func relaunchPatterns(forCommands commands: Set<String>) -> [RelaunchPattern] {
        lifecycle.relaunchPatterns(
            in: lifecycleEvents.filter { commands.contains($0.command) })
    }

    /// Every relaunch pattern currently observed, for surfaces that list findings
    /// rather than ask about one application — the incidents history in particular.
    ///
    /// Bounded by the tracker's own window, so this is "what we have watched",
    /// never "what has ever happened". A caller must not present it as the latter:
    /// an app that crashed repeatedly before monitoring started is invisible here,
    /// which is a limit of observation, not evidence of health (FR-045, FR-046).
    var relaunchPatterns: [RelaunchPattern] {
        lifecycle.relaunchPatterns(in: lifecycleEvents)
    }

    // MARK: - Deleting recorded evidence (FR-029)

    /// What "Delete all history" actually removed.
    struct DeletionOutcome: Equatable {
        let incidents: Int
        let files: Int
        let bytes: UInt64

        var isEmpty: Bool { incidents == 0 && files == 0 }
    }

    /// Deletes recorded evidence, in memory and on disk, and says how much went.
    ///
    /// Both halves are required. Deleting the file alone would leave the incidents
    /// in memory to be written straight back by the next close, so the user would
    /// watch "deleted" history reappear — the delete would have been a lie the
    /// moment the next incident ended.
    ///
    /// User rules are untouched: `PolicyStore` writes `policies.json`, which
    /// `StoredData` excludes by name.
    @discardableResult
    func deleteRecordedHistory() -> DeletionOutcome {
        let removedIncidents = incidents.deleteAll()
        recentIncidents = []
        // The live metric series is recorded evidence too (FR-005). Leaving it would
        // make "delete everything" untrue of the sparklines still on screen.
        history.removeAll()
        let files = StoredData.deleteRecordedEvidence(in: evidenceDirectory)
        return DeletionOutcome(
            incidents: removedIncidents.incidents,
            files: files.files,
            // Summed, not maxed: the incident file is deleted first, so the second
            // pass no longer sees it and the two figures cover disjoint sets.
            bytes: files.bytes + removedIncidents.bytes)
    }
}
