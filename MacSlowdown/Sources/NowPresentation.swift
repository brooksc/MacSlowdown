import Foundation
import Metrics

/// Formatting and selection rules for the Now screen (design reference 1c).
///
/// Kept out of the view for the same reason `Presentation` is kept out of the
/// store: these are the rules that can be wrong, and a rule inside a `body` is a
/// rule no test can reach.
///
/// Nothing here derives a value the framework does not measure. Where the design
/// asks for something we do not have — a sparkline over retained history, the
/// time since swap last changed, a user "expected workload" classification — the
/// answer is an omission recorded in TASK-65.3, not an approximation (FR-002,
/// FR-036, FR-038).
enum NowPresentation {
    // MARK: - The verdict

    /// The sentence Now opens with (FR-001: the condition, not a raw figure).
    ///
    /// Deliberately states only what was measured. It says the machine is busy;
    /// it never says what is making it busy, because that claim belongs to the
    /// incident summary where it can carry a confidence label (FR-013).
    struct Verdict: Equatable {
        let headline: String
        let detail: String
    }

    static func verdict(
        severity: Severity,
        attribution: CPUAttribution?,
        incidentOpen: Bool,
        topology: CoreTopology = .current
    ) -> Verdict {
        guard let attribution else {
            return Verdict(
                headline: "Taking the first reading",
                detail: "CPU is measured between two samples, so the first figure "
                    + "appears after one interval.")
        }

        let total = CPUPresentation.percentOfOneCore(attribution.totalBusyPercentOfOneCore)
        let relative = CPUPresentation.machineRelative(
            attribution.totalBusyPercentOfOneCore, topology: topology)
        let figures = "Total CPU is \(total) of one core — \(relative)."

        if incidentOpen {
            return Verdict(
                headline: "A slowdown is in progress",
                detail: figures)
        }

        switch severity {
        case .normal:
            return Verdict(
                headline: "Nothing sustained is slowing this Mac down",
                detail: figures + " Nothing has stayed bad long enough to count as an incident.")
        case .elevated:
            return Verdict(
                headline: "This Mac is working hard",
                detail: figures + " That is a busy machine, not yet a sustained problem.")
        case .severe:
            return Verdict(
                headline: "This Mac is heavily loaded",
                detail: figures + " If it stays this way it will be recorded as an incident.")
        }
    }

    // MARK: - The incident banner

    /// The chip beside the banner headline: severity and elapsed time.
    ///
    /// Duration is the incident's own, so a banner that has been on screen for a
    /// while does not silently keep the figure it opened with.
    static func incidentChip(
        _ incident: Incident,
        formatter: DateComponentsFormatter = .incidentDuration
    ) -> String {
        let duration = formatter.string(from: incident.duration.totalSeconds) ?? "under a minute"
        return "\(incident.severity.label) · \(duration)"
    }

    /// How the banner is drawn for a severity, and how that survives the two
    /// accessibility settings that forbid conveying anything by a wash of colour
    /// (FR-034).
    ///
    /// Colour is only ever *added* here. The severity word is in the chip and the
    /// glyph differs per severity, so removing every colour from this treatment
    /// loses no information — which is the test of whether colour was carrying
    /// meaning on its own. The same rule, and the same shape of type, as
    /// `MenuBarIconTreatment`.
    struct BannerTreatment: Equatable {
        /// Whether colour is applied at all. Not under Increase Contrast: the
        /// banner is then drawn in the foreground colour against a plain field.
        var usesTint: Bool
        var field: Field

        /// How the banner's own field is filled.
        enum Field: Equatable {
            /// A faint tinted wash, the design's rendering.
            case tintedFill
            /// An opaque field with a solid tinted border. Used under Reduce
            /// Transparency, which is a request not to convey state with a
            /// washed-out fill.
            case tintedBorder
            /// No colour at all: a neutral field with a foreground-colour border.
            case plain
        }

        static func resolve(
            increaseContrast: Bool, reduceTransparency: Bool
        ) -> BannerTreatment {
            if increaseContrast { return BannerTreatment(usesTint: false, field: .plain) }
            if reduceTransparency { return BannerTreatment(usesTint: true, field: .tintedBorder) }
            return BannerTreatment(usesTint: true, field: .tintedFill)
        }
    }

    /// The hue for a severity. Named rather than a `Color` so the rule is testable
    /// outside a view, exactly as `MenuBarIconTint` is.
    enum SeverityTint: Equatable { case yellow, orange, red }

