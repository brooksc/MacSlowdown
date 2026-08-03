import Metrics
import SwiftUI

/// The evidence behind one incident (FR-013, FR-038, FR-054).
///
/// Design reference: 1e, and 1h for the unattributable case — which is not an
/// error state but roughly 40% of real incidents, so it has to read as a useful
/// answer rather than an apology.
struct IncidentDetailView: View {
    let incident: Incident
    let store: MonitorStore

    private var summary: IncidentSummary {
        IncidentSummarizer.summarize(incident: incident, attribution: store.attribution)
    }

    private var investigation: GuidedInvestigation {
        InvestigationBuilder.build(
            incident: incident, summary: summary, attribution: store.attribution)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                findings
                if !summary.ruledOut.isEmpty {
                    ruledOutSection
                }
                Divider()
                rawEvidence
                Divider()
                investigationSteps
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.headline).font(.title3).bold()
            Text(incident.isOpen ? "Still going" : "Recovered")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What we found").font(.headline)
            ForEach(Array(summary.conclusions.enumerated()), id: \.offset) { _, conclusion in
                ConclusionRow(conclusion: conclusion)
            }
        }
    }

    private var ruledOutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ruled out").font(.headline)
            ForEach(Array(summary.ruledOut.enumerated()), id: \.offset) { _, conclusion in
                ConclusionRow(conclusion: conclusion)
            }
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

/// One statement, always showing how it is known (FR-038).
struct ConclusionRow: View {
    let conclusion: Conclusion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
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
