import Foundation
import Metrics

/// One plotted reading. Always a sample that was actually taken — there is no
/// initialiser that invents a point, and nothing here ever produces one.
struct SparklinePoint: Equatable {
    let at: Date
    let value: Double
}

/// The rules a history sparkline has to obey, kept out of the view so they are
/// reachable from a test.
///
/// The rules exist because a small chart is unusually good at implying things
/// nobody measured. Four of them, in the order they bite:
///
/// 1. **Only measured samples.** The series comes from `MonitorStore.retainedSamples`
///    — the same series FR-005 keeps as evidence — never from a second series a
///    view accumulated for itself. Two curves over the same minutes that disagree
///    would be a fabrication in whichever one is wrong, and there would be no way
///    to tell which.
/// 2. **Never pad the window.** When the retained span is shorter than the window
///    the design asks for, the span we have is drawn and `spanCaption` says so. The
///    line does not start at zero at the left edge to fill the space, because a
///    zero there is a claim the machine was idle when in truth we were not running.
/// 3. **Never bridge a gap.** Consecutive samples further apart than the cadence
///    allows for mean we stopped sampling. `runs` splits the series there so the
///    stroke breaks, rather than drawing a straight line across minutes nobody
///    observed.
/// 4. **Too few points is a sentence, not a flat line.** A two-point series drawn
///    as a curve reads as "nothing happened". The truth is "we have not watched
///    long enough", and `readiness` returns that in words.
enum SparklinePresentation {
    /// Below this a curve says more about the axis than about the machine.
    ///
    /// Five is a judgement, not a measurement: at the 2 s base cadence it is about
    /// ten seconds of observation, which is the point at which a shape starts to
    /// carry information. The wording that replaces the curve names the actual
    /// count, so the reader is never left guessing how thin the evidence is.
    static let minimumPoints = 5

    // MARK: - Building a series from what was retained

    /// Machine-aggregate busy CPU, which `MetricsHistory` records on every sample.
    ///
    /// Complete by construction: every retained sample carries this field, so the
    /// series has a point wherever we have a sample and no point where we do not.
    static func totalBusySeries(_ samples: [HistorySample]) -> [SparklinePoint] {
        samples.map { SparklinePoint(at: $0.timestamp, value: $0.totalBusyPercentOfOneCore) }
    }

    /// CPU we were not permitted to attribute, which is exactly the "System
    /// processes" row's figure (`InventoryRow` builds that row from
    /// `unattributedPercentOfOneCore`).
    ///
    /// This is the one contributor row with an honest history: it is retained on
    /// every sample, so its curve has the same coverage as the aggregate. Every
    /// other row is an application family, and see `perFamilyHistoryIsRetained`.
    static func unattributedSeries(_ samples: [HistorySample]) -> [SparklinePoint] {
        samples.map { SparklinePoint(at: $0.timestamp, value: $0.unattributedPercentOfOneCore) }
    }

    /// Whether the retained history can support a curve for one application family.
    ///
    /// **It can, since 2026-08-25 (TASK-95).** It could not before, and the reason
    /// is worth keeping because it is what the fix had to answer:
    /// `HistorySample.topContributors` holds a bounded set of leading *processes*
    /// keyed by `(pid, start time)`, which left three holes — a family outside the
    /// leading few is absent from most samples; a family of many small processes
    /// can rank highly while no single member ever enters the list; and a member
    /// that has since exited cannot be matched back to its family, so its past
    /// readings would vanish and the curve would dip for a reason that never
    /// happened.
    ///
    /// The answer was not to draw that more bravely. `FamilyHistory` records each
    /// family's **sum** on every sampling pass, keyed on family identity, so the
    /// coverage now matches the machine total's: a point per sample, and a genuine
    /// gap only where the family was not running.
    static let perFamilyHistoryIsRetained = true

    /// Member rows, on the other hand, still have none — and for the reason above:
    /// history is keyed on the family, because a family outlives the processes in
    /// it and pids are recycled.
    static let perProcessHistoryExplanation =
        "History is retained for each application, not for each of its processes. "
        + "Processes come and go — and macOS reuses their identifiers — so a curve "
        + "for one of them would break every time the application replaced it."

    // MARK: - Enough to draw?

    enum Readiness: Equatable {
        /// Not enough retained readings for a curve to mean anything. The string is
        /// what to show instead, and it says we have not watched long enough — never
        /// that nothing happened.
        case tooFew(String)
        case ready
    }

    static func readiness(
        _ points: [SparklinePoint], minimumPoints: Int = SparklinePresentation.minimumPoints
    ) -> Readiness {
        guard points.count < minimumPoints else { return .ready }
        let counted = points.count == 1 ? "1 reading" : "\(points.count) readings"
        return .tooFew(
            "\(counted) retained so far. A trend needs at least \(minimumPoints), "
            + "so there is nothing to draw yet — this is how long we have been "
            + "watching, not how quiet the machine has been.")
    }

    // MARK: - The span actually covered

