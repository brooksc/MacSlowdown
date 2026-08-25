import Foundation
import Metrics
import Observation

/// One retained reading of one application family.
struct FamilyHistoryPoint: Equatable, Identifiable {
    let at: Date
    let percentOfOneCore: Double
    let residentBytes: UInt64

    var id: Date { at }
}

/// How a trailing figure describes itself on screen (FR-038, FR-002).
enum TrailingPresentation {
    /// "average over the last minute". The statistic and the window are both named,
    /// because a bare percentage beside an application's name reads as "right now"
    /// and that is a different claim.
    /// The window is a parameter with its own default rather than
    /// `FamilyHistory.defaultTrailingWindow`, which is main-actor isolated and so
    /// cannot be a default value here.
    static let defaultWindow: Duration = .seconds(60)

    static func caption(
        _ trailing: FamilyHistory.Trailing,
        requestedWindow: Duration = TrailingPresentation.defaultWindow
    ) -> String {
        "average over \(windowPhrase(trailing, requested: requestedWindow))"
    }

    /// Says the short span out loud when we have not been watching long enough to
    /// fill the window, rather than rounding up to the window we meant to use.
    static func windowPhrase(
        _ trailing: FamilyHistory.Trailing, requested: Duration
    ) -> String {
        // A tolerance rather than equality: samples land on a cadence, so a full
        // minute of coverage is almost never exactly sixty seconds of span.
        let shortfall = requested.totalSeconds - trailing.span.totalSeconds
        guard shortfall > requested.totalSeconds * 0.2 else { return phrase(requested) }
        return "the last \(Int(trailing.span.totalSeconds.rounded()))s — all we have"
    }

    private static func phrase(_ duration: Duration) -> String {
        let seconds = duration.totalSeconds
        if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "the last minute" : "the last \(minutes) min"
        }
        return "the last \(Int(seconds.rounded()))s"
    }
}

/// A change in memory over the window we actually observed (FR-044).
///
/// The span travels with the figure because "+1.9 GB" means very different things
/// over two minutes and over two hours, and we can only ever report the window the
/// app has been running for. Nothing here calls growth a leak: it is an observation
/// with several ordinary explanations.
struct MemoryGrowth: Equatable {
    let deltaBytes: Int64
    let span: Duration
}

/// Recent per-family history, recorded from what the store has already measured
/// (FR-005, FR-043).
///
/// **Why this exists in the app layer.** `MetricsHistory` retains the machine
/// aggregate and the five leading contributors, which is what FR-005 asks for and
/// what the incident record needs. The inspector asks a different question — how has
/// *this* application behaved — and answering it from the top-five list would show a
/// series full of holes for any application that drops out of the top five.
///
/// **Why it is bounded to a handful of families.** Retaining a series for every
/// family would mean roughly 800 of them: a quarter of an hour at a two-second
/// cadence is ~450 samples each, which is tens of megabytes against FR-030's 100 MB
/// budget for the whole app. So the busiest families are tracked, plus whichever one
/// the user has selected. A family that has only just been selected has no history
/// yet, and the interface says so rather than drawing a flat line.
@MainActor
@Observable
final class FamilyHistory {
    /// Matches `MetricsHistory.defaultRetention`, so the two surfaces cover the
    /// same window and a user comparing them is not comparing different spans.
    static let window: Duration = MetricsHistory.defaultRetention
    /// How many families keep a series. The inspector only ever shows one.
    static let trackedLimit = 40

    private(set) var series: [String: [FamilyHistoryPoint]] = [:]
    /// Times at which a member process of a family was seen to be replaced by
    /// another process running the same command.
    ///
    /// **Not what the interface shows.** TASK-66 wired `LifecycleTracker` into
    /// `MonitorStore`, and the inspector's relaunch figure now comes from there —
    /// the tracker watches the whole process table rather than only the families
    /// tracked here. This remains as the series' own bookkeeping; anything
    /// user-facing must read the store, or the two counts would differ with no way
    /// for a reader to tell which was right.
    private(set) var relaunches: [String: [Date]] = [:]
    /// Previous tick's members, per tracked family: command name to identities.
    private var previousMembers: [String: [String: Set<ProcessIdentity>]] = [:]

