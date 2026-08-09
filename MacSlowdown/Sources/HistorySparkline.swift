import Metrics
import SwiftUI

/// A small curve over retained history (FR-005). Design references: 1b and 1c.
///
/// Render-only, and deliberately incapable of inventing a reading: it plots the
/// points it is handed, breaks the stroke wherever `SparklinePresentation.runs`
/// says we stopped observing, and draws nothing at all when there are too few
/// points — in which case the caller shows the sentence instead. See
/// `SparklinePresentation` for why each of those is a rule rather than a taste.
///
/// The curve is never the only carrier of meaning: `summary` states the same thing
/// in words for VoiceOver, and the caller states the span beneath it (FR-034).
struct HistorySparkline: View {
    let points: [SparklinePoint]
    /// Moments to mark, from their own source — an incident's `beganAt`, not a
    /// feature of the curve. Marks outside the retained span are dropped here and
    /// explained in words by the caller.
    var markers: [Date] = []
    var gapThreshold: Duration = SparklinePresentation.gapThreshold(
        cadence: MetricsHistory.defaultCadence)
    var height: CGFloat = 34
    /// The chart, spoken. Required, because a sparkline VoiceOver cannot read is
    /// not accessible.
    let summary: String

    /// The top of the axis.
    ///
    /// From the data, with a small headroom so the peak is not welded to the top
    /// edge, and a floor so a genuinely quiet stretch does not get amplified into a
    /// dramatic curve by autoscaling to a 3% peak.
    private var yMax: Double {
        let peak = points.map(\.value).max() ?? 0
        return max(peak * 1.15, 100)
    }

    var body: some View {
        Canvas { context, size in
            let runs = SparklinePresentation.runs(points, gapThreshold: gapThreshold)
            for run in runs {
                guard let first = run.first else { continue }
                if run.count == 1 {
                    // One isolated reading is a dot. Drawing it as a line would need
                    // a second point we do not have.
                    let point = CGPoint(x: x(for: first.at, in: size),
                                        y: y(for: first.value, in: size))
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5,
                                               width: 3, height: 3)),
                        with: .color(.accentColor))
                    continue
                }
                var path = Path()
                for (index, point) in run.enumerated() {
                    let location = CGPoint(x: x(for: point.at, in: size),
                                           y: y(for: point.value, in: size))
                    index == 0 ? path.move(to: location) : path.addLine(to: location)
                }
                context.stroke(path, with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }

            for marker in markers {
                guard let fraction = SparklinePresentation.markerFraction(
                    for: marker, in: points) else { continue }
                let markerX = size.width * CGFloat(fraction)
                var rule = Path()
                rule.move(to: CGPoint(x: markerX, y: 0))
                rule.addLine(to: CGPoint(x: markerX, y: size.height))
                // Dashed rule plus the caption underneath: the mark is never carried
                // by colour alone (FR-034).
                context.stroke(rule, with: .color(.primary.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(summary)
    }

    private func x(for date: Date, in size: CGSize) -> CGFloat {
        guard let first = points.first, let last = points.last else { return 0 }
        let total = last.at.timeIntervalSince(first.at)
        guard total > 0 else { return size.width / 2 }
        let fraction = min(max(date.timeIntervalSince(first.at) / total, 0), 1)
        return size.width * CGFloat(fraction)
    }

    private func y(for value: Double, in size: CGSize) -> CGFloat {
        guard yMax > 0 else { return size.height }
        let fraction = min(max(value / yMax, 0), 1)
        return size.height * CGFloat(1 - fraction)
    }
}

/// A sparkline with its span caption, or the sentence that replaces it when too
/// little has been retained to draw one.
///
/// One view rather than two so no caller can accidentally show the curve without
/// the span it covers — the caption is what stops four minutes of samples reading
/// as a quiet quarter of an hour.
struct HistorySparklineBlock: View {
    let title: String
    let points: [SparklinePoint]
    var markers: [Date] = []
    var window: Duration = MetricsHistory.defaultRetention
    var cadence: Duration = MetricsHistory.defaultCadence
    var height: CGFloat = 34
    /// An extra line under the span caption — the incident-start axis, for
    /// instance. Additional to the span, never a replacement for it: the span is
    /// what stops a short series reading as a long quiet one.
    var axisCaption: String?

    private var gapThreshold: Duration {
        SparklinePresentation.gapThreshold(cadence: cadence)
    }

    /// The chart in words. Exposed so a container that overrides its own
    /// accessibility label can fold this in rather than silently dropping it.
    var accessibleSummary: String {
        SparklinePresentation.accessibilitySummary(
            title: title, points: points, window: window, gapThreshold: gapThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch SparklinePresentation.readiness(points) {
            case .tooFew(let sentence):
                Text(sentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(title). \(sentence)")
            case .ready:
                HistorySparkline(
                    points: points, markers: markers,
                    gapThreshold: gapThreshold, height: height, summary: accessibleSummary)
                Text(SparklinePresentation.spanCaption(points, window: window))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                if let axisCaption {
                    Text(axisCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(axisCaption)
                }
            }
        }
    }
}