    /// Wall-clock span between the first and last retained reading.
    static func span(_ points: [SparklinePoint]) -> Duration {
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return .zero
        }
        return .seconds(last.at.timeIntervalSince(first.at))
    }

    /// What the axis is actually showing.
    ///
    /// When the retained span is short of the window, the caption says both figures.
    /// The alternative — labelling the chart "Last 15 min" over four minutes of
    /// samples — would make the empty three-quarters read as measured calm.
    static func spanCaption(_ points: [SparklinePoint], window: Duration) -> String {
        let covered = span(points)
        // Within a couple of samples of full is "full": the ring buffer's oldest
        // sample ages out continuously, so an exact comparison would flicker.
        if covered.totalSeconds >= window.totalSeconds * 0.95 {
            return "Last \(spanPhrase(window.totalSeconds))"
        }
        return "Last \(spanPhrase(covered.totalSeconds)) — all we have retained, "
            + "of a \(spanPhrase(window.totalSeconds)) window"
    }

    /// Coarse by intent: the cadence does not justify second resolution above a
    /// minute, and below it the count of seconds is the honest thing to say.
    static func spanPhrase(_ seconds: Double) -> String {
        let seconds = max(0, seconds)
        guard seconds >= 60 else { return "\(Int(seconds.rounded())) s" }
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    // MARK: - Gaps

    /// How far apart two readings may be before the space between them counts as
    /// unobserved.
    ///
    /// Four intervals rather than one: the cadence is nominal, a sampling loop
    /// competing for a busy machine runs late (that is what FR-032's staleness is
    /// about), and breaking the stroke for ordinary jitter would invent gaps as
    /// readily as bridging them invents readings. The floor keeps a fast investigation
    /// cadence from making the threshold absurdly tight.
    static func gapThreshold(cadence: Duration) -> Duration {
        .seconds(max(cadence.totalSeconds * 4, 8))
    }

    /// The series split into stretches of continuous observation.
    ///
    /// More than one run means we stopped sampling — the app was quit and restarted
    /// against persisted history, or the machine slept. The view strokes each run
    /// separately so nothing is drawn across the interval, and `accessibilitySummary`
    /// says a gap exists so the break is not carried by the picture alone (FR-034).
    static func runs(_ points: [SparklinePoint], gapThreshold: Duration) -> [[SparklinePoint]] {
        guard !points.isEmpty else { return [] }
        var runs: [[SparklinePoint]] = []
        var current: [SparklinePoint] = [points[0]]
        for point in points.dropFirst() {
            let elapsed = point.at.timeIntervalSince(current[current.count - 1].at)
            if elapsed > gapThreshold.totalSeconds {
                runs.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        runs.append(current)
        return runs
    }

    // MARK: - Marking a moment on the axis

    /// Where a moment sits along the drawn span, as a fraction from 0 to 1.
    ///
    /// Nil when the moment is outside what we retained. That case has to be handled
    /// in words (`markerCaption`) rather than by clamping to an edge: a marker
    /// pinned to the left edge would claim the incident began exactly when our
    /// history happens to start, which is a coincidence, not a measurement.
    static func markerFraction(for date: Date, in points: [SparklinePoint]) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        let total = last.at.timeIntervalSince(first.at)
        guard total > 0 else { return nil }
        let offset = date.timeIntervalSince(first.at)
        guard offset >= 0, offset <= total else { return nil }
        return offset / total
    }

    /// The axis line under an incident sparkline: where the window starts, where the
    /// incident started, and that the right edge is now.
    ///
    /// The moment marked is the incident's own `beganAt`, never a feature of the
    /// curve. A chart that marked "where it looks like it started" would be
    /// asserting a detection we did not make.
    static func markerCaption(beganAt: Date, points: [SparklinePoint]) -> String {
        guard let first = points.first else { return "" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        let start = first.at.formatted(time)
        if markerFraction(for: beganAt, in: points) != nil {
            return "\(start) · started \(beganAt.formatted(time)) · now"
        }
        // Before our history: say so rather than move the mark to the edge.
        return "\(start) · now — it started at \(beganAt.formatted(time)), "
            + "before the history we still hold"
    }

    // MARK: - Saying it in words

    /// The chart, spoken. A sparkline with no accessible summary is not accessible
    /// (FR-034), and this is also the fallback wherever the curve is not drawn.
    ///
    /// Reports the retained span, the range, the latest reading and, when the series
    /// is broken, that a gap exists. Every figure comes from a plotted point.
    static func accessibilitySummary(
        title: String,
        points: [SparklinePoint],
        window: Duration,
        gapThreshold: Duration,
        format: (Double) -> String = { CPUPresentation.percentOfOneCore($0) }
    ) -> String {
        switch readiness(points) {
        case .tooFew(let sentence):
            return "\(title). \(sentence)"
        case .ready:
            break
        }
        let values = points.map(\.value)
        guard let lowest = values.min(), let highest = values.max(), let latest = values.last
        else { return title }

        var parts = [
            "\(title), \(spanCaption(points, window: window).lowercased())",
            "\(points.count) readings",
            "lowest \(format(lowest))",
            "highest \(format(highest))",
            "most recent \(format(latest))",
        ]
        if runs(points, gapThreshold: gapThreshold).count > 1 {
            parts.append("with a break where no readings were taken, which is not drawn across")
        }
        return parts.joined(separator: ", ") + "."
    }
}
