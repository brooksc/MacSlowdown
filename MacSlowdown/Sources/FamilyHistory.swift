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
