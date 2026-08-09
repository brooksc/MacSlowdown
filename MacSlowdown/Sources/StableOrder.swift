import Foundation

/// The rule the tables' ordering obeys, in one place so the code, the footer a user
/// reads and the tests cannot disagree about it (TASK-74).
///
/// **Why hold the order at all.** The inventory ranks ~425 application rows by a
/// figure that jitters every sample. Re-ranking every 2 s means the row a user is
/// reaching for moves out from under the pointer, which makes a list that is
/// technically correct practically unreadable. The design's inventory (screen 1d)
/// shows a settled list, not a leaderboard mid-shuffle.
///
/// **The second reason, and it is second.** TASK-67 established that SwiftUI's
/// `Table` performs a reentrant `NSTableView` delegate operation whenever rows are
/// *reordered* — proved with a frozen array shuffled between samples, identical
/// identities, values and count, 21 warnings in 25 s against 0 for the same array
/// left alone. AppKit says the warning becomes an assert in a future release. A
/// sample that reorders nothing warns not at all, so ordering less often warns less
/// often. Nothing here touches logging, asserts or the warning itself: the change is
/// to when rows move, and the warning frequency is a consequence of that.
enum OrderStability {
    /// How long a displayed order stands before a changed ranking replaces it.
    ///
    /// Ten seconds is roughly five sampling intervals: long enough to find a row,
    /// move to it and click it without it moving, short enough that nobody reads a
    /// stale order for long. It is an upper bound on how out of date the *order* may
    /// be — never on how out of date the *numbers* are, which are always from the
    /// most recent sample.
    static let settleInterval: TimeInterval = 10

    /// Stated on screen, because an order that is deliberately not live is a fact a
    /// user needs, not an implementation detail.
    static let explanation =
        "Rows keep their places while you read: the numbers update every sample, and "
        + "the list re-ranks at most once every \(Int(settleInterval)) seconds. "
        + "Processes that start or stop are added and removed straight away; "
        + "sorting or searching re-ranks it at once."
}

/// A row in a table whose order is damped. Rows with children — the inventory's
/// expandable families — hold their children's order too.
protocol StablyOrdered: Identifiable where ID: Hashable {
    var stableChildren: [Self] { get set }
}

extension StablyOrdered {
    /// Most rows have no children. A no-op setter is correct for them: there is
    /// nothing to write back.
    var stableChildren: [Self] {
        get { [] }
        set { _ = newValue }
    }
}

/// Holds a table's displayed order steady between samples.
///
/// **Values are never held — only positions.** Every call emits the rows it was
/// given, which carry the newest sample's numbers; all this type decides is the
/// sequence they come out in. Emitting a remembered *row* rather than a remembered
/// *position* would put a stale reading on screen as though it were current, which
/// FR-002 and FR-032 forbid.
///
/// It also never encodes position into identity — rows are matched by their own
/// `id`, so selection and expansion, which are keyed on the same ids, survive every
/// reorder (FR-027). TASK-67 rejected position-encoded identity for exactly that
/// reason.
struct StableOrder<Row: StablyOrdered> {
    private var held: [Row.ID] = []
    private var childHeld: [Row.ID: [Row.ID]] = [:]
    private var lastReorder: Date?

    /// Forgets the held order, so the next `settle` adopts the ranking whole.
    ///
    /// This is what "the user asked" looks like: a column heading clicked, a search
    /// term changed. Damping applies to data churn and never to user intent.
    mutating func reset() {
        held = []
        childHeld = [:]
        lastReorder = nil
    }

    /// The rows to display, in the order to display them.
    ///
    /// - Rows that ended are dropped and rows that appeared are inserted at their
    ///   ranked position immediately, so the *set* on screen is always current. That
    ///   is an insertion or a removal, not a reorder: the rows already on screen keep
    ///   their order relative to each other.
    /// - The order itself is replaced by the current ranking only once
    ///   `OrderStability.settleInterval` has passed since the last time it changed.
    ///   A ranking that has not changed costs nothing and does not restart the clock.
    mutating func settle(_ ranked: [Row], now: Date = Date()) -> [Row] {
        let rankedIDs = ranked.map(\.id)
        let mayReorder = lastReorder.map { now.timeIntervalSince($0) >= OrderStability.settleInterval }
            ?? true

        let order: [Row.ID]
        if mayReorder {
            order = rankedIDs
            if order != held { lastReorder = now }
        } else {
            order = Self.spliced(held: held, ranked: rankedIDs)
        }
        held = order

        let byID = Dictionary(ranked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Row] = []
        result.reserveCapacity(order.count)
        for id in order {
            guard var row = byID[id] else { continue }
            let children = row.stableChildren
            if !children.isEmpty {
                let childRanked = children.map(\.id)
                let childOrder = mayReorder
                    ? childRanked
                    : Self.spliced(held: childHeld[id] ?? childRanked, ranked: childRanked)
                childHeld[id] = childOrder
                let childByID = Dictionary(
                    children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                row.stableChildren = childOrder.compactMap { childByID[$0] }
            }
            result.append(row)
        }
        // A family that has gone should not keep a remembered child order alive.
        let present = Set(order)
        childHeld = childHeld.filter { present.contains($0.key) }
        return result
    }

    /// The held order with departures removed and arrivals inserted where the
    /// ranking puts them, relative to the rows already on screen.
    private static func spliced(held: [Row.ID], ranked: [Row.ID]) -> [Row.ID] {
        let present = Set(ranked)
        var order = held.filter(present.contains)
        guard order.count != ranked.count else { return order }

        var placed = Set(order)
        for (index, id) in ranked.enumerated() where !placed.contains(id) {
            // Just after the nearest higher-ranked row that is already on screen —
            // which may be an arrival placed a moment ago, so several new rows keep
            // their ranked order relative to each other.
            var insertAt = 0
            var scan = index - 1
            while scan >= 0 {
                if let position = order.firstIndex(of: ranked[scan]) {
                    insertAt = position + 1
                    break
                }
                scan -= 1
            }
            order.insert(id, at: insertAt)
            placed.insert(id)
        }
        return order
    }
}