    static func tint(for severity: IncidentSeverity) -> SeverityTint {
        switch severity {
        case .moderate: .yellow
        case .high: .orange
        case .severe: .red
        }
    }

    /// The banner glyph. **Shape differs per severity as well as hue**, so the
    /// three levels stay distinguishable with every colour removed (FR-034).
    static func symbolName(for severity: IncidentSeverity) -> String {
        switch severity {
        case .moderate: "exclamationmark.circle.fill"
        case .high: "exclamationmark.triangle.fill"
        case .severe: "exclamationmark.octagon.fill"
        }
    }

    // MARK: - The banner headline (design 1c, FR-013, FR-038)

    /// The banner's opening line, which names an application where one is known.
    ///
    /// Design 1c leads with "Xcode is using most of the CPU" rather than with the
    /// condition, because that is the reader's actual question. Naming an
    /// application as the subject of a slowdown is a *heuristic* claim, so the
    /// confidence recorded at the time travels with the sentence and is shown
    /// beside it — the headline is not allowed to state a cause outright (FR-013,
    /// FR-038).
    ///
    /// Where no application is known the condition-only headline is used unchanged,
    /// which is the summariser's own.
    struct BannerHeadline: Equatable {
        let text: String
        /// The evidence class and confidence for `text`, present exactly when the
        /// headline names an application. Nil when the headline states only what
        /// was measured, because a measured fact carries no confidence.
        let qualifier: String?

        var spoken: String { qualifier.map { "\(text). \($0)." } ?? text }
    }

    /// A heuristic's label, in the framework's own words rather than a second
    /// wording of them.
    static func heuristicQualifier(_ confidence: Confidence) -> String {
        "\(Evidence.heuristic.label) · \(confidence.label)"
    }

    static func bannerHeadline(
        incident: Incident, conditionHeadline: String
    ) -> BannerHeadline {
        // Repeated quits first. An episode where an application kept exiting is
        // about that application whatever else the machine was doing, and the
        // largest CPU contributor is a different subject entirely (TASK-82).
        if let pattern = leadingRelaunchPattern(incident) {
            return BannerHeadline(
                text: "\(ProcessNaming.labelled(command: pattern.command)) "
                    + "keeps quitting and reopening",
                // The *association* confidence: whether these exits are one
                // application rather than unrelated processes sharing a truncated
                // 16-byte command. Nothing here claims to know why it exited.
                qualifier: heuristicQualifier(pattern.confidence))
        }

        // The recorded attribution, never the live one: for the banner's subject to
        // be the machine's current busiest process would put a passer-by's name on
        // an incident it had nothing to do with.
        if incident.conditions.contains(.cpuSaturation),
           let recorded = incident.attribution,
           let leader = recorded.leadingApplication {
            let share = recorded.peakTotalBusyPercentOfOneCore > 0
                ? leader.peakPercentOfOneCore / recorded.peakTotalBusyPercentOfOneCore
                : 0
            // "Most of the CPU" is a claim about a majority. It is only made when
            // the recorded figures support one; otherwise the sentence says what
            // was actually established, which is that this was the largest thing we
            // were permitted to measure.
            let text = share > 0.5
                ? "\(leader.displayName) is using most of the CPU"
                : "\(leader.displayName) is the largest measurable use of the CPU"
            return BannerHeadline(text: text, qualifier: heuristicQualifier(recorded.confidence))
        }

        return BannerHeadline(text: conditionHeadline, qualifier: nil)
    }

    /// The repeated-quit pattern the banner is about.
    ///
    /// Defers to `Incident.lifecycleSubject`, and must keep doing so. This was
    /// briefly a second implementation — written here at the same time as the
    /// framework's, by a different pair of hands, with a different tie-break
    /// (most-recent rather than earliest-then-command). Equal exit counts would
    /// then have made the banner and the incidents list name **different
    /// processes for the same incident**.
    ///
    /// Which is precisely the defect TASK-82 exists to fix — the list and the
    /// detail naming different applications — reappearing inside the fix for it,
    /// in the gap between two briefs. One rule, one place.
    static func leadingRelaunchPattern(_ incident: Incident) -> RelaunchPattern? {
        incident.lifecycleSubject
    }

