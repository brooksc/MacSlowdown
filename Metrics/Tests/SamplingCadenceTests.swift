import Foundation
import Testing

@testable import Metrics

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

@Suite("Adaptive sampling cadence")
struct SamplingCadenceTests {
    @Test("Steady state samples at the normal interval")
    func steadyStateIsNormal() {
        let controller = CadenceController()
        var state = CadenceController.State()
        let cadence = controller.cadence(
            at: at(0), incidentOpen: false, conditionBreaching: false, state: &state)

        #expect(cadence.mode == .normal)
        #expect(cadence.interval == .seconds(2))
    }

    /// FR-031: resolution rises on a *suspected* incident, not only a confirmed
    /// one. Waiting for the trigger would miss the evidence leading up to it.
    @Test("A breaching condition raises resolution before an incident exists")
    func preTriggerElevates() {
        let controller = CadenceController()
        var state = CadenceController.State()
        let cadence = controller.cadence(
            at: at(0), incidentOpen: false, conditionBreaching: true, state: &state)

        #expect(cadence.mode == .investigation)
        #expect(cadence.interval == .seconds(1))
    }

    @Test("An open incident keeps resolution raised")
    func openIncidentElevates() {
        let controller = CadenceController()
        var state = CadenceController.State()
        let cadence = controller.cadence(
            at: at(0), incidentOpen: true, conditionBreaching: false, state: &state)
        #expect(cadence.mode == .investigation)
    }

    @Test("Resolution lingers after recovery, then returns to normal")
    func lingersThenReturns() {
        let controller = CadenceController(investigationLinger: .seconds(60))
        var state = CadenceController.State()

        _ = controller.cadence(at: at(0), incidentOpen: true,
                               conditionBreaching: false, state: &state)

        // Conditions cleared, but the recovery window is still worth capturing.
        let during = controller.cadence(at: at(30), incidentOpen: false,
                                        conditionBreaching: false, state: &state)
        #expect(during.mode == .investigation)
        #expect(during.reason.contains("recovery"))

        let after = controller.cadence(at: at(90), incidentOpen: false,
                                       conditionBreaching: false, state: &state)
        #expect(after.mode == .normal)
    }

    /// FR-031: a cadence transition does not lose samples. The controller only
    /// ever chooses the *next* interval, so every observation offered to it is
    /// counted, whichever side of a transition it falls on.
    @Test("No sample is lost across transitions")
    func noSamplesLost() {
        let controller = CadenceController(investigationLinger: .seconds(30))
        var state = CadenceController.State()

        // Quiet, then a breach, then recovery, then quiet again.
        var offered = 0
        for second in stride(from: 0.0, through: 200, by: 5) {
            let breaching = (60...120).contains(Int(second))
            _ = controller.cadence(at: at(second), incidentOpen: false,
                                   conditionBreaching: breaching, state: &state)
            offered += 1
        }

        #expect(state.samplesTaken == offered,
                "\(offered - state.samplesTaken) samples were dropped across transitions")
        #expect(state.modeChanges >= 2, "expected at least one rise and one fall")
    }

    @Test("Mode changes only when the situation actually changes")
    func noModeChurn() {
        let controller = CadenceController()
        var state = CadenceController.State()
        for second in stride(from: 0.0, through: 100, by: 5) {
            _ = controller.cadence(at: at(second), incidentOpen: false,
                                   conditionBreaching: false, state: &state)
        }
        #expect(state.modeChanges == 0, "steady state should not change mode")
    }

    /// FR-031: normal mode is no faster than necessary, which is what keeps the
    /// FR-030 idle budget met.
    @Test("Normal is slower than investigation")
    func normalIsSlower() {
        let controller = CadenceController()
        #expect(controller.normalInterval > controller.investigationInterval)
    }

    /// FR-031: the user can inspect the current cadence.
    @Test("The cadence describes itself, including why")
    func cadenceIsInspectable() {
        let controller = CadenceController()
        var state = CadenceController.State()

        let normal = controller.cadence(at: at(0), incidentOpen: false,
                                        conditionBreaching: false, state: &state)
        #expect(normal.description.contains("every 2 s"))
        #expect(normal.description.contains("normal"))
        #expect(!normal.reason.isEmpty)

        let elevated = controller.cadence(at: at(10), incidentOpen: true,
                                          conditionBreaching: false, state: &state)
        #expect(elevated.description.contains("every 1 s"))
        #expect(elevated.reason.contains("incident is open"))
    }

    @Test("A pre-trigger breach explains itself distinctly from an open incident")
    func reasonsAreDistinct() {
        let controller = CadenceController()
        var state = CadenceController.State()

        let pending = controller.cadence(at: at(0), incidentOpen: false,
                                         conditionBreaching: true, state: &state)
        #expect(pending.reason.contains("not lasted long enough"))

        var other = CadenceController.State()
        let open = controller.cadence(at: at(0), incidentOpen: true,
                                      conditionBreaching: true, state: &other)
        #expect(open.reason.contains("incident is open"))
    }
}