    /// Records one sample.
    ///
    /// `rows` supplies the aggregates the table already computed; `families` supply
    /// the member identities, which is the only way a replacement can be seen.
    func record(
        rows: [InventoryRow],
        families: [ProcessFamily],
        selected: String?,
        at now: Date = Date()
    ) {
        let applications = rows.filter { $0.kind == .application }
        let tracked = Self.tracked(applications, selected: selected)
        let familiesByID = Dictionary(families.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cutoff = now.addingTimeInterval(-Self.window.totalSeconds)

        for row in applications where tracked.contains(row.id) {
            var points = series[row.id] ?? []
            points.append(FamilyHistoryPoint(
                at: now, percentOfOneCore: row.percentOfOneCore,
                residentBytes: row.residentBytes))
            series[row.id] = Array(points.drop { $0.at < cutoff })

            let members = Self.membersByCommand(familiesByID[row.id])
            if let earlier = previousMembers[row.id] {
                let replacements = Self.replacements(from: earlier, to: members)
                if replacements > 0 {
                    relaunches[row.id, default: []]
                        .append(contentsOf: Array(repeating: now, count: replacements))
                }
            }
            previousMembers[row.id] = members
            relaunches[row.id] = relaunches[row.id]?.filter { $0 >= cutoff }
        }

        // Anything no longer tracked stops costing memory. Its history is dropped
        // rather than frozen: a stale series presented as current would be exactly
        // the stale-reading-as-fresh problem FR-002 forbids.
        for id in Array(series.keys) where !tracked.contains(id) {
            series[id] = nil
            relaunches[id] = nil
            previousMembers[id] = nil
        }
    }

    func points(for id: String) -> [FamilyHistoryPoint] { series[id] ?? [] }

    /// The trailing window every surface averages over unless it says otherwise.
    /// Mirrored by `TrailingPresentation.defaultWindow`, which the copy layer needs
    /// outside this type's actor isolation; a test holds the two equal.
    static let defaultTrailingWindow: Duration = .seconds(60)

    /// A trailing statistic, carried with the evidence it was computed from.
    ///
    /// The window and the sample count travel with the number because FR-038
    /// requires a derived value to say what it derives from: "29%" and "29% on
    /// average over the last minute, from 47 readings" are different claims, and
    /// only the second is true of a mean.
    struct Trailing: Equatable {
        let meanPercentOfOneCore: Double
        let peakPercentOfOneCore: Double
        let sampleCount: Int
        /// The span actually covered — at most the window asked for, and less
        /// whenever we have not been watching that long.
        let span: Duration
    }

    /// Trailing statistics for one family, or nil when nothing was retained in the
    /// window.
    ///
    /// Nil rather than zero, always: "we have no readings" and "it used no CPU" are
    /// different statements and only one is a measurement (FR-002).
    func trailing(
        for id: String,
        window: Duration = FamilyHistory.defaultTrailingWindow,
        now: Date = Date()
    ) -> Trailing? {
        let cutoff = now.addingTimeInterval(-window.totalSeconds)
        let points = points(for: id).filter { $0.at >= cutoff }
        guard let first = points.first, let last = points.last else { return nil }
        let total = points.reduce(0) { $0 + $1.percentOfOneCore }
        return Trailing(
            meanPercentOfOneCore: total / Double(points.count),
            peakPercentOfOneCore: points.map(\.percentOfOneCore).max() ?? 0,
            sampleCount: points.count,
            span: .seconds(last.at.timeIntervalSince(first.at)))
    }

    /// The span actually covered, which is never longer than the app has been open.
    func observedSpan(for id: String) -> Duration {
        let points = points(for: id)
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return .zero
        }
        return .seconds(last.at.timeIntervalSince(first.at))
    }

    /// Memory growth over the observed window, or nil when too little has been seen
    /// to say anything. A minute of samples is not a trend.
    func growth(for id: String, minimumSpan: Duration = .seconds(120)) -> MemoryGrowth? {
        let points = points(for: id)
        guard let first = points.first, let last = points.last else { return nil }
        let span = observedSpan(for: id)
        guard span.totalSeconds >= minimumSpan.totalSeconds else { return nil }
        return MemoryGrowth(
            deltaBytes: Int64(last.residentBytes) - Int64(first.residentBytes), span: span)
    }

    /// Processes seen to exit and be replaced by another running the same command,
    /// within the retained window.
    func relaunchCount(for id: String) -> Int { relaunches[id]?.count ?? 0 }

    /// Whether we have watched this family long enough for a relaunch count of zero
    /// to mean anything. Before that, zero means "we have not been looking".
    func hasWatchedLongEnough(for id: String, minimum: Duration = .seconds(120)) -> Bool {
        observedSpan(for: id).totalSeconds >= minimum.totalSeconds
    }

    // MARK: - Pure helpers

    /// The busiest families by CPU, then by memory, plus the selection.
    static func tracked(_ rows: [InventoryRow], selected: String?) -> Set<String> {
        var ids = Set(rows
            .sorted {
                $0.percentOfOneCore != $1.percentOfOneCore
                    ? $0.percentOfOneCore > $1.percentOfOneCore
                    : $0.residentBytes > $1.residentBytes
            }
            .prefix(trackedLimit)
            .map(\.id))
        if let selected, rows.contains(where: { $0.id == selected }) { ids.insert(selected) }
        return ids
    }

    static func membersByCommand(
        _ family: ProcessFamily?
    ) -> [String: Set<ProcessIdentity>] {
        guard let family else { return [:] }
        var result: [String: Set<ProcessIdentity>] = [:]
        for member in family.members {
            result[member.record.command, default: []].insert(member.record.identity)
        }
        return result
    }

    /// How many processes were replaced between two ticks.
    ///
    /// A replacement is one identity gone and another arrived under the same
    /// command, which is what a relaunch looks like from outside. Identity is
    /// `(pid, start time)`, so a recycled PID reads as a replacement rather than as
    /// continuity — the same rule `LifecycleTracker` uses.
    ///
    /// This deliberately reports neither a crash nor a hang. We can see that a
    /// process went away and one like it came back; we cannot see why, and macOS
    /// reports a stalled app exactly as it reports a healthy one.
    static func replacements(
        from earlier: [String: Set<ProcessIdentity>],
        to later: [String: Set<ProcessIdentity>]
    ) -> Int {
        var count = 0
        for (command, before) in earlier {
            guard let after = later[command] else { continue }
            let gone = before.subtracting(after).count
            let arrived = after.subtracting(before).count
            count += min(gone, arrived)
        }
        return count
    }
}