    /// The live process a repeated-quit banner's action should act on.
    ///
    /// The **newest** instance of the command, because the whole finding is that
    /// the previous ones are gone: an older match would be a process that has
    /// already exited. Matched on the command because a relaunched process has a
    /// new pid and therefore a new identity by construction.
    static func familyMember(
        forCommand command: String, in families: [ProcessFamily]
    ) -> FamilyMember? {
        families
            .flatMap(\.members)
            .filter { $0.record.command == command }
            .max { $0.record.identity.startTime < $1.record.identity.startTime }
    }

    // MARK: - Marking a workload expected from the banner (FR-016, design 1c)

    static func expectedPolicyActionTitle(_ name: String) -> String {
        "Heavy load is expected for \(name)"
    }

    /// What to say afterwards. `saved` must come from reading the store back — an
    /// API returning without error is not evidence that a rule exists (FR-017,
    /// FR-050).
    static func expectedPolicyOutcome(name: String, saved: Bool) -> String {
        saved
            ? "Recorded: heavy load is expected for \(name), so future alerts about it are "
                + "suppressed. Monitoring and recording continue, and this incident stays in "
                + "the history."
            : "The rule for \(name) was not saved, so nothing has changed."
    }

    // MARK: - The metric cards

    /// Memory in use, as a share of physical memory.
    ///
    /// **Calculated, not measured**: active + wired + compressed, which excludes
    /// inactive pages. Inactive memory is reclaimable cache, and counting it as
    /// "in use" is the misreport FR-007 and DR-08 exist to prevent. The figure is
    /// labelled as calculated wherever it appears, and it is never the basis of
    /// the pressure state — that comes from the kernel's own signal.
    ///
    /// Returns nil when `host_statistics64` could not be read: no reading is the
    /// honest answer, a zero would not be (FR-002).
    static func memoryInUse(
        _ statistics: MemoryStatistics?,
        physicalMemoryBytes: UInt64
    ) -> String? {
        guard let statistics, physicalMemoryBytes > 0 else { return nil }
        let inUse = statistics.active + statistics.wired + statistics.compressed
        let format = ByteCountFormatStyle(style: .memory, allowedUnits: .gb)
        return "\(format.format(Int64(inUse))) of \(format.format(Int64(physicalMemoryBytes))) "
            + "in use"
    }

    /// The detail lines under the memory-pressure card, in the design's order:
    /// what is in use, whether pages are moving, and how much swap is on disk.
    ///
    /// A function rather than three expressions inside the card's `body`, for the
    /// reason the rest of this type exists: the rules that can be wrong have to be
    /// somewhere a test can reach.
    ///
    /// Every line here is either a measurement or explicitly labelled as not one.
    /// The in-use figure carries "calculated" because it is a sum over page
    /// counters and excludes inactive pages, and an unreadable counter says so
    /// rather than reporting zero (FR-002, FR-007, DR-08).
    static func memoryCardDetails(
        statistics: MemoryStatistics?,
        physicalMemoryBytes: UInt64,
        swapActivity: String,
        swapUsage: SwapUsage?
    ) -> [String] {
        var details: [String] = []
        if let inUse = memoryInUse(statistics, physicalMemoryBytes: physicalMemoryBytes) {
            details.append("\(inUse) · calculated")
        } else {
            details.append("Memory counters unavailable")
        }
        details.append(swapActivity)
        details.append(Presentation.swapInUse(swapUsage))
        return details
    }

    /// The disk card's headline figure.
    ///
    /// Write throughput, because writes are what a slowdown is usually made of.
    /// Always a rate over the measured interval — the counters behind it are
    /// cumulative and are never shown as-is (FR-009).
    /// Nil is "not available", never "0 B/s". The disk driver either reported its
    /// counters or it did not, and only one of those is a measurement.
    static func diskWrite(_ rates: DiskRates?) -> String {
        guard let rates else { return "Not available" }
        return "\(ByteCountFormatStyle().format(Int64(rates.writeBytesPerSecond)))/s"
    }

    static func diskRead(_ rates: DiskRates?) -> String {
        guard let rates else { return "Read rate not available" }
        return "\(ByteCountFormatStyle().format(Int64(rates.readBytesPerSecond)))/s read"
    }

    // MARK: - The sidebar footer

