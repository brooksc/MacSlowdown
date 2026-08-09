import Metrics
import SwiftUI

/// The evidence behind one incident (FR-013, FR-038, FR-049, FR-050, FR-054).
///
/// Design reference: 1e — "the evidence room". The order is the design's: a plain
/// verdict, the confidence legend, the timeline, what we found (ending in what the
/// evidence rules out), what happened after any action, the events including our
/// own behaviour, and the conditions around it.
///
/// Two sections deliberately state absence rather than filling space. Everything a
/// section would need has to have been measured and retained; where it was not, the
/// section says so by name. Reconstructing a plausible series or showing a current
/// reading under "at the time" would be the fabricated measurement the spec never
/// allows.
struct IncidentDetailView: View {
    let incident: Incident
    let store: MonitorStore
    /// Retained samples covering the incident window, if a caller can supply them.
    ///
    /// `IncidentsView` supplies these from `MonitorStore.retainedSamples(around:)`.
    /// Still defaulted, so a caller with no history — a preview, or an incident
    /// older than the retained window — gets a timeline that draws the recorded
    /// lifecycle and says plainly that it has no series, rather than one invented
    /// to fill the space.
    var samples: [HistorySample] = []
    /// A before/after taken around a user action, if one was recorded (FR-050).
    var verification: ActionVerification? = nil

    @State private var isExporting = false

    /// The user's own words about incidents (FR-039). Owned here rather than
    /// injected because `IncidentsView` constructs this view and is not ours to
    /// change; `UserDefaults` is the shared state, so a second instance sees the
    /// same labels rather than a private copy.
    @State private var labels = IncidentLabels()
    @State private var draftLabel = ""
    @State private var isLabelling = false
    /// What actually happened when a hand-off was used, so a button is never shown
    /// as though it worked (FR-017).
    @State private var toolResults: [String: String] = [:]

    /// The 1h presentation, when most of this incident's load is unattributable.
    ///
    /// Nil is the ordinary case and is not a failure: an incident the user's own
    /// applications explain must not be dressed in the language of a limit we did
    /// not hit.
    private var unattributed: UnattributedIncidentReport? {
        // A lifecycle-only incident is not an unattributable resource incident, and
        // narrating it as one would lead with a CPU split for an episode in which no
        // resource condition was ever breached (TASK-71). The share can look high
        // simply because the machine was idle, so this is guarded on the conditions
        // rather than on the numbers.
        guard incident.conditions.contains(where: \.isResourceCondition) else { return nil }
        return UnattributedIncidentReport.build(
            incident: incident,
            liveAttribution: store.attribution,
            protected: store.attribution?.protectedProcesses ?? [],
            lifecycle: store.lifecycleEvents,
            lifecycleObservedFrom: store.monitoringStartedAt,
            enumerationSucceeded: !store.enumeration.didFail,
            samples: samples,
            recentIncidents: store.recentIncidents,
            labels: labels.byIncident)
    }

    /// Relaunch patterns whose window overlaps this incident (design 1o, FR-046).
    ///
    /// Bounded by the lifecycle tracker's own window, so this is "what we watched"
    /// and never "what has ever happened".
    ///
    /// The incident's **own** record wins where it has one, exactly as the
    /// attribution does: lifecycle events are not persisted, so after a restart the
    /// live tracker holds nothing about an episode that ended yesterday, and reading
    /// from it would turn a recorded finding into a blank section (TASK-71).
    private var repeatedQuitPatterns: [RelaunchPattern] {
        if !incident.lifecycleFindings.isEmpty { return incident.lifecycleFindings }
        return store.relaunchPatterns.filter { pattern in
            pattern.lastAt >= incident.beganAt
                && pattern.firstAt <= (incident.closedAt ?? Date())
        }
    }

    private var repeatedQuits: [RepeatedQuitReport] {
        repeatedQuitPatterns
            .map { pattern in
                RepeatedQuitReport.build(
                    pattern: pattern,
                    displayName: displayName(forCommand: pattern.command),
                    lifecycle: store.lifecycleEvents,
                    samples: samples,
                    logicalCoreCount: incident.attribution?.logicalCoreCount
                        ?? store.attribution?.logicalCoreCount,
                    peakPressure: incident.peakMemoryPressure)
            }
    }

