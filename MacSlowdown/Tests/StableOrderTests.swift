import Foundation
import Testing

@testable import MacSlowdown

/// A row with a value that changes and children that reorder, which is the whole of
/// what `StableOrder` has to cope with.
private struct Sample: StablyOrdered, Equatable {
    let id: String
    var value: Int
    var children: [Sample] = []

    var stableChildren: [Sample] {
        get { children }
        set { children = newValue }
    }
}

/// Ranked the way the tables rank: value descending, name for the ties.
private func ranked(_ rows: [Sample]) -> [Sample] {
    rows.sorted {
        $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value
    }
    .map { row in
        var copy = row
        copy.children = ranked(row.children)
        return copy
    }
}

@Suite("Order damping (TASK-74)")
struct StableOrderTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func rows(_ pairs: [(String, Int)]) -> [Sample] {
        pairs.map { Sample(id: $0.0, value: $0.1) }
    }

    @Test("The first settle adopts the ranking whole")
    func firstSettleAdopts() {
        var order = StableOrder<Sample>()
        let out = order.settle(ranked(rows([("a", 1), ("b", 9), ("c", 5)])), now: start)
        #expect(out.map(\.id) == ["b", "c", "a"])
    }

    /// The point of the whole exercise: within the settle interval, a row does not
    /// move out from under the pointer.
    @Test("A changed ranking does not move rows before the settle interval")
    func orderIsHeld() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9), ("c", 5)])), now: start)
        let out = order.settle(
            ranked(rows([("a", 99), ("b", 2), ("c", 5)])),
            now: start.addingTimeInterval(2))
        #expect(out.map(\.id) == ["b", "c", "a"])
    }

    /// The rule that keeps this honest. Holding the order must never hold a number:
    /// a stale reading shown as a current one is what FR-002 and FR-032 forbid.
    @Test("Held order still shows the newest values")
    func valuesStayLive() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9)])), now: start)
        let out = order.settle(
            ranked(rows([("a", 99), ("b", 2)])), now: start.addingTimeInterval(2))
        #expect(out.map(\.id) == ["b", "a"])
        #expect(out.map(\.value) == [2, 99])
    }

    @Test("The ranking is adopted once the settle interval has passed")
    func adoptsAfterInterval() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9), ("c", 5)])), now: start)
        let out = order.settle(
            ranked(rows([("a", 99), ("b", 2), ("c", 5)])),
            now: start.addingTimeInterval(OrderStability.settleInterval))
        #expect(out.map(\.id) == ["a", "c", "b"])
    }

    /// Damping applies to data churn, never to user intent (TASK-74's constraint).
    @Test("A user's sort or search re-ranks immediately")
    func userIntentReRanksAtOnce() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9), ("c", 5)])), now: start)
        order.reset()
        let out = order.settle(
            ranked(rows([("a", 99), ("b", 2), ("c", 5)])),
            now: start.addingTimeInterval(0.1))
        #expect(out.map(\.id) == ["a", "c", "b"])
    }

    /// A process that ended must leave the screen at once — a settled order is not a
    /// licence to show something that is no longer running.
    @Test("Departures are removed at once and survivors keep their order")
    func departuresLeaveImmediately() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9), ("c", 5)])), now: start)
        let out = order.settle(
            ranked(rows([("a", 1), ("c", 5)])), now: start.addingTimeInterval(2))
        #expect(out.map(\.id) == ["c", "a"])
    }

    /// An arrival is an insertion, not a reorder: it lands where the ranking puts it
    /// and the rows already on screen keep their relative order.
    @Test("Arrivals are inserted at their ranked position")
    func arrivalsLandInRank() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9), ("c", 5)])), now: start)
        // Held order is b, c, a. New rows: d outranks everything, e sits between c
        // and a. Meanwhile a and b swap in the ranking, which must not show yet.
        let out = order.settle(
            ranked(rows([("a", 8), ("b", 2), ("c", 5), ("d", 100), ("e", 3)])),
            now: start.addingTimeInterval(2))
        #expect(out.map(\.id) == ["d", "b", "c", "e", "a"])
    }

    @Test("Several arrivals keep their ranked order relative to each other")
    func severalArrivals() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1)])), now: start)
        let out = order.settle(
            ranked(rows([("a", 1), ("x", 50), ("y", 70), ("z", 60)])),
            now: start.addingTimeInterval(2))
        #expect(out.map(\.id) == ["y", "z", "x", "a"])
    }

    /// An expanded family's members jitter for the same reason its aggregate does.
    @Test("Children are damped too, and adopt when the parent does")
    func childrenAreDamped() {
        var order = StableOrder<Sample>()
        let first = [Sample(id: "p", value: 10, children: rows([("c1", 1), ("c2", 9)]))]
        _ = order.settle(ranked(first), now: start)

        let second = [Sample(id: "p", value: 10, children: rows([("c1", 99), ("c2", 2)]))]
        let held = order.settle(ranked(second), now: start.addingTimeInterval(2))
        #expect(held[0].children.map(\.id) == ["c2", "c1"])
        #expect(held[0].children.map(\.value) == [2, 99])

        let settled = order.settle(
            ranked(second), now: start.addingTimeInterval(OrderStability.settleInterval))
        #expect(settled[0].children.map(\.id) == ["c1", "c2"])
    }

    /// Row identity is the row's own id and nothing else. Selection and expansion are
    /// keyed on it, so encoding position would break both across every sample —
    /// TASK-67 rejected exactly that.
    @Test("Identity never carries position")
    func identityIsPositionFree() {
        var order = StableOrder<Sample>()
        let input = ranked(rows([("a", 1), ("b", 9), ("c", 5)]))
        let held = order.settle(input, now: start)
        let reordered = order.settle(
            ranked(rows([("a", 99), ("b", 2), ("c", 5)])),
            now: start.addingTimeInterval(OrderStability.settleInterval))
        #expect(Set(held.map(\.id)) == Set(reordered.map(\.id)))
        #expect(reordered.first(where: { $0.id == "a" })?.id == "a")
    }

    /// A ranking that has not changed must not restart the clock, or a table that is
    /// quiet for a while would then hold its next real change for a further interval.
    @Test("An unchanged ranking does not restart the settle clock")
    func unchangedRankingDoesNotRestartTheClock() {
        var order = StableOrder<Sample>()
        _ = order.settle(ranked(rows([("a", 1), ("b", 9)])), now: start)
        // Same order, later: no reorder happened, so the clock still runs from `start`.
        _ = order.settle(
            ranked(rows([("a", 2), ("b", 9)])),
            now: start.addingTimeInterval(OrderStability.settleInterval * 2))
        let out = order.settle(
            ranked(rows([("a", 99), ("b", 9)])),
            now: start.addingTimeInterval(OrderStability.settleInterval * 2 + 0.1))
        #expect(out.map(\.id) == ["a", "b"])
    }

    @Test("The rule is stated for a user, with the interval it actually uses")
    func explanationStatesTheRule() {
        #expect(OrderStability.explanation.contains("\(Int(OrderStability.settleInterval)) seconds"))
        #expect(OrderStability.explanation.contains("numbers update every sample"))
    }
}
