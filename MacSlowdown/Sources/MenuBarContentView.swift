import Metrics
import SwiftUI

/// Compact persistent status surface (FR-001).
///
/// Render-only. It reads from the store and opens windows; it never samples or
/// computes.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    let store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let attribution = store.attribution {
                breakdown(attribution)
            } else {
                Text("Taking the first reading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Open MacSlowdown") {
                openWindow(id: MainWindow.id)
                ActivationPolicy.mainWindowOpened()
            }
            .keyboardShortcut("o")

            Button("Quit MacSlowdown") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    private var header: some View {
        // Symbol, word and value together — severity is never carried by colour
        // alone (FR-034).
        HStack(spacing: 8) {
            Image(systemName: store.severity.symbolName)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.severity.label)
                    .font(.headline)
                if case .stale(let age) = store.freshness {
                    Text("Last complete reading, \(Int(age.totalSeconds))s ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overall condition: \(store.severity.label)")
    }

    @ViewBuilder
    private func breakdown(_ attribution: CPUAttribution) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Total CPU") {
                Text(CPUPresentation.percentOfOneCore(attribution.totalBusyPercentOfOneCore))
                    .monospacedDigit()
            }

            let leading = Array(attribution.contributors.prefix(3))
            ForEach(Array(leading.enumerated()), id: \.offset) { _, usage in
                LabeledContent {
                    Text(CPUPresentation.percentOfOneCore(usage.percentOfOneCore))
                        .monospacedDigit()
                } label: {
                    // The resolved name, never the kernel's 16-byte command. The
                    // store owns naming so this row, the table and the notification
                    // cannot disagree.
                    Text(store.displayName(for: usage))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(store.accessibilityName(for: usage)): "
                    + "\(CPUPresentation.percentOfOneCore(usage.percentOfOneCore)) of one core")
            }

            // Everything measured but not shown individually. Without this the
            // visible rows would not sum to the total, which is the same failure
            // the unattributed row exists to prevent — just from truncation rather
            // than from permissions.
            let remainder = attribution.attributedPercentOfOneCore
                - leading.reduce(0) { $0 + $1.percentOfOneCore }
            if remainder > 0.5 {
                LabeledContent("Other applications") {
                    Text(CPUPresentation.percentOfOneCore(remainder)).monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            // Always present, so the list visibly accounts for the whole machine
            // rather than silently failing to sum.
            LabeledContent {
                Text(CPUPresentation.percentOfOneCore(attribution.unattributedPercentOfOneCore))
                    .monospacedDigit()
            } label: {
                Label("Unattributed system activity", systemImage: "lock")
                    .labelStyle(.titleAndIcon)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .help(attribution.explanation)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Unattributed system activity: "
                + "\(CPUPresentation.percentOfOneCore(attribution.unattributedPercentOfOneCore)) "
                + "of one core")
            .accessibilityHint(attribution.explanation)

            Text(CPUPresentation.convention())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
