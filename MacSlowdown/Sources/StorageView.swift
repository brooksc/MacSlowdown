import Metrics
import SwiftUI

/// Capacity for mounted volumes (FR-041). Design reference: 1l.
struct StorageView: View {
    let store: MonitorStore

    private var snapshot: StorageSnapshot { StorageSignals.snapshot() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let current = snapshot
                ForEach(current.volumes) { volume in
                    VolumeCard(volume: volume)
                }

                if !current.unreadable.isEmpty {
                    unreadableSection(current.unreadable)
                }

                Text(StorageSignals.purgeableCaveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Storage")
    }

    /// FR-041: volumes we cannot read are listed with a reason rather than
    /// hidden, so the picture is visibly incomplete rather than silently wrong.
    private func unreadableSection(_ volumes: [UnreadableVolume]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not measured").font(.headline)
            ForEach(volumes) { volume in
                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.name)
                    Text(volume.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct VolumeCard: View {
    let volume: VolumeCapacity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.name).font(.headline)
                if volume.isStartupVolume {
                    Text("Startup volume").font(.caption).foregroundStyle(.secondary)
                }
            }

            ProgressView(value: 1 - volume.availableFraction)
                .accessibilityLabel("\(volume.name) is "
                                    + "\(Int(((1 - volume.availableFraction) * 100).rounded()))% full")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Available")
                    Text(format(volume.availableBytes)).monospacedDigit()
                    Text("Measured").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("In use")
                    Text(format(volume.usedBytes)).monospacedDigit()
                    Text("Calculated").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Capacity")
                    Text(format(volume.totalBytes)).monospacedDigit()
                    Text("Measured").font(.caption).foregroundStyle(.secondary)
                }
                if let purgeable = volume.purgeableEstimateBytes {
                    GridRow {
                        Text("Purgeable")
                        Text(format(purgeable)).monospacedDigit()
                        // Never "Measured": macOS may not release it, so presenting
                        // it as fact would be the error FR-041 calls out.
                        Text("Estimate").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func format(_ bytes: UInt64) -> String {
        ByteCountFormatStyle().format(Int64(bytes))
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
