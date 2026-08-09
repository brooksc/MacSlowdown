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

    // MARK: - Footnotes

    /// The caveats that must travel with the figures above them.
    static func footnotes(topology: CoreTopology = .current) -> [String] {
        var notes = [CPUPresentation.convention(topology: topology)]
        if let note = CPUPresentation.topologyNote(topology: topology) { notes.append(note) }
        notes.append("Per-app disk activity isn't available to App Store apps, so only the "
                     + "machine-wide figure above is shown.")
        notes.append("Resident memory. Activity Monitor's Memory column shows a different "
                     + "measure (footprint), so the numbers will not match exactly.")
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
