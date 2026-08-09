import AppKit
import Charts
import Metrics
import SwiftUI

/// Which series the inspector's chart is showing.
enum InspectorMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"

    var id: String { rawValue }
}

/// The plain-text block "Copy diagnostics" puts on the clipboard (FR-017).
///
/// Pure so it can be checked against the cases that matter: a family we cannot
/// measure, one with no history yet, and one where growth is real. Every line either
/// states a measurement or states that there is none — there is no line here that
/// can be produced by inference.
enum FamilyDiagnostics {
    static func text(
        row: InventoryRow,
        provenance: GroupingProvenance,
        growth: MemoryGrowth?,
        relaunches: Int?,
        machine: MachineContext,
        at date: Date = Date()
    ) -> String {
        var lines = ["MacSlowdown — \(row.name)"]
        lines.append("")
        if let bundlePath = row.bundlePath { lines.append("Location      \(bundlePath)") }
        lines.append("Processes     \(row.processCount)")
        if let pid = row.pid { lines.append("PID           \(pid)") }
        if let startedAt = row.startedAt {
            lines.append("Started       \(startedAt.formatted(.iso8601))")
        }
        lines.append("")

        if row.isMeasurable {
            lines.append("CPU (family)  "
                + "\(CPUPresentation.percentOfOneCore(row.percentOfOneCore)) of one core "
                + "(\(CPUPresentation.machineRelative(row.percentOfOneCore)))")
            lines.append("Resident mem  "
                + ByteCountFormatStyle().format(Int64(row.residentBytes))
                + "  [resident size, not footprint]")
        } else {
            lines.append("CPU (family)  not available — macOS does not report this "
                + "process's usage to App Store apps")
            lines.append("Resident mem  not available, same reason")
        }

        if let growth {
            let minutes = max(1, Int((growth.span.totalSeconds / 60).rounded()))
            lines.append("Growth        "
                + signedBytes(growth.deltaBytes)
                + " over the last \(minutes) min observed")
        } else {
            lines.append("Growth        not enough history yet")
        }
        lines.append(relaunches.map {
            "Relaunches    \($0) observed while MacSlowdown has been running"
        } ?? "Relaunches    not observed long enough to say")
        lines.append("Disk activity not available — per-app disk I/O is not readable "
            + "by an App Store app")
        lines.append("")

        if !provenance.sentences.isEmpty {
            lines.append("Grouping")
            for sentence in provenance.sentences { lines.append("  \(sentence)") }
            lines.append("")
        }

        lines.append("Machine       \(machine.hardwareModel) · \(machine.architecture) · "
            + "\(machine.logicalCores) cores")
        lines.append("macOS         \(machine.osVersion)")
        lines.append("App           \(machine.appVersion) (\(machine.appBuild))")
        lines.append("Captured      \(date.formatted(.iso8601))")
        lines.append("")
        lines.append(CPUPresentation.convention())
        return lines.joined(separator: "\n")
    }

    static func signedBytes(_ delta: Int64) -> String {
        let magnitude = ByteCountFormatStyle().format(abs(delta))
        if delta == 0 { return "no change" }
        return (delta > 0 ? "+" : "−") + magnitude
    }
}

/// The right-hand pane for the selected application (FR-003, FR-017, FR-039).
struct FamilyInspectorView: View {
    let store: MonitorStore
    let history: FamilyHistory
    let row: InventoryRow
    let family: ProcessFamily?

    @State private var metric: InspectorMetric = .cpu
    @State private var subtitle: String?
    @State private var actionReport: String?
    @State private var isExpected = false

    private var performer: ActionPerformer { ActionPerformer() }

