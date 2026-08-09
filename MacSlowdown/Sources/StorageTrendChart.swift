import Metrics
import SwiftUI

/// The available-space curve for one volume, with the low-storage warning line and
/// any incident that opened against it (FR-041, FR-042). Design reference: 1l.
///
/// Drawn only from readings that exist. There is no interpolation across a gap
/// when the app was not running, no extrapolation to the right edge, and no chart
/// at all until there is enough history — the caller decides that, and the finding
/// is always stated in words beside this, never carried by the curve alone
/// (FR-034: severity is never conveyed by colour or shape alone).
struct StorageTrendChart: View {
    let readings: [StorageReading]
    let thresholdBytes: UInt64
    /// When a low-storage incident opened, for the marks on the curve.
    let incidentOpenings: [Date]
    /// Stated in words for VoiceOver; the curve is reinforcement.
    let accessibilitySummary: String

    private var span: (start: Date, end: Date)? {
        guard let first = readings.first, let last = readings.last, first.timestamp < last.timestamp
        else { return nil }
        return (first.timestamp, last.timestamp)
    }

    private var yMax: Double {
        let peak = readings.map(\.availableBytes).max() ?? thresholdBytes
        return Double(max(peak, thresholdBytes)) * 1.12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart
                .frame(height: 120)
                .accessibilityElement()
                .accessibilityLabel(accessibilitySummary)
            axisLabels
            legend
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let span {
            Canvas { context, size in
                let thresholdY = y(for: Double(thresholdBytes), in: size)

                // The band below the warning line, so the region reads as a region
                // and not only as a dashed rule.
                context.fill(
                    Path(CGRect(x: 0, y: thresholdY,
                                width: size.width, height: max(0, size.height - thresholdY))),
                    with: .color(.orange.opacity(0.10)))

                var threshold = Path()
                threshold.move(to: CGPoint(x: 0, y: thresholdY))
                threshold.addLine(to: CGPoint(x: size.width, y: thresholdY))
                context.stroke(
                    threshold, with: .color(.orange),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                var line = Path()
                for (index, reading) in readings.enumerated() {
                    let point = CGPoint(
                        x: x(for: reading.timestamp, span: span, in: size),
                        y: y(for: Double(reading.availableBytes), in: size))
                    index == 0 ? line.move(to: point) : line.addLine(to: point)
                }
                context.stroke(line, with: .color(.accentColor), lineWidth: 2)

                for opening in incidentOpenings {
                    let markX = x(for: opening, span: span, in: size)
                    let markY = y(for: Double(available(at: opening)), in: size)
                    let dot = Path(ellipseIn: CGRect(
                        x: markX - 4, y: markY - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(.orange))
                    context.stroke(dot, with: .color(.primary.opacity(0.6)), lineWidth: 1)
                }
            }
        } else {
            EmptyView()
        }
    }

    private var axisLabels: some View {
        HStack {
            if let span {
                Text(span.start, format: .dateTime.month().day())
                Spacer()
                Text(span.end, format: .dateTime.month().day().hour().minute())
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label(
                LowStorageDetector.warningLineLegend(
                    thresholdBytes: StoragePresentation.bytes(thresholdBytes)),
                systemImage: "minus")
            if !incidentOpenings.isEmpty {
                Label("Incident opened here", systemImage: "circle.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    /// The measured available space at the reading nearest the incident, so the
    /// mark sits on the curve rather than at an invented value.
    private func available(at date: Date) -> UInt64 {
        readings.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }?.availableBytes ?? thresholdBytes
    }

    private func x(for date: Date, span: (start: Date, end: Date), in size: CGSize) -> CGFloat {
        let total = span.end.timeIntervalSince(span.start)
        guard total > 0 else { return 0 }
        let fraction = (date.timeIntervalSince(span.start) / total).clamped(to: 0...1)
        return size.width * CGFloat(fraction)
    }

    private func y(for value: Double, in size: CGSize) -> CGFloat {
        guard yMax > 0 else { return size.height }
        return size.height * CGFloat(1 - (value / yMax).clamped(to: 0...1))
    }
}

extension LowStorageDetector {
    /// Legend text for the warning line, kept beside the detector's own wording so
    /// the chart and the detection cannot describe different thresholds.
    static func warningLineLegend(thresholdBytes: String) -> String {
        "Low-storage warning line · \(thresholdBytes)"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