    /// The cadence in force (FR-031 requires the user be able to inspect it).
    ///
    /// Before the first sample there is no cadence yet, and saying so beats naming
    /// an interval we are not actually running at.
    static func cadenceLine(_ cadence: SamplingCadence?) -> String {
        guard let cadence else { return "Sampling cadence not established yet" }
        let seconds = cadence.interval.totalSeconds
        let interval = seconds < 1
            ? String(format: "%.0f ms", seconds * 1000)
            : String(format: "%.0f s", seconds)
        return "Sampling every \(interval) (\(cadence.mode.label.lowercased()) cadence)"
    }

    // MARK: - Per-metric freshness (FR-002, FR-032, design 1n)

    /// How fresh one reading is, and what that follows from.
    ///
    /// Per metric rather than per screen — but only where the metrics genuinely
    /// have separate ages, which on this screen is *one* of them. CPU, the
    /// contributor list, disk throughput, swap, paging, thermal state and power
    /// are all assigned in a single pass of `MonitorStore.run()`, so they share
    /// one age exactly; giving them separate ones would be an invented
    /// distinction. Memory pressure is the exception, and the reason is the
    /// kernel's: `MemoryPressureMonitor` is a dispatch source that pushes a
    /// transition the moment it happens, so once the store adopts those pushes the
    /// pressure level does not wait on the sampling loop at all.
    ///
    /// Design 1n also shows Disk as current while CPU is stale. That is not true
    /// of this app — disk rates are computed in the same pass as the CPU
    /// attribution — so the card says what is true here rather than what the mock
    /// drew (the mocks are directional).
    enum MetricFreshness: Equatable {
        /// Nothing has been read yet. Not "unchanged", and not zero (FR-002).
        case noReadingYet
        /// From the sampling loop's last pass, which arrived when it was due.
        case current(age: Duration)
        /// The last complete reading. The pass that would have replaced it has not
        /// arrived, and nothing is estimated forward.
        case stale(age: Duration)
        /// Pushed by the kernel when it changes, so it never waits on our loop.
        case reportedOnChange

        var isStale: Bool { if case .stale = self { true } else { false } }

        /// The line under the figure on a card.
        var caption: String {
            switch self {
            case .noReadingYet: "no reading yet"
            case .current: "current"
            case .stale(let age): "as of \(NowPresentation.ageInWords(age)) ago"
            case .reportedOnChange: "current · reported when it changes"
            }
        }

        /// A glyph, because "this figure is old" must not be carried by grey text
        /// alone (FR-034).
        var symbolName: String? {
            switch self {
            case .stale: "exclamationmark.triangle"
            case .noReadingYet: "clock"
            case .current, .reportedOnChange: nil
            }
        }

        /// What VoiceOver is told. The age reaches it in words — a dimmed value is
        /// not a fact a screen reader can convey (FR-034).
        var spoken: String {
            switch self {
            case .noReadingYet: "no reading yet"
            case .current: "current"
            case .stale(let age): "not current, as of \(NowPresentation.ageInWords(age)) ago"
            case .reportedOnChange: "current, reported by the system when it changes"
            }
        }

        /// The short form a contributor row carries, or nil when the row is current
        /// and an age would be noise.
        var rowCaption: String? {
            guard case .stale(let age) = self else { return nil }
            return "\(Int(age.totalSeconds.rounded())) s ago"
        }
    }

    /// When a reading stops being able to describe now.
    ///
    /// Twice the interval we said we would sample at, with a two-second floor so a
    /// 1 s investigation cadence is not called stale merely because the next sample
    /// is a moment away.
    static func staleThreshold(cadence: Duration) -> Duration {
        max(cadence * 2, cadence + .seconds(2))
    }

    /// The age of a reading **at render time**, which is not the same fact as the
    /// interval the sampling loop measured.
    ///
    /// `MonitorStore.freshness` can only be recomputed when a sample arrives, so a
    /// loop that has stopped arriving leaves it saying `.current` forever — during
    /// exactly the stall this screen exists to describe. Deriving the age from the
    /// timestamp of the last reading and a clock that ticks on its own is what lets
    /// the screen admit it (FR-032, DR-03).
    static func metricFreshness(
        observedAt: Date?, now: Date, cadence: Duration
    ) -> MetricFreshness {
        guard let observedAt else { return .noReadingYet }
        let age = Duration.seconds(max(0, now.timeIntervalSince(observedAt)))
        return age > staleThreshold(cadence: cadence) ? .stale(age: age) : .current(age: age)
    }