    /// The application name for a command, where grouping knows one.
    private func displayName(forCommand command: String) -> String? {
        for family in store.families {
            if family.members.contains(where: { $0.record.command == command }) {
                return family.displayName
            }
        }
        return nil
    }

    private var summary: IncidentSummary {
        IncidentSummarizer.summarize(incident: incident, attribution: store.attribution)
    }

    private var investigation: GuidedInvestigation {
        InvestigationBuilder.build(
            incident: incident, summary: summary, attribution: store.attribution)
    }

    private var duration: String {
        DateComponentsFormatter.incidentDuration.string(from: incident.duration.totalSeconds)
            ?? "a period"
    }

    private var timeline: IncidentTimeline {
        IncidentTimeline.build(incident: incident, samples: samples)
    }

    private var conditions: IncidentConditions {
        IncidentConditions.build(
            incident: incident,
            power: store.power,
            thermal: store.thermalState,
            startupVolume: startupVolume,
            machine: store.machine)
    }

    /// Read once, not on every layout pass: capacity reads touch the filesystem and
    /// this view redraws with the sampling loop.
    @State private var startupVolume: VolumeCapacity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                verdict
                legend
                // Design 1h: where the CPU went comes before the timeline, because
                // for an unattributable incident the split *is* the finding.
                if let report = unattributed {
                    CPUSplitSection(split: report.split)
                }
                timelineSection
                findings
                if let report = unattributed {
                    TimingInferenceSection(report: report)
                    SystemProcessRosterSection(report: report)
                    UnattributedLimitSection(share: report.unattributedShare)
                }
                ForEach(Array(repeatedQuits.enumerated()), id: \.offset) { _, report in
                    RepeatedQuitSection(report: report)
                }
                if let report = unattributed {
                    labelSection(report: report)
                    if let recurrence = report.recurrence {
                        RecurrenceSection(recurrence: recurrence)
                    }
                }
                toolsSection
                postAction
                events
                conditionsSection
                Divider()
                rawEvidence
                Divider()
                investigationSteps
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            guard incident.isOpen, startupVolume == nil else { return }
            startupVolume = StorageSignals.snapshot().startupVolume
        }
    }

    // MARK: - Verdict

    /// The opening line, which changes with the kind of evidence behind it.
    ///
    /// An unattributable incident and a repeated-quit episode are not the same
    /// event described differently — they are answers to different questions, and
    /// leading either with "your Mac's processors were close to fully busy" would
    /// point the reader at the wrong evidence entirely.
    private var headline: String {
        if let report = unattributed { return report.headline }
        if let quits = repeatedQuits.first, unattributed == nil { return quits.headline }
        return IncidentVerdict.headline(for: incident, duration: duration)
    }

    private var opening: String {
        if let report = unattributed { return report.opening }
        if let quits = repeatedQuits.first { return quits.opening }
        return IncidentVerdict.paragraph(
            incident: incident, attribution: store.attribution, duration: duration)
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.title3).bold()
                    .fixedSize(horizontal: false, vertical: true)
                SeverityChip(severity: incident.severity)
                Spacer()
                // FR-028: exporting shows what would leave before anything does.
                Button("Export…") { isExporting = true }
                    .help("Check what's in a report before you send it. Nothing is uploaded.")
            }
            Text(opening)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            // How it ended, from what was recorded — never inferred from the fact
            // that the machine got better (FR-050). The vocabulary distinguishes
            // "recovered, no action was recorded" from "recovered after a recorded
            // action", and there is deliberately no case meaning "recovered
            // *because* you acted": we can show the two lined up, never that one
            // caused the other.
            Text(incident.outcome.statement.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $isExporting) {
            ExportReportView(
                model: ExportReportModel(
                    incident: incident, summary: summary, attribution: store.attribution,
                    contributorPaths: contributorPaths, machine: store.machine),
                onClose: { isExporting = false })
        }
    }

    /// Paths for the processes named in the report, where the app has them, so the
    /// "File paths" control acts on something real rather than being inert.
    private var contributorPaths: [ProcessIdentity: String] {
        var paths: [ProcessIdentity: String] = [:]
        for family in store.families {
            for member in family.members {
                if let path = member.resolved.executablePath {
                    paths[member.record.identity] = path
                }
            }
        }
        return paths
    }

    // MARK: - Confidence legend (FR-038, stated up front)

    private var legend: some View {
        let entries = EvidenceLegend.entries(
            for: summary, incident: incident, attribution: store.attribution)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: EvidenceStyle.symbol(entry.evidence))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(entry.text)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        let line = timeline
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").font(.headline)
                Text(line.caption).font(.caption).foregroundStyle(.secondary)
            }
            IncidentTimelineBand(timeline: line)
                .frame(height: line.hasSeries ? 78 : 46)
            // Why this incident can be dated before the moment it was noticed
            // (FR-038). Nil in the ordinary case, where the start was observed
            // live and there is nothing to explain. Rendered here rather than in
            // "What we found" because it is a statement about the timeline's own
            // left edge, and a reader who has just seen a start time earlier than
            // the app could plausibly have watched needs the answer next to it.
            if let provenance = line.startProvenance {
                ConclusionRow(conclusion: provenance)
            }
            if !line.hasSeries {
                Text(IncidentTimeline.noSeriesNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(line.missingSeries) { missing in
                    Text("\(missing.name): not retained. \(missing.reason)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - What we found

    /// Measured, then calculated, then the single labelled hypothesis, then what the
    /// evidence rules out. "Ruled out" closes the section because it is the part
    /// that stops a user chasing a cause the measurements exclude.
    private var findings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What we found").font(.headline)
            ForEach(Array(summary.conclusions.enumerated()), id: \.offset) { _, conclusion in
                ConclusionRow(conclusion: conclusion)
            }
            if !summary.ruledOut.isEmpty {
                Text("Ruled out")
                    .font(.subheadline).bold()
                    .padding(.top, 4)
                Text("What the measurements exclude, not only what they suggest.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(summary.ruledOut.enumerated()), id: \.offset) { _, conclusion in
                    ConclusionRow(conclusion: conclusion)
                }
            }
        }
    }

    // MARK: - What happened after you acted (FR-050)

    private var postAction: some View {
        let report = PostActionReport(verification: verification)
        return VStack(alignment: .leading, spacing: 8) {
            Text("What happened after you acted").font(.headline)
            Text(report.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let pair = report.beforeAfter {
                HStack(spacing: 16) {
                    beforeAfterColumn(title: "Before", value: pair.before)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    beforeAfterColumn(title: "After", value: pair.after)
                    if let outcome = report.outcomeLabel {
                        Text(outcome)
                            .font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if report.verification != nil {
                Text(PostActionReport.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func beforeAfterColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }

    // MARK: - Events

    private var events: some View {
        let entries = IncidentEventLog.entries(
            incident: incident,
            cadence: incident.isOpen ? store.cadence : nil)
        let hasOwn = entries.contains { $0.origin == .ourOwnBehaviour }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Events").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(entries) { entry in
                    GridRow {
                        Text(entry.timeLabel)
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if entry.origin == .ourOwnBehaviour {
                                // Our own behaviour is marked, because it changes the
                                // resolution of everything recorded after it.
                                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(entry.timeLabel). \(entry.text)."
                        + (entry.origin == .ourOwnBehaviour ? " MacSlowdown's own behaviour." : ""))
                }
            }
            if !hasOwn {
                Text(IncidentEventLog.noOwnBehaviourNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Conditions (FR-049)

    private var conditionsSection: some View {
        let context = conditions
        return VStack(alignment: .leading, spacing: 8) {
            Text(incident.isOpen ? "Conditions now" : "Conditions at the time")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(context.rows) { row in
                    GridRow {
                        Text(row.label).foregroundStyle(.secondary)
                        Text(row.value)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
            Text(context.provenance.note)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(context.unavailable) { row in
                Text("\(row.label): \(row.value)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(context.footer)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// FR-054: raw measurements stay reachable, so a user can check the working.
    /// FR-055: the figures visibly sum.
    /// The figures to show, and where they came from.
    ///
    /// An incident's own recording wins over live state. Showing the live reading
    /// against a closed incident put whatever is busy *now* under the heading "the
    /// measurements" for a slowdown that ended an hour ago — the live reading is
    /// used only while an incident has recorded nothing of its own.
    private var evidenceFigures: (figures: [AttributedFigure], caption: String)? {
        if let recorded = incident.attribution {
            return (recorded.figures,
                    "Recorded while this was happening, at its busiest moment, on "
                    + "\(recorded.logicalCoreCount) logical cores.")
        }
        if let live = store.attribution, incident.isOpen {
            return (live.figures, live.explanation)
        }
        return nil
    }

    private var rawEvidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The measurements").font(.headline)
            if let evidence = evidenceFigures {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(Array(evidence.figures.enumerated()), id: \.offset) { _, figure in
                        GridRow {
                            Text(figure.label)
                            Text(CPUPresentation.percentOfOneCore(figure.percentOfOneCore))
                                .monospacedDigit()
                            Text(figure.evidence.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(figure.label): "
                            + "\(CPUPresentation.percentOfOneCore(figure.percentOfOneCore)) "
                            + "of one core, \(figure.evidence.rawValue)")
                    }
                }
                Text(evidence.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Peak CPU reached "
                     + "\(Int((incident.peakCPUBusyFraction * 100).rounded()))% of this Mac.")
                    .font(.callout)
            }
            Text(CPUPresentation.convention())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var investigationSteps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Working through it").font(.headline)
            // The first stage restates the findings already shown above, which
            // read as a bug when both are on screen. The remaining stages are the
            // part that adds something: what was involved, whether it was
            // expected, what can be done, and what changed.
            ForEach(investigation.steps.filter { $0.stage != .whatHappened }) { step in
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.question).font(.subheadline).bold()
                    ForEach(Array(step.findings.enumerated()), id: \.offset) { _, conclusion in
                        ConclusionRow(conclusion: conclusion)
                    }
                    ForEach(step.actions) { action in
                        // Only non-destructive actions exist; an unavailable one is
                        // never offered as though it worked (FR-017).
                        Label(action.title, systemImage: "arrow.up.forward.app")
                            .font(.callout)
                            .help(action.explanation)
                    }
                }
            }
        }
    }

    // MARK: - What you can do

    /// Hand-offs to tools that can see what we cannot.
    ///
    /// The offer follows the evidence: Time Machine's settings appear because
    /// `backupd` was on the roster, not because backups are a plausible topic.
    private var tools: [SystemTool] {
        var tools = unattributed?.tools ?? []
        for report in repeatedQuits {
            for tool in report.tools where !tools.contains(where: { $0.id == tool.id }) {
                tools.append(tool)
            }
        }
        return tools
    }

    @ViewBuilder private var toolsSection: some View {
        if !tools.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What you can do").font(.headline)
                ForEach(tools) { tool in
                    VStack(alignment: .leading, spacing: 3) {
                        Button(tool.title) { open(tool) }
                            .disabled(!tool.isPresent)
                        Text(tool.explanation)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // FR-017: the result of asking, not the assumption that
                        // asking worked.
                        if let result = toolResults[tool.id] {
                            Text(result)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func open(_ tool: SystemTool) {
        switch SystemToolOpener().open(tool) {
        case .succeeded:
            toolResults[tool.id] = "Asked macOS to open it."
        case .failed(let reason), .withheld(let reason):
            toolResults[tool.id] = reason
        }
    }

    // MARK: - What the user knows that we do not (FR-039)

    private func labelSection(report: UnattributedIncidentReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let existing = labels.label(for: incident.id) {
                Text(IncidentLabels.conclusion(for: existing).text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Change…") {
                        draftLabel = existing
                        isLabelling = true
                    }
                    // Reversible, as FR-039 requires: there is no state a user can
                    // reach here and not leave.
                    Button("Remove label") { labels.clear(for: incident.id) }
                }
            } else if !isLabelling {
                Button(IncidentLabels.prompt) {
                    draftLabel = ""
                    isLabelling = true
                }
            }

            if isLabelling {
                TextField(IncidentLabels.fieldPrompt, text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitLabel() }
                let suggestions = IncidentLabels.suggestions(from: report.roster)
                if !suggestions.isEmpty {
                    HStack {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { draftLabel = suggestion }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
                HStack {
                    Button("Save") { commitLabel() }
                    Button("Cancel") { isLabelling = false }
                }
            }

            Text(IncidentLabels.promise)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(IncidentLabels.recallPromise)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commitLabel() {
        labels.set(draftLabel, for: incident.id)
        isLabelling = false
    }
}

// MARK: - Where the CPU went (design 1h)

/// The split of busy CPU, with the remainder as a first-class bar.
///
/// The unattributed share is drawn like every other slice rather than as a
/// leftover, because it *is* a measurement — and it is usually the largest one.
/// The hatched fill and the word "unattributed" both carry that meaning, so the
/// distinction never rests on colour alone (FR-034).
struct CPUSplitSection: View {
    let split: CPUSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where the CPU went").font(.headline)
                Text("totals 100%").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(split.slices) { slice in
                row(slice)
            }
            if !split.applicationPeaks.isEmpty {
                Text("Applications we could measure")
                    .font(.subheadline).bold()
                    .padding(.top, 4)
                ForEach(split.applicationPeaks) { application in
                    HStack(alignment: .firstTextBaseline) {
                        Text(application.displayName).font(.callout)
                        Spacer()
                        Text(CPUPresentation.percentOfOneCore(application.peakPercentOfOneCore))
                            .font(.callout).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(split.coherence.note)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(CPUPresentation.convention())
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ slice: CPUSplit.Slice) -> some View {
        let share = split.share(of: slice)
        let percent = Int((share * 100).rounded())
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: EvidenceStyle.symbol(slice.evidence))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(slice.name).font(.callout)
                Spacer()
                Text("\(percent)%").font(.callout).bold().monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(slice.kind == .unattributed
                              ? AnyShapeStyle(.secondary)
                              : AnyShapeStyle(.tint))
                        .frame(width: max(2, geometry.size.width * share))
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(slice.name): \(percent)% of busy CPU, "
            + "\(CPUPresentation.percentOfOneCore(slice.percentOfOneCore)) of one core, "
            + "\(slice.evidence.rawValue)")
    }
}

// MARK: - An inference from timing (design 1h)

/// The suggestion, its supporting evidence, and its disclaimer, in one block.
///
/// They are one view rather than three so that the caveat cannot be laid out
/// away from the claim it qualifies.
struct TimingInferenceSection: View {
    let report: UnattributedIncidentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the timing suggests").font(.headline)
            if report.inferences.isEmpty {
                Text(TimingInference.noneFound)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let shape = report.shape {
                    ConclusionRow(conclusion: shape.conclusion)
                }
            } else {
                ForEach(report.inferences) { inference in
                    VStack(alignment: .leading, spacing: 6) {
                        ConclusionRow(conclusion: inference.conclusion)
                        ForEach(Array(inference.supporting.enumerated()), id: \.offset) {
                            _, support in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: EvidenceStyle.symbol(support.evidence))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(support.text)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - What was running (design 1h)

/// System processes by name and timing, and the ones notably absent.
struct SystemProcessRosterSection: View {
    let report: UnattributedIncidentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(SystemProcessRoster.heading).font(.headline)
                Text(SystemProcessRoster.evidenceNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(SystemProcessRoster.cpuLimitation)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(report.roster.running) { witness in
                row(witness, absent: false)
            }
            // Absence is evidence. A user asking "was it a software update?" is
            // answered by softwareupdated not having been there.
            ForEach(report.roster.absent) { witness in
                row(witness, absent: true)
            }
            if let limitation = report.roster.absenceLimitation {
                Text(limitation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(report.roster.provenanceNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(SystemProcessRoster.timingPrecisionNote)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ witness: SystemProcessWitness, absent: Bool) -> some View {
        let timing = witness.timing(window: report.window)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Presence and absence differ by symbol as well as by wording,
                // never by colour alone (FR-034).
                Image(systemName: absent ? "circle" : "circle.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(witness.displayName).font(.callout).bold()
                Text(witness.command)
                    .font(.caption).monospaced().foregroundStyle(.secondary)
            }
            Text(timing)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(witness.displayName), \(witness.command). \(timing). "
                            + "Its CPU is not measurable.")
    }
}

// MARK: - Why we can't name it (design 1h)

struct UnattributedLimitSection: View {
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(UnattributedExplanation.heading).font(.headline)
            Text(UnattributedExplanation.limit)
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(UnattributedExplanation.remainderIsMeasured(share: share))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(UnattributedExplanation.whatWeStillSee)
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(UnattributedExplanation.handOff)
                .font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Has this happened before? (design 1h)

struct RecurrenceSection: View {
    let recurrence: UnattributedRecurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Has this happened before?").font(.headline)
            ConclusionRow(conclusion: recurrence.count)
            if let clustering = recurrence.clustering { ConclusionRow(conclusion: clustering) }
            if let recall = recurrence.labelRecall { ConclusionRow(conclusion: recall) }
            if let hint = recurrence.hint { ConclusionRow(conclusion: hint) }
        }
    }
}

// MARK: - Repeated quits (design 1o)

/// Lifecycle evidence: sessions, exits and PID changes — not resource curves.
struct RepeatedQuitSection: View {
    let report: RepeatedQuitReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("What we saw").font(.headline)
                Text("Measured — launches, exits and PID changes")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SessionBar(report: report)
                .frame(height: 20)
            legend

            // The PID evidence, spelled out. This is the whole of what we know.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach(report.exits) { exit in
                    GridRow {
                        Text(IncidentVerdict.time(exit.noticedAt))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Text(exit.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let since = report.stillRunningSince {
                    GridRow {
                        Text(IncidentVerdict.time(since))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Text("Running since — no further exit seen while we have been watching")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(RepeatedQuitReport.timingPrecisionNote)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("What we found").font(.headline).padding(.top, 4)
            ForEach(Array(report.conclusions.enumerated()), id: \.offset) { _, conclusion in
                ConclusionRow(conclusion: conclusion)
            }
            Text("Ruled out").font(.subheadline).bold().padding(.top, 4)
            ForEach(Array(report.ruledOut.enumerated()), id: \.offset) { _, conclusion in
                ConclusionRow(conclusion: conclusion)
            }

            // FR-046's sentence, given a section of its own rather than a
            // footnote: a capability we do not have is part of the answer.
            VStack(alignment: .leading, spacing: 6) {
                Text("What we can and can't say").font(.subheadline).bold()
                Text(RepeatedQuitReport.capability)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(RepeatedQuitReport.hangLimitation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(RepeatedQuitReport.sessionLegend, id: \.label) { entry in
                Text("\(entry.label) — \(entry.meaning)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Sessions as bars along the window, with a mark where each one ended.
///
/// A bar chart rather than a line, because the quantity being shown is "this
/// process existed from here to here" — there is no series to plot and drawing one
/// would imply we measured something across it.
struct SessionBar: View {
    let report: RepeatedQuitReport

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(.quaternary).frame(height: 3).offset(y: 8)
                ForEach(report.sessions) { session in
                    let start = fraction(session.startedAt ?? report.window.start) * width
                    let end = fraction(session.endedAt ?? report.window.end) * width
                    RoundedRectangle(cornerRadius: 3)
                        // An open session is drawn taller as well as differently
                        // filled, so the distinction is not colour alone (FR-034).
                        .fill(session.isOpen ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: max(3, end - start), height: session.isOpen ? 14 : 10)
                        .offset(x: start, y: session.isOpen ? 2 : 4)
                }
                ForEach(report.exits) { exit in
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 1.5, height: 18)
                        .offset(x: fraction(exit.noticedAt) * width)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func fraction(_ date: Date) -> Double {
        let span = report.window.duration
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(report.window.start) / span))
    }

    private var accessibilityDescription: String {
        let sessions = report.sessions.count
        let exits = report.exits.map { IncidentVerdict.time($0.noticedAt) }
            .joined(separator: ", ")
        return "\(sessions) sessions of \(report.displayName) between "
            + "\(IncidentVerdict.time(report.window.start)) and "
            + "\(IncidentVerdict.time(report.window.end)). Exits noticed at \(exits)."
    }
}

/// Severity as a word and a shape, never colour alone (FR-034).
struct SeverityChip: View {
    let severity: IncidentSeverity

    var body: some View {
        Label(severity.label, systemImage: symbol)
            .font(.caption).bold()
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Severity \(severity.label)")
    }

    private var symbol: String {
        switch severity {
        case .moderate: "exclamationmark.circle"
        case .high: "exclamationmark.triangle"
        case .severe: "exclamationmark.octagon"
        }
    }
}

/// The incident window, drawn from recorded timestamps, with any retained CPU
/// series inside it.
///
/// The shading marks the window; the notches mark the lifecycle points. When there
/// is no series, this still carries real information — which is why it is drawn
/// rather than hidden.
struct IncidentTimelineBand: View {
    let timeline: IncidentTimeline

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bandHeight: CGFloat = 14
            let seriesHeight = max(0, height - bandHeight - 18)

            ZStack(alignment: .topLeading) {
                if timeline.hasSeries {
                    seriesPath(width: width, height: seriesHeight)
                        .fill(.tint.opacity(0.25))
                    seriesPath(width: width, height: seriesHeight, closed: false)
                        .stroke(.tint, lineWidth: 1.5)
                }

                // The incident window itself.
                let start = timeline.fraction(of: timeline.windowStart) * width
                let end = timeline.fraction(of: timeline.windowEnd) * width
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.25))
                    .frame(width: max(2, end - start), height: bandHeight)
                    .offset(x: start, y: seriesHeight)

                ForEach(timeline.markers) { marker in
                    let x = timeline.fraction(of: marker.at) * width
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 1.5, height: bandHeight + 4)
                        .offset(x: x, y: seriesHeight - 2)
                    Text(marker.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: min(max(0, x - 18), max(0, width - 70)),
                                y: seriesHeight + bandHeight + 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timeline.accessibilityDescription)
    }

    /// Total busy CPU across the window — the one series `MetricsHistory` retains.
    private func seriesPath(width: CGFloat, height: CGFloat, closed: Bool = true) -> Path {
        Path { path in
            let peak = max(timeline.peakTotalPercentOfOneCore, 1)
            var started = false
            for sample in timeline.samples {
                let x = timeline.fraction(of: sample.timestamp) * width
                let y = height - CGFloat(sample.totalBusyPercentOfOneCore / peak) * height
                if started {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                    started = true
                }
            }
            guard closed, started,
                  let first = timeline.samples.first, let last = timeline.samples.last
            else { return }
            path.addLine(to: CGPoint(x: timeline.fraction(of: last.timestamp) * width, y: height))
            path.addLine(to: CGPoint(x: timeline.fraction(of: first.timestamp) * width, y: height))
            path.closeSubpath()
        }
    }
}

/// Symbols for the evidence classes, so the legend is not colour alone (FR-034).
enum EvidenceStyle {
    static func symbol(_ evidence: Evidence) -> String {
        switch evidence {
        case .measured: "circle.fill"
        case .calculated: "square.fill"
        case .heuristic: "triangle.fill"
        case .userProvided: "person.fill"
        }
    }
}

/// One statement, always showing how it is known (FR-038).
struct ConclusionRow: View {
    let conclusion: Conclusion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Label(label, systemImage: EvidenceStyle.symbol(conclusion.evidence))
                    .font(.caption).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            Text(conclusion.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). \(conclusion.text)")
    }

    /// A hypothesis always carries its confidence into the label, so the caveat
    /// cannot be separated from the claim.
    private var label: String {
        if let confidence = conclusion.confidence {
            return "\(conclusion.evidence.label) · \(confidence.label)"
        }
        return conclusion.evidence.label
    }
}
