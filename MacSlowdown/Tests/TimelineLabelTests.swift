import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// The incident timeline's axis labels (TASK-65.24 #5).
///
/// Found by rendering incident detail at 820 pt, not by a test: "conditions
/// cleared" and "closed" are a minute apart on a fourteen-minute axis and were
/// drawn on top of each other, into an unreadable smear at exactly the point the
/// screen was saying when the machine recovered. These assertions are what stops
/// it coming back silently.
@MainActor
@Suite("Incident timeline axis labels")
struct TimelineLabelTests {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    /// The incident from the render that found the defect: opened three minutes
    /// in, conditions cleared at nine, closed at ten.
    private func crowdedIncident() -> Incident {
        Incident.preview(
            beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
            recoveryStartedAt: origin.addingTimeInterval(540),
            closedAt: origin.addingTimeInterval(600),
            conditions: [.cpuSaturation], severity: .high,
            peakCPUBusyFraction: 0.94, peakMemoryPressure: .warning)
    }

    /// Two labels overlap when they share a row and their extents cross.
    private func overlaps(
        _ placements: [IncidentTimeline.MarkerPlacement]
    ) -> [(String, String)] {
        var found: [(String, String)] = []
        for (index, first) in placements.enumerated() {
            for second in placements.dropFirst(index + 1) where first.row == second.row {
                let firstEnd = first.x + CGFloat(first.marker.label.count) * 5.5
                let secondEnd = second.x + CGFloat(second.marker.label.count) * 5.5
                if first.x < secondEnd && second.x < firstEnd {
                    found.append((first.marker.label, second.marker.label))
                }
            }
        }
        return found
    }

    @Test("No two labels overstrike at the width the defect was seen at")
    func noOverlapAt820() {
        let timeline = IncidentTimeline.build(incident: crowdedIncident())
        #expect(overlaps(timeline.labelPlacements(width: 820)).isEmpty)
    }

    @Test("Every recorded moment keeps a label — crowding is never resolved by dropping one")
    func nothingIsDropped() {
        let timeline = IncidentTimeline.build(incident: crowdedIncident())
        for width in [400.0, 480.0, 620.0, 820.0, 1200.0] {
            let placements = timeline.labelPlacements(width: width)
            #expect(placements.count == timeline.markers.count)
            #expect(placements.map(\.marker.label) == timeline.markers.map(\.label))
        }
    }

    @Test("Labels stay on the axis's first row when there is room for them")
    func oneRowWhenUncrowded() {
        // An incident still open, so only "first breach" and "opened" are marked,
        // ten minutes apart on a forty-minute axis. A second row here would put a
        // label 12 pt from its notch for no reason.
        let spacious = Incident.preview(
            beganAt: origin, triggeredAt: origin.addingTimeInterval(600),
            conditions: [.cpuSaturation], severity: .moderate,
            peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
        let timeline = IncidentTimeline.build(
            incident: spacious, now: origin.addingTimeInterval(2400))
        #expect(timeline.labelPlacements(width: 820).allSatisfy { $0.row == 0 })
    }

    @Test("Labels stay inside the axis at every width")
    func labelsStayInside() {
        let timeline = IncidentTimeline.build(incident: crowdedIncident())
        for width in [400.0, 480.0, 820.0] {
            for placement in timeline.labelPlacements(width: width) {
                #expect(placement.x >= 0)
                #expect(placement.x <= width)
                #expect(placement.row == 0 || placement.row == 1)
            }
        }
    }
}
