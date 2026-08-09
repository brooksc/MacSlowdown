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
    /// Defaulted because `MonitorStore` keeps its `MetricsHistory` private, so today
    /// no caller can. The timeline draws the recorded lifecycle either way and says
    /// plainly when it has no series; wiring history through is a one-line change
    /// for whoever owns the store.
    var samples: [HistorySample] = []
    /// A before/after taken around a user action, if one was recorded (FR-050).
    var verification: ActionVerification? = nil

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
                timelineSection
                findings
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

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(IncidentVerdict.headline(for: incident, duration: duration))
                    .font(.title3).bold()
                    .fixedSize(horizontal: false, vertical: true)
                SeverityChip(severity: incident.severity)
            }
            Text(IncidentVerdict.paragraph(
                incident: incident, attribution: store.attribution, duration: duration))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
    private var rawEvidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The measurements").font(.headline)
            if let attribution = store.attribution {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(Array(attribution.figures.enumerated()), id: \.offset) { _, figure in
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
                Text(attribution.explanation)
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