    /// An age in words. Never a bare number the reader has to decode.
    static func ageInWords(_ age: Duration) -> String {
        let seconds = Int(age.totalSeconds.rounded())
        switch seconds {
        case ..<1: return "under a second"
        case 1: return "1 second"
        case ..<90: return "\(seconds) seconds"
        case ..<120: return "1 minute"
        default: return "\(seconds / 60) minutes"
        }
    }

    /// An interval, formatted the way the cadence line formats it.
    static func intervalInWords(_ interval: Duration) -> String {
        let seconds = interval.totalSeconds
        return seconds < 1
            ? String(format: "%.0f ms", seconds * 1000)
            : String(format: "%.0f s", seconds)
    }

    /// The banner shown while sampling is behind (design 1n).
    struct CatchingUpBanner: Equatable {
        let headline: String
        let body: String
        /// What we are still trying to do, so "behind" does not read as "stopped".
        let retry: String
    }

    static func catchingUpBanner(cadence: Duration) -> CatchingUpBanner {
        CatchingUpBanner(
            headline: "These readings are catching up",
            body: "The system is too busy to sample right now, so we are showing the "
                + "last reading we trust rather than guessing. Recording is still "
                + "running — nothing is being lost, it is just arriving late.",
            retry: "Retrying every \(intervalInWords(cadence))")
    }

    /// The qualifier on the contributor list's title, or nil while it is current.
    static func contributorHeaderNote(_ freshness: MetricFreshness) -> String? {
        guard case .stale(let age) = freshness else { return nil }
        return "from the reading \(ageInWords(age)) ago — not updating right now"
    }

    /// The two sentences that must appear beneath a screen full of late figures.
    ///
    /// The second one is deliberately *not* the design's. Design 1n promises "the
    /// menu bar icon runs on a higher-priority path, so it keeps updating even
    /// while this window is behind", and that is false of this app: the sampling
    /// loop, the store and both surfaces are on the main actor and read the same
    /// `@Observable` state, and `MenuBarIconModel` adds a rate limit on top, so the
    /// icon is at best exactly as current as this window and at worst two seconds
    /// behind it. Saying so is more use to the reader than a reassurance we cannot
    /// support (TASK-65.14 criterion #5).
    static let staleFootnotes = [
        "Values marked “as of …” are the last complete reading, not a current one. "
            + "Nothing here is estimated forward.",
        "The menu bar icon is drawn from this same reading, on the same update path, "
            + "so it is never more up to date than this window."
    ]

    // MARK: - The contributor table

    /// The rows Now shows: the biggest few, plus the system group whatever its
    /// size.
    ///
    /// The system row is never dropped for being small. It is the one row that
    /// makes the list account for the whole machine, and truncating it away would
    /// leave a table that silently fails to sum — the failure FR-013 and FR-038
    /// call out.
    static func contributorRows(_ inventory: [InventoryRow], limit: Int) -> [InventoryRow] {
        let ranked = Presentation.sortedInventory(inventory, by: Presentation.defaultInventorySort)
        var rows = Array(ranked.prefix(max(0, limit)))
        if let system = ranked.first(where: { $0.kind == .systemProcesses }),
           !rows.contains(where: { $0.id == system.id }) {
            rows.append(system)
        }
        return rows
    }