    /// The process the actions apply to: the application's own executable where
    /// there is one, otherwise the first member. Never a helper picked at random,
    /// because "Show in Finder" on a renderer is not what was asked for.
    private var primaryRecord: (record: ProcessRecord, resolved: ResolvedIdentity)? {
        guard let family, let first = family.members.first else { return nil }
        let main = family.bundlePath.map { $0 + "/Contents/MacOS/" }
        let chosen = family.members.first {
            guard let main, let path = $0.resolved.executablePath else { return false }
            return path.hasPrefix(main)
        } ?? first
        return (chosen.record, chosen.resolved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                chart
                Divider()
                figures
                caveats
                Divider()
                safeActions
                Divider()
                grouping
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: row.id) {
            subtitle = Self.bundleSubtitle(row.bundlePath)
            actionReport = nil
            isExpected = currentClassification() == .expected
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon = store.icon(forExecutablePath: row.executablePath) {
                Image(nsImage: icon)
                    .resizable().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.title3).bold()
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(row.processCount) "
                     + (row.processCount == 1 ? "process" : "processes"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    private var points: [FamilyHistoryPoint] { history.points(for: row.id) }

    @ViewBuilder
    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(chartTitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Series", selection: $metric) {
                    ForEach(InspectorMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if points.count < 2 {
                // FR-002: an empty series is "we have not watched long enough",
                // never a flat line at zero.
                Text("Not enough history yet. Readings for this application are kept "
                     + "from the moment it is first seen, so a chart appears after a "
                     + "few samples.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 70, alignment: .top)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value(metric.rawValue, value(point)))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 70)
                .accessibilityLabel("\(metric.rawValue) over \(chartTitle.lowercased())")
                .accessibilityValue(chartAccessibilityValue)
            }
        }
    }

    private func value(_ point: FamilyHistoryPoint) -> Double {
        switch metric {
        case .cpu: point.percentOfOneCore
        case .memory: Double(point.residentBytes) / 1_048_576
        }
    }

    private var chartTitle: String {
        let span = history.observedSpan(for: row.id)
        guard span.totalSeconds >= 60 else { return "Last few samples" }
        return "Last \(Int((span.totalSeconds / 60).rounded())) minutes"
    }

    /// VoiceOver gets the range and the latest value rather than the shape, which is
    /// what a chart with no axis labels actually communicates (FR-034).
    private var chartAccessibilityValue: String {
        let values = points.map(value)
        guard let low = values.min(), let high = values.max(), let latest = values.last else {
            return "no readings"
        }
        let unit = metric == .cpu ? "% of one core" : " MB"
        return String(format: "now %.1f%@, ranging %.1f to %.1f%@", latest, unit, low, high, unit)
    }

    // MARK: - Figures

    private var growth: MemoryGrowth? { history.growth(for: row.id) }

    /// Exits observed for this family's processes, from the store's `LifecycleTracker`.
    ///
    /// Nil until monitoring has run long enough for zero to mean something. The
    /// tracker watches the whole process table, so a family that has never been in
    /// the busiest few is covered too — which the per-family series above is not.
    private var relaunches: Int? {
        guard store.hasObservedLongEnough(), let family else { return nil }
        return store.relaunchCount(forCommands: Set(family.members.map(\.record.command)))
    }

    private var figures: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            figure("CPU (family)", row.isMeasurable
                ? CPUPresentation.percentOfOneCore(row.percentOfOneCore)
                    + " · " + CPUPresentation.machineRelative(row.percentOfOneCore)
                : "Not available")
            // Zero here means "nobody reported one", not "uses no memory" — the
            // system group has a measured CPU remainder and no memory figure at all.
            figure("Resident memory", row.isMeasurable && row.residentBytes > 0
                ? ByteCountFormatStyle().format(Int64(row.residentBytes))
                : "Not available")
            if let growth {
                let minutes = max(1, Int((growth.span.totalSeconds / 60).rounded()))
                figure("Growth, last \(minutes) min",
                       FamilyDiagnostics.signedBytes(growth.deltaBytes))
            } else {
                figure("Growth", "Not enough history yet")
            }
            if let relaunches {
                figure("Relaunches while watching", "\(relaunches)")
            } else {
                figure("Relaunches", "Not watched long enough")
            }
            // Never approximated, never inferred from aggregate disk rates:
            // proc_pid_rusage is self-only under the sandbox, so there is no
            // per-process figure to report.
            figure("Disk activity", "Not available")
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var caveats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resident memory. Activity Monitor's Memory column shows a different "
                 + "measure (footprint), so the numbers will not match exactly.")
            Text("Per-app disk activity is not available to App Store apps. macOS "
                 + "reports per-process disk I/O only to unsandboxed tools, so there is "
                 + "no figure here to show.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Safe actions

    private var safeActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAFE ACTIONS").font(.caption).bold().foregroundStyle(.secondary)

            if let primary = primaryRecord {
                ForEach(SafetyPolicy().availableActions(for: primary.record)) { action in
                    Button(title(for: action)) { run(action, primary) }
                        .frame(maxWidth: .infinity)
                }
                if let explanation = SafetyPolicy().explanation(for: primary.record) {
                    Text(explanation)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No process is available to act on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let actionReport {
                Text(actionReport)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            // FR-037. Stated as a fact about the product, not as a disabled control:
            // there is no quit or pause anywhere in this build to disable.
            Text("Quitting and pausing apps are not part of MacSlowdown. Use the "
                 + "application's own controls, or Activity Monitor, to stop what it "
                 + "is doing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(for action: ProcessAction) -> String {
        guard action == .markExpected else { return action.title }
        return isExpected
            ? "Stop treating this app's load as expected"
            : "Treat this app's load as expected…"
    }

    private func run(_ action: ProcessAction, _ primary: (record: ProcessRecord,
                                                          resolved: ResolvedIdentity)) {
        if action == .markExpected {
            setExpected(!isExpected, primary.resolved)
            return
        }
        // FR-017: report what happened, rather than assuming the request worked.
        let result = performer.perform(
            action, on: primary.record, resolved: primary.resolved,
            diagnostics: FamilyDiagnostics.text(
                row: row, provenance: row.provenance, growth: growth,
                relaunches: relaunches, machine: store.machine))
        actionReport = switch result {
        case .succeeded: "\(action.title): done."
        case .failed(let reason): "\(action.title) did not work. \(reason)"
        case .withheld(let reason): "\(action.title) is not available. \(reason)"
        }
    }

    private func currentClassification() -> PolicyClassification? {
        guard let resolved = primaryRecord?.resolved else { return nil }
        return store.policies
            .policy(for: resolved, displayName: row.name)?.classification
    }

    /// FR-016: this changes what interrupts, never what is recorded.
    private func setExpected(_ expected: Bool, _ resolved: ResolvedIdentity) {
        let policy = ApplicationPolicy(
            bundleID: resolved.bundleID, bundlePath: resolved.appBundlePath,
            displayName: row.name, classification: .expected)
        if expected {
            store.policies.setPolicy(policy)
            actionReport = "\(row.name) is now treated as expected. MacSlowdown will "
                + "keep measuring and recording it; it just will not interrupt you "
                + "about it."
        } else {
            store.policies.removePolicy(id: policy.id)
            actionReport = "\(row.name) is alerted about as usual again."
        }
        isExpected = expected
    }

    // MARK: - Grouping (FR-039)

    private var grouping: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GROUPING").font(.caption).bold().foregroundStyle(.secondary)
            if row.kind == .systemProcesses {
                Text("These \(row.processCount) processes are owned by another user "
                     + "account. They are grouped together because macOS reports the "
                     + "CPU and memory of none of them to an App Store app — the figure "
                     + "above is the measured remainder, not their sum.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if row.provenance.sentences.isEmpty {
                Text("This is a single process, so there was nothing to group.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(row.provenance.sentences, id: \.self) { sentence in
                    Text(sentence).font(.caption).foregroundStyle(.secondary)
                }
            }
            if row.kind != .systemProcesses {
                Text("Grouping keys on the outermost application bundle in each "
                     + "executable's path. Correcting it by hand is not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Bundle metadata

    /// "Version 141.0 · /Applications", from the bundle's own `Info.plist`.
    ///
    /// Readable under the sandbox — measured, 145 of 151 bundled processes yield a
    /// name this way. Read once per selection rather than per render: this is
    /// filesystem work and must never land on the sampling path.
    static func bundleSubtitle(_ bundlePath: String?) -> String? {
        guard let bundlePath else { return nil }
        let directory = (bundlePath as NSString).deletingLastPathComponent
        let version = Bundle(path: bundlePath)?
            .infoDictionary?["CFBundleShortVersionString"] as? String
        return switch (version, directory.isEmpty) {
        case (let version?, false): "Version \(version) · \(directory)"
        case (let version?, true): "Version \(version)"
        case (nil, false): directory
        case (nil, true): nil
        }
    }
}
