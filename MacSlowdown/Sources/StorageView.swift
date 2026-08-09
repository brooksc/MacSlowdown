import Metrics
import SwiftUI

/// Capacity, trend, and what cannot be read, for every mounted volume
/// (FR-041, FR-042). Design reference: 1l.
struct StorageView: View {
    let store: MonitorStore
    @State private var model = StorageScreenModel.shared

    /// Low-storage incidents, newest first. Only incidents that actually carry the
    /// low-storage condition — a CPU incident is not evidence about a disk.
    private var lowStorageIncidents: [Incident] {
        ([store.openIncident].compactMap { $0 } + store.recentIncidents)
            .filter { $0.conditions.contains(.lowStorage) }
            .sorted { $0.beganAt > $1.beganAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let startup = model.startupVolume {
                    StartupVolumeCard(
                        volume: startup, model: model, incidents: lowStorageIncidents)
                }

                otherVolumes

                provenanceFooter
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                // FR-002: how old the reading is, not an implied "now".
                if let freshness = StoragePresentation.freshness(
                    lastChecked: model.lastChecked, now: model.now) {
                    Text(freshness).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            model.refresh()
            // Re-reads while the screen is open. The capacity series coalesces to
            // its own quarter-hour interval, so this costs resource-value reads
            // and no extra disk writes (FR-030).
            while !Task.isCancelled {
                try? await Task.sleep(for: StorageScreenModel.refreshInterval)
                if Task.isCancelled { return }
                model.refresh()
            }
        }
    }

    /// Every other mounted volume, including the ones we cannot read and the ones
    /// monitoring excludes. Nothing is dropped, so an incomplete picture is
    /// visibly incomplete (FR-002, FR-010, FR-041).
    @ViewBuilder
    private var otherVolumes: some View {
        let others = model.otherVolumes
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Other volumes").font(.headline)
                Text(others.isEmpty
                     ? "none mounted"
                     : "\(others.count) mounted")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, others.isEmpty ? 0 : 8)

            ForEach(others) { volume in
                Divider().opacity(volume.id == others.first?.id ? 0 : 1)
                OtherVolumeRow(volume: volume) { model.include(volume) }
                    .padding(.vertical, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// FR-038: every figure on this screen is one of these three, and the
    /// purgeable caveat travels with the estimate.
    private var provenanceFooter: some View {
        let caveat = StorageSignals.purgeableCaveat.prefix(1).lowercased()
            + StorageSignals.purgeableCaveat.dropFirst()
        let markdown =
            "**Measured** — total and available capacity, read from the volume itself. "
            + "**Calculated** — in use, and the rate of change over the recorded period. "
            + "**Estimate** — \(caveat)"
        return Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The startup volume: capacity, the segmented bar, the trend and its finding.
struct StartupVolumeCard: View {
    let volume: MountedVolume
    let model: StorageScreenModel
    let incidents: [Incident]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let capacity = volume.capacity {
                CapacityBar(capacity: capacity)
                capacityLegend(capacity)
                Divider()
                trendSection(capacity)
            } else {
                unavailable
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(volume.name).font(.headline)
            Text(volume.subtitle(isInternal: nil))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let capacity = volume.capacity {
                Text(StoragePresentation.headline(capacity))
                    .font(.callout).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var unavailable: some View {
        switch volume.state {
        case .unreadable(let reason), .excluded(let reason):
            Text(reason).font(.callout).foregroundStyle(.secondary)
        case .measured:
            EmptyView()
        }
    }

    /// Each figure keeps its provenance, and purgeable keeps its caveat attached
    /// to it rather than parked elsewhere on the screen (FR-041, FR-038).
    private func capacityLegend(_ capacity: VolumeCapacity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            legendRow(.primary, "In use \(StoragePresentation.bytes(capacity.usedBytes))",
                      provenance: "Calculated")
            if let purgeable = StoragePresentation.purgeable(capacity) {
                legendRow(.secondary, purgeable, provenance: "Estimate")
            }
            legendRow(.tertiary, "Free \(StoragePresentation.bytes(capacity.availableBytes))",
                      provenance: "Measured")
            legendRow(.quaternary, "Capacity \(StoragePresentation.bytes(capacity.totalBytes))",
                      provenance: "Measured")
        }
    }

    private func legendRow(
        _ shade: HierarchicalShapeStyle, _ text: String, provenance: String
    ) -> some View {
        HStack(spacing: 6) {
            // A shape as well as a shade: the swatch is never the only way to tell
            // the segments apart (FR-034).
            RoundedRectangle(cornerRadius: 2).fill(shade).frame(width: 9, height: 9)
            Text(text).font(.caption)
            Text(provenance).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(provenance)")
    }

    // MARK: - Trend

    @ViewBuilder
    private func trendSection(_ capacity: VolumeCapacity) -> some View {
        let readings = model.readings(for: volume)
        let trend = model.trend(for: volume)
        let covered = model.coveredDuration(for: volume)
        let threshold = model.detector.thresholdBytes(for: capacity)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(periodLabel(covered: covered, readings: readings.count)).font(.subheadline).bold()
                Text("available space").font(.caption).foregroundStyle(.secondary)
                Spacer()
                // The finding in words. This is the point of the section; the
                // curve reinforces it and never carries it alone.
                //
                // With its provenance attached to it, in the same idiom as the
                // capacity legend above: a direction and a byte figure over a
                // window are a calculation across readings, not a reading, and
                // showing them bare let the trend read as something the app had
                // measured directly (FR-038).
                VStack(alignment: .trailing, spacing: 1) {
                    Text(trend.statement)
                        .font(.callout)
                        .foregroundStyle(trend.isStillFalling ? .orange : .secondary)
                    Text(StoragePresentation.trendProvenance(trend))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(trend.statement), \(StoragePresentation.trendProvenance(trend))")
            }

            if case .insufficientHistory = trend {
                // No chart rather than a curve drawn through two points. History
                // begins when the app starts watching, and saying so is the
                // honest answer (FR-002).
                Text(model.detector.thresholdExplanation(for: capacity))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                StorageTrendChart(
                    readings: readings,
                    thresholdBytes: threshold,
                    incidentOpenings: incidentOpenings(within: readings),
                    accessibilitySummary: chartAccessibilitySummary(trend: trend, capacity: capacity))
                Text(model.detector.thresholdExplanation(for: capacity))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if let callout = incidentCallout(capacity) {
                calloutView(callout)
            } else if let standing = model.standing(for: volume, hadIncident: false) {
                Text(standing).font(.callout)
            }
        }
    }

    private func periodLabel(covered: Duration, readings: Int) -> String {
        guard readings >= 2, covered.totalSeconds > 0 else { return "No history yet" }
        // The period we actually have, never the retention window we hope for.
        return "Last \(StorageTrendAnalysis.describe(covered))"
    }

    private func incidentOpenings(within readings: [StorageReading]) -> [Date] {
        guard let first = readings.first?.timestamp, let last = readings.last?.timestamp
        else { return [] }
        return incidents.map(\.triggeredAt).filter { $0 >= first && $0 <= last }
    }

    private func chartAccessibilitySummary(trend: StorageTrend, capacity: VolumeCapacity) -> String {
        var parts = ["Available space over the recorded period.",
                     trend.statement,
                     StoragePresentation.trendProvenance(trend) + "."]
        parts.append(model.detector.thresholdExplanation(for: capacity) + ".")
        if let standing = model.standing(for: volume, hadIncident: !incidents.isEmpty) {
            parts.append(standing)
        }
        return parts.joined(separator: " ")
    }

    /// The incident, and the distinction the screen exists for: back above the
    /// line is not the same as the slide having stopped.
    private func incidentCallout(_ capacity: VolumeCapacity) -> String? {
        guard let incident = incidents.first else { return nil }
        var sentence = "\(volume.name) below the low-storage warning line — "
            + incident.beganAt.formatted(date: .abbreviated, time: .shortened)
        if incident.isOpen {
            sentence += ", still open."
        } else {
            sentence += ", lasted "
                + StorageTrendAnalysis.describe(incident.duration)
                + ", resolved on its own."
        }
        if let standing = model.standing(for: volume, hadIncident: true) {
            sentence += " " + standing
        }
        return sentence
    }

    private func calloutView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Symbol as well as colour (FR-034).
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

/// The proportions of one volume: in use, purgeable, free.
struct CapacityBar: View {
    let capacity: VolumeCapacity

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let purgeable = capacity.purgeableEstimateBytes ?? 0
            // Purgeable content is part of what is in use — it is occupied by
            // files macOS believes it could remove — so it is drawn inside the
            // used span, never added to free space (FR-041).
            let used = capacity.usedBytes >= purgeable ? capacity.usedBytes - purgeable : 0

            HStack(spacing: 1) {
                segment(width: width * fraction(used), style: AnyShapeStyle(.primary))
                segment(width: width * fraction(purgeable),
                        style: AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(
            "\(capacity.name): \(StoragePresentation.headline(capacity)), "
            + "\(Int((capacity.availableFraction * 100).rounded()))% free")
    }

    private func fraction(_ bytes: UInt64) -> CGFloat {
        guard capacity.totalBytes > 0 else { return 0 }
        return CGFloat(Double(bytes) / Double(capacity.totalBytes))
    }

    private func segment(width: CGFloat, style: AnyShapeStyle) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(style).frame(width: max(0, width))
    }
}

/// One non-startup volume: measured, unreadable, or excluded with a way in.
struct OtherVolumeRow: View {
    let volume: MountedVolume
    let include: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(volume.name)
            Text(volume.kind.label)
                .font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
            detail
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        switch volume.state {
        case .measured(let capacity):
            HStack(spacing: 8) {
                CapacityBar(capacity: capacity)
                    .frame(width: 120)
                    .accessibilityHidden(true)
                Text(StoragePresentation.headline(capacity))
                    .monospacedDigit()
                Text("Measured").font(.caption2).foregroundStyle(.secondary)
            }
        case .unreadable(let reason):
            // Stated, never omitted: the row exists precisely so the gap is
            // visible (FR-002, FR-010).
            Text("Can't be read — \(reason.prefix(1).lowercased())\(reason.dropFirst())")
                .foregroundStyle(.secondary)
        case .excluded(let reason):
            HStack(spacing: 6) {
                Text(reason).foregroundStyle(.secondary)
                Button("Include", action: include)
                    .buttonStyle(.link)
                    .accessibilityLabel("Include \(volume.name) in monitoring")
            }
        }
    }
}

/// The system signals, for the Now screen (FR-007, FR-008, FR-010, FR-047).
struct SystemSignalsView: View {
    let store: MonitorStore

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                signal("Memory pressure", store.memoryPressure.label)
                signal("Thermal state", store.thermalState.label)
            }
            GridRow {
                signal("Power", store.power.summary)
                signal("Disk", store.diskThroughput)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) { EmptyView() }
    }

    private func signal(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