    /// Rows matching a search query, by the row's own name or any child's.
    static func matching(_ rows: [InventoryRow], query: String) -> [InventoryRow] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.children.contains { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    /// Qualifiers to show as chips on a row (FR-002, FR-003, FR-038).
    ///
    /// Every chip here corresponds to something measured or to a stated limit of
    /// what we may measure. There is still no "expected workload" chip, but the
    /// reason has changed: TASK-66 gave the app a `PolicyStore` (`MonitorStore
    /// .policies`), so the classification now has a real source. What remains is
    /// that `InventoryRow` carries a bundle path and a name, while
    /// `PolicyStore.policy(for:displayName:)` matches on a `ResolvedIdentity` —
    /// so rendering the chip needs a lookup this pure function cannot do. Passing
    /// the classification in is the change to make, and it belongs with whoever
    /// designs the chip rather than being invented here.
    static func chips(for row: InventoryRow) -> [String] {
        var chips: [String] = []
        if row.kind == .systemProcesses { chips.append("Can't be broken down") }
        if !row.isMeasurable { chips.append("Not measurable") }
        if let qualification = row.qualification { chips.append(qualification) }
        return chips
    }

    /// The family member holding a contributor's live record, for a safe action.
    ///
    /// Matched on `(pid, start time)`, never on pid alone: pids are reused, and
    /// acting on a recycled one would bring a different application forward.
    static func familyMember(
        for identity: ProcessIdentity, in families: [ProcessFamily]
    ) -> FamilyMember? {
        for family in families {
            if let member = family.members.first(where: { $0.record.identity == identity }) {
                return member
            }
        }
        return nil
    }

    // MARK: - Retained history

    /// Why the disk card carries no curve.
    ///
    /// Design 1c charts disk throughput. `MetricsHistory` retains CPU — the machine
    /// total, the attributed and unattributed split, and a bounded set of leading
    /// contributors — and nothing else. Accumulating a disk series inside this
    /// screen would produce a curve that exists only while the screen is open and
    /// that no incident report could corroborate, so the absence is stated instead
    /// (FR-002, FR-005).
    static let diskHistoryNote =
        "No history is retained for disk throughput, so there is no trend here — "
        + "only the rate over the last interval."

    /// The footnote explaining the table's history column.
    ///
    /// Rewritten for TASK-95, which made applications keep their own series. The
    /// old wording said applications had none and sat a few lines under a column
    /// drawing their curves. The limitation moved down a level rather than
    /// disappearing, so the note describes where it actually is now.
    static let historyColumnNote =
        "Retained history covers the machine total, the activity we are not "
        + "permitted to attribute, and each application. Individual processes "
        + "inside an application are not kept separately — they come and go, and "
        + "macOS reuses their identifiers — so those rows read “not retained”."

    // MARK: - Footnotes

    /// The caveats that must travel with the figures above them.
    static func footnotes(topology: CoreTopology = .current) -> [String] {
        var notes = [CPUPresentation.convention(topology: topology)]
        if let note = CPUPresentation.topologyNote(topology: topology) { notes.append(note) }
        // The framework's sentence, not a paraphrase of it. This footnote and the
        // Disk card's help text were two separately worded statements of one
        // limitation, either of which could have drifted from what the app does.
        // Both now read from `DiskSignals.perApplicationUnavailable` (FR-009).
        notes.append(DiskSignals.perApplicationUnavailable)
        notes.append("Resident memory. Activity Monitor's Memory column shows a different "
                     + "measure (footprint), so the numbers will not match exactly.")
        notes.append(historyColumnNote)
        return notes
    }

    /// Machine identity for the window subtitle.
    ///
    /// `hw.model` and the OS version string, as measured. There is no marketing
    /// name ("MacBook Pro") in any public API we can read, so the model identifier
    /// is what we show rather than a guess at what it is called.
    static func machineIdentity(_ machine: MachineContext) -> String {
        [machine.hardwareModel,
         "\(machine.logicalCores) cores",
         String(format: "%.0f GB", machine.physicalMemoryGB),
         machine.osVersion]
            .joined(separator: " · ")
    }
}

extension NowPresentation {
    /// How long a categorical state has held, in words (FR-058, design 4a).
    ///
    /// The tiles carry a state word — "Normal", "Fair" — and a word alone says
    /// nothing about whether it is settled or was reached a moment ago. FR-058
    /// makes the state a judgement over an interval; this is that interval, said
    /// out loud, so a reader can tell a steady machine from one that just changed.
    ///
    /// Two cases, kept apart deliberately:
    ///
    /// - The state changed while we were watching, so we saw the change and can
    ///   date it: "Held 3 min at this state".
    /// - It has been this way for the whole time we have been watching, so we did
    ///   **not** see it start and must not imply we did. The phrasing says what was
    ///   actually covered, which is FR-057's rule about a window shorter than
    ///   intended, applied to a duration rather than to a mean.
    ///
    /// Nil below a minute, because a state that changed seconds ago is described by
    /// the freshness line already, and "held 0 min" is noise.
    static func stateHold(
        since: Date?, monitoringBeganAt: Date?, now: Date = Date()
    ) -> String? {
        guard let since else { return nil }
        let held = now.timeIntervalSince(since)
        guard held >= 60 else { return nil }
        let phrase = DurationPhrase.phrase(held, .compact)

        // Equality on the stamp, not a tolerance: `start()` assigns the same
        // `Date` to both, and any real transition replaces it.
        if let monitoringBeganAt, since == monitoringBeganAt {
            return "At this state for the \(phrase) we have been watching"
        }
        return "Held \(phrase) at this state"
    }
}
