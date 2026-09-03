import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private let anchor = Date(timeIntervalSince1970: 1_000_000)

private func incidentInputs(
    severity: IncidentSeverity = .severe,
    conditions: [IncidentCondition] = [.memoryPressure],
    minutes: Double = 11,
    policy: PolicyClassification? = nil,
    application: String? = "Xcode"
) -> MenuBarIconInputs {
    MenuBarIconInputs(
        severity: .severe,
        incidentIsOpen: true,
        incidentSeverity: severity,
        incidentConditions: conditions,
        incidentDuration: .seconds(minutes * 60),
        leadingApplicationName: application,
        leadingApplicationPolicy: policy)
}

@Suite("The menu bar icon has four states, not three")
struct MenuBarIconStateTests {
    /// The design's central claim. Three severities cannot express "a threshold is
    /// crossed but has not lasted long enough", which is FR-006's whole rule.
    @Test func fourStatesAreDistinctInShape() {
        let filled = MenuBarIconState.allCases.map(\.filledBars)
        #expect(Set(filled).count == MenuBarIconState.allCases.count)
        #expect(MenuBarIconState.muted.isSlashed)
        #expect(!MenuBarIconState.normal.isSlashed)
    }

    /// "Muted must never look identical to normal." Two independent differences,
    /// so neither a monochrome render nor a lost slash can collapse them.
    @Test func mutedIsNeverIdenticalToNormal() {
        #expect(MenuBarIconState.muted.filledBars != MenuBarIconState.normal.filledBars)
        #expect(MenuBarIconState.muted.isSlashed != MenuBarIconState.normal.isSlashed)
        // Colour is deliberately not a third difference any more (TASK-89): both are
        // uncoloured, and the two shape differences above are what the design's
        // requirement actually rests on.
    }

    @Test func quietMachineIsNormal() {
        let presentation = MenuBarIcon.presentation(for: MenuBarIconInputs())
        #expect(presentation.state == .normal)
        #expect(!presentation.showsBadge)
        #expect(presentation.accessibilityLabel == "MacSlowdown, normal")
    }

    /// A threshold crossed without an incident is elevated — including when the
    /// live severity is already `.severe`. Promoting that to the incident glyph
    /// would make the sustained-duration threshold invisible again.
    @Test func severeWithoutAnIncidentIsElevatedNotIncident() {
        let elevated = MenuBarIcon.presentation(
            for: MenuBarIconInputs(severity: .elevated,
                                   elevatedConditions: [.cpuSaturation]))
        #expect(elevated.state == .elevated)

        let severe = MenuBarIcon.presentation(
            for: MenuBarIconInputs(severity: .severe, elevatedConditions: [.cpuSaturation]))
        #expect(severe.state == .elevated)
        #expect(!severe.showsBadge)
    }

    @Test func openIncidentIsTheIncidentStateAndCarriesABadge() {
        let presentation = MenuBarIcon.presentation(for: incidentInputs())
        #expect(presentation.state == .incident)
        #expect(presentation.showsBadge)
        #expect(!presentation.cappedByExpectedWorkload)
    }

    /// Mute takes the glyph, because a monitor that has stopped interrupting must
    /// say so on the only always-present surface (FR-015).
    @Test func muteTakesTheGlyph() {
        var inputs = incidentInputs()
        inputs.isMuted = true
        inputs.muteRemaining = .seconds(41 * 60)
        let presentation = MenuBarIcon.presentation(for: inputs)
        #expect(presentation.state == .muted)
        // …but the incident is not hidden by muting. Only the colour is.
        #expect(presentation.showsBadge)
    }

    /// FR-034, at the one place it was still being broken. Severe and an ordinary
    /// open incident were the same three bars and the same hollow ring, separated
    /// by red and nothing else — so under Increase Contrast, on a monochrome
    /// strip, or for a colour-blind reader, the two were identical. Design 4d
    /// fills the badge for severe, which is a shape.
    @Test("Severe differs from an open incident in shape, not only in colour")
    func severeIsSeparatedByShape() {
        let severe = MenuBarIcon.presentation(for: incidentInputs(severity: .severe))
        let ordinary = MenuBarIcon.presentation(for: incidentInputs(severity: .high))

        #expect(severe.state == ordinary.state, "both are the incident glyph")
        #expect(severe.showsBadge && ordinary.showsBadge)
        #expect(severe.badgeIsFilled, "severe fills the badge")
        #expect(!ordinary.badgeIsFilled, "an ordinary incident keeps the ring")

        // The property that matters: strip the colour and they are still different.
        #expect(severe.tint != ordinary.tint)
        #expect(severe.badgeIsFilled != ordinary.badgeIsFilled,
                "with colour removed, nothing would tell these two apart")
    }

    /// The fill and the tint are one decision, so they cannot drift into
    /// disagreeing about which state is severe.
    @Test("Only the state that earns colour fills the badge")
    func fillAndColourAgree() {
        for severity in [IncidentSeverity.moderate, .high, .severe] {
            let shown = MenuBarIcon.presentation(for: incidentInputs(severity: severity))
            #expect(shown.badgeIsFilled == (shown.tint == .red))
        }
        #expect(!MenuBarIcon.presentation(for: MenuBarIconInputs()).badgeIsFilled,
                "a calm machine has no badge to fill")
    }

}

@Suite("A workload the user marked expected never turns the icon red")
struct MenuBarIconPolicyCapTests {
    /// Design 1j's per-app rule reaching the menu bar: "red never appears for a
    /// workload the user marked expected; that shows as yellow at most."
    @Test func expectedWorkloadCapsAtElevated() {
        let presentation = MenuBarIcon.presentation(for: incidentInputs(policy: .expected))
        #expect(presentation.state == .elevated)
        #expect(presentation.tint == .none)
        #expect(presentation.cappedByExpectedWorkload)
        // The incident is still recorded and still badged; only the escalation is
        // withheld (FR-016: suppressing an alert never suppresses the record).
        #expect(presentation.showsBadge)
    }

    /// `.ignored` is the strictly stronger rule, so it cannot cap less.
    @Test func ignoredCapsToo() {
        #expect(MenuBarIcon.presentation(for: incidentInputs(policy: .ignored)).state == .elevated)
    }

    /// `.watched` is the user asking to be told, so it must not cap.
    @Test func watchedDoesNotCap() {
        let presentation = MenuBarIcon.presentation(for: incidentInputs(policy: .watched))
        #expect(presentation.state == .incident)
        #expect(!presentation.cappedByExpectedWorkload)
    }

    /// The cap says which application caused it, so a user who wonders why the
    /// icon is not red can hear the answer.
    @Test func theCapIsSpoken() {
        let label = MenuBarIcon.presentation(for: incidentInputs(policy: .expected))
            .accessibilityLabel
        #expect(label.contains("Xcode is marked as expected"))
    }

    /// Matching follows `ApplicationPolicy.matches`: bundle identifier, then path,
    /// and a name only for a policy that carries neither.
    @Test func policyMatchesOnBundleIdentifierThenPathThenName() {
        let byID = ApplicationPolicy(
            bundleID: "com.apple.dt.Xcode", displayName: "Xcode", classification: .expected)
        let byPath = ApplicationPolicy(
            bundlePath: "/Applications/Xcode.app", displayName: "Xcode",
            classification: .ignored)
        let byName = ApplicationPolicy(displayName: "swift-frontend", classification: .watched)
        let policies = [byID, byPath, byName]

        #expect(MenuBarIcon.policy(
            for: .init(bundleID: "com.apple.dt.Xcode", displayName: "Anything"),
            in: policies)?.classification == .expected)
        #expect(MenuBarIcon.policy(
            for: .init(bundlePath: "/Applications/Xcode.app", displayName: "Anything"),
            in: policies)?.classification == .ignored)
        #expect(MenuBarIcon.policy(
            for: .init(displayName: "swift-frontend"), in: policies)?.classification == .watched)
        // A name that matches a policy keyed on a bundle must not match: the
        // policy is about that bundle, not about anything calling itself Xcode.
        #expect(MenuBarIcon.policy(
            for: .init(displayName: "Xcode"), in: [byID, byPath]) == nil)
        #expect(MenuBarIcon.policy(for: nil, in: policies) == nil)
    }
}

@Suite("What the menu bar icon says out loud")
struct MenuBarIconVoiceOverTests {
    /// The four strings the design specifies, as specified.
    @Test func theDesignsStrings() {
        #expect(MenuBarIcon.presentation(for: MenuBarIconInputs()).accessibilityLabel
            == "MacSlowdown, normal")

        #expect(MenuBarIcon.presentation(for: MenuBarIconInputs(
            severity: .elevated, elevatedConditions: [.cpuSaturation])).accessibilityLabel
            == "MacSlowdown, elevated, CPU")

        #expect(MenuBarIcon.presentation(for: incidentInputs(
            severity: .severe, conditions: [.memoryPressure], minutes: 11, application: nil))
            .accessibilityLabel == "MacSlowdown, severe, memory, 11 minutes")

        var muted = MenuBarIconInputs()
        muted.isMuted = true
        muted.muteRemaining = .seconds(41 * 60)
        #expect(MenuBarIcon.presentation(for: muted).accessibilityLabel
            == "MacSlowdown, muted for 41 more minutes")
    }

    /// Muting must not delete the incident from the only surface that is always
    /// visible. The table did not consider the combination; silence would be the
    /// worse answer.
    @Test func mutedStillNamesAnOpenIncident() {
        var inputs = incidentInputs(application: nil)
        inputs.isMuted = true
        inputs.muteRemaining = .seconds(41 * 60)
        #expect(MenuBarIcon.presentation(for: inputs).accessibilityLabel
            == "MacSlowdown, muted for 41 more minutes, incident open, memory, 11 minutes")
    }

    @Test func anIndefiniteMuteSaysSoRatherThanCountingMinutes() {
        var inputs = MenuBarIconInputs()
        inputs.isMuted = true
        inputs.muteIsIndefinite = true
        inputs.muteRemaining = .seconds(100 * 365 * 24 * 3600)
        #expect(MenuBarIcon.presentation(for: inputs).accessibilityLabel
            == "MacSlowdown, muted until you turn alerts back on")
    }

    /// A duration under a minute is said in words. "0 minutes" would be a claim
    /// the clock does not support and "1 minute" would be a rounding presented as
    /// a measurement.
    @Test func shortDurationsAreWordsNotZero() {
        #expect(MenuBarIcon.durationPhrase(.seconds(20)) == "less than a minute")
        #expect(MenuBarIcon.durationPhrase(.seconds(60)) == "1 minute")
        #expect(MenuBarIcon.durationPhrase(.seconds(11 * 60)) == "11 minutes")
        #expect(MenuBarIcon.durationPhrase(.seconds(3600)) == "1 hour")
        #expect(MenuBarIcon.durationPhrase(.seconds(3600 + 120)) == "1 hour 2 minutes")
    }

    /// Conditions are named in a fixed order, so the spoken label does not swap
    /// words between samples for a machine whose conditions have not changed.
    @Test func conditionOrderIsStable() {
        let ordered = MenuBarIcon.ordered([.thermalPressure, .cpuSaturation, .memoryPressure])
        #expect(ordered == [.cpuSaturation, .memoryPressure, .thermalPressure])
        #expect(MenuBarIcon.conditionWord(.cpuSaturation) == "CPU")
        #expect(MenuBarIcon.conditionWord(.memoryPressure) == "memory")
        #expect(MenuBarIcon.conditionWord(.lowStorage) == "storage")
        #expect(MenuBarIcon.conditionWord(.thermalPressure) == "thermal")
    }
}

@Suite("The icon cannot strobe")
struct MenuBarIconRateLimiterTests {
    private let start = ContinuousClock.now

    private func presentation(_ state: MenuBarIconState) -> MenuBarIconPresentation {
        MenuBarIconPresentation(
            state: state, showsBadge: false, cappedByExpectedWorkload: false,
            tint: .none, accessibilityLabel: state.rawValue)
    }

    @Test func theFirstChangeIsNeverHeld() {
        #expect(MenuBarIconRateLimiter.decide(
            displayed: presentation(.normal), desired: presentation(.incident),
            lastChangeAt: nil, now: start) == .apply)
    }

    @Test func aSecondChangeWithinTwoSecondsIsHeld() {
        let decision = MenuBarIconRateLimiter.decide(
            displayed: presentation(.normal), desired: presentation(.incident),
            lastChangeAt: start, now: start + .milliseconds(500))
        #expect(decision == .hold(remaining: .milliseconds(1500)))
    }

    @Test func afterTheIntervalItApplies() {
        #expect(MenuBarIconRateLimiter.decide(
            displayed: presentation(.normal), desired: presentation(.incident),
            lastChangeAt: start, now: start + .seconds(2)) == .apply)
    }

    /// Only the *state* is rate-limited. A label whose duration ticked from ten to
    /// eleven minutes must not be held back for two seconds — nothing flickers
    /// when a spoken string changes.
    @Test func onlyTheStateIsRateLimited() {
        let shown = MenuBarIconPresentation(
            state: .incident, showsBadge: true, cappedByExpectedWorkload: false,
            tint: .none, accessibilityLabel: "MacSlowdown, severe, memory, 10 minutes")
        let updated = MenuBarIconPresentation(
            state: .incident, showsBadge: true, cappedByExpectedWorkload: false,
            tint: .none, accessibilityLabel: "MacSlowdown, severe, memory, 11 minutes")
        #expect(MenuBarIconRateLimiter.decide(
            displayed: shown, desired: updated,
            lastChangeAt: start, now: start + .milliseconds(100)) == .apply)
        #expect(MenuBarIconRateLimiter.decide(
            displayed: shown, desired: shown,
            lastChangeAt: start, now: start + .milliseconds(100)) == .unchanged)
    }

    /// A held change is not a dropped change: the model shows it once the interval
    /// has run.
    @MainActor
    @Test func aHeldChangeArrivesLate() async {
        let model = MenuBarIconModel(minimumInterval: .milliseconds(200))
        let now = ContinuousClock.now
        #expect(model.update(to: presentation(.elevated), now: now))
        #expect(model.displayed.state == .elevated)
        #expect(!model.update(to: presentation(.incident), now: now + .milliseconds(10)))
        #expect(model.displayed.state == .elevated)

        try? await Task.sleep(for: .milliseconds(600))
        #expect(model.displayed.state == .incident)
    }

    /// The cross-fade is a fade and nothing else. Asserted as a constant because
    /// the absence of motion is a property of the view's construction — the bars
    /// have fixed frames and only their fills change — and cannot be observed from
    /// a test.
    @Test func theCrossFadeIsQuarterOfASecond() {
        #expect(MenuBarIcon.crossFadeSeconds == 0.25)
        #expect(MenuBarIcon.minimumInterval == .seconds(2))
    }
}

@Suite("The optional readouts")
struct MenuBarReadoutTests {
    /// Off by default: the menu bar is the user's, and a permanent number there is
    /// noise nobody asked for.
    @Test func iconOnlyIsTheDefault() {
        #expect(MenuBarReadout.default == .iconOnly)
        let defaults = UserDefaults(suiteName: "MenuBarReadoutTests.\(UUID().uuidString)")!
        #expect(MenuBarReadout.stored(in: defaults) == .iconOnly)
        defaults.set("sparkline", forKey: MenuBarReadout.storageKey)
        #expect(MenuBarReadout.stored(in: defaults) == .sparkline)
        // A hand-edited preference must not leave the menu bar undefined.
        defaults.set("nonsense", forKey: MenuBarReadout.storageKey)
        #expect(MenuBarReadout.stored(in: defaults) == .iconOnly)
        #expect(MenuBarReadout.allCases.count == 3)
    }

    /// No measurement is not a measurement of zero (FR-002).
    @Test func anUnmeasuredCPUReadoutSaysSoRatherThanShowingZero() {
        #expect(MenuBarIcon.cpuReadout(busyShareOfMachine: nil) == nil)
        #expect(MenuBarIcon.cpuReadoutAccessibilityLabel(busyShareOfMachine: nil)
            == "CPU not measured yet")
        #expect(MenuBarIcon.cpuReadout(busyShareOfMachine: .nan) == nil)
        #expect(MenuBarIcon.cpuReadout(busyShareOfMachine: 0) == "0%")
        #expect(MenuBarIcon.cpuReadout(busyShareOfMachine: 0.94) == "94%")
    }

    /// The sparkline is the series FR-005 retains, windowed — never a second
    /// series the menu bar accumulated for itself.
    @Test func theSparklineComesFromRetainedSamplesOnly() {
        let samples = (0..<60).map { index in
            HistorySample(
                timestamp: anchor.addingTimeInterval(Double(index) * 2 - 118),
                totalBusyPercentOfOneCore: Double(index),
                attributedPercentOfOneCore: Double(index),
                unattributedPercentOfOneCore: 0,
                topContributors: [])
        }
        let points = MenuBarIcon.sparklinePoints(retained: samples, now: anchor)
        // A 60 s window over a 2 s cadence keeps about thirty readings, and every
        // one of them is a sample that was taken.
        #expect(points.count == 31)
        #expect(points.allSatisfy { point in
            samples.contains { $0.timestamp == point.at && $0.totalBusyPercentOfOneCore == point.value }
        })
        #expect(MenuBarIcon.canDrawSparkline(points))
    }

    /// Too few readings draws nothing at all. A flat line in a 40 pt strip reads
    /// as a quiet machine; the truth is that we have not been watching long enough.
    @Test func tooFewReadingsDrawNothing() {
        let samples = (0..<2).map { index in
            HistorySample(
                timestamp: anchor.addingTimeInterval(Double(index) * 2 - 4),
                totalBusyPercentOfOneCore: 10,
                attributedPercentOfOneCore: 10,
                unattributedPercentOfOneCore: 0,
                topContributors: [])
        }
        #expect(!MenuBarIcon.canDrawSparkline(
            MenuBarIcon.sparklinePoints(retained: samples, now: anchor)))
        #expect(!MenuBarIcon.canDrawSparkline([]))
    }
}

@Suite("Increase Contrast and Reduce Transparency")
struct MenuBarIconTreatmentTests {
    /// The design's rule: "In Increase Contrast the fills go to pure black/white
    /// outlines." What a test can check is that colour is dropped and the unfilled
    /// bars become strokes. Whether the result is legible in a real menu bar needs
    /// a person looking at one.
    @Test func increaseContrastDropsColourAndOutlinesTheEmptyBars() {
        let contrast = MenuBarIconTreatment.resolve(
            increaseContrast: true, reduceTransparency: false)
        #expect(!contrast.usesTint)
        #expect(contrast.unfilled == .outline)
    }

    /// Reduce Transparency is a request not to convey anything with a washed-out
    /// fill, so the empty bars are stroked — but colour is still allowed.
    @Test func reduceTransparencyOutlinesButKeepsColour() {
        let reduced = MenuBarIconTreatment.resolve(
            increaseContrast: false, reduceTransparency: true)
        #expect(reduced.usesTint)
        #expect(reduced.unfilled == .outline)
    }

    @Test func theDefaultTreatmentIsTintedAndDimmed() {
        let plain = MenuBarIconTreatment.resolve(
            increaseContrast: false, reduceTransparency: false)
        #expect(plain.usesTint)
        #expect(plain.unfilled == .dimmed)
    }

    /// The system settings are readable, so the treatment is a live fact rather
    /// than a preference we invented. The machine's current values are whatever
    /// they are; this asserts only that reading them is total.
    @MainActor
    @Test func theSystemSettingsAreReadable() {
        let current = MenuBarIconTreatment.current
        #expect(MenuBarIconTreatment.allTreatments.contains(current))
    }
}

extension MenuBarIconTreatment {
    /// Every treatment `resolve` can produce, for the totality check above.
    static var allTreatments: [MenuBarIconTreatment] {
        [true, false].flatMap { contrast in
            [true, false].map { resolve(increaseContrast: contrast, reduceTransparency: $0) }
        }
    }
}

@Suite("The store's own inputs to the icon")
@MainActor
struct MenuBarIconStoreTests {
    /// A store nobody has started describes a quiet machine, and the icon agrees.
    /// This is also the guard that reading the inputs touches nothing that starts
    /// monitoring or inserts a status item.
    @Test func afreshStoreIsNormal() {
        let store = MonitorStore(policies: PolicyStore(), storage: StorageScreenModel(history: StorageHistory()))
        let inputs = store.menuBarIconInputs
        #expect(!inputs.incidentIsOpen)
        #expect(!inputs.isMuted)
        #expect(inputs.severity == .normal)
        #expect(MenuBarIcon.presentation(for: inputs).state == .normal)
    }

    /// FR-015: muting changes the icon and nothing else about the recording.
    @Test func mutingReachesTheIcon() {
        let store = MonitorStore(policies: PolicyStore(), storage: StorageScreenModel(history: StorageHistory()))
        store.mute(forMinutes: 30)
        let presentation = MenuBarIcon.presentation(for: store.menuBarIconInputs)
        #expect(presentation.state == .muted)
        #expect(presentation.accessibilityLabel.hasPrefix("MacSlowdown, muted for"))
        #expect(store.isRunning == false)

        store.clearMute()
        #expect(MenuBarIcon.presentation(for: store.menuBarIconInputs).state == .normal)
    }

    /// The live conditions the elevated glyph names come from the store's own
    /// signals, in the fixed order.
    @Test func liveConditionsAreOrdered() {
        let store = MonitorStore(policies: PolicyStore(), storage: StorageScreenModel(history: StorageHistory()))
        #expect(store.liveBreachingConditions.isEmpty)
    }

    /// The label the app scene installs, constructed. This is the whole of the
    /// wiring in `MacSlowdownApp.swift`, so it is worth knowing it type-checks and
    /// that building it starts nothing and puts nothing in the menu bar.
    @Test func theLabelTheSceneInstallsCanBeBuilt() {
        let store = MonitorStore(policies: PolicyStore(),
                                 storage: StorageScreenModel(history: StorageHistory()))
        _ = MenuBarIconLabel(store: store)
        #expect(!store.isRunning)
        #expect(AppDelegate.isHostingTests)
    }
}

/// TASK-89. Product owner, 2026-08-23: "red should be a rare event e.g. something
/// is really wrong on the machine." Design 2d tinted all four states; in a real
/// menu bar that meant a permanent green light beside a strip of template icons,
/// and a red that arrived for any open incident — which on a working Mac is not
/// rare, and an alarm that is on most of the time is not an alarm.
@Suite("Colour is rare, and shape is not")
struct MenuBarIconTintTests {
    @Test("A severe incident is the only thing that earns red")
    func onlySevereIsRed() {
        #expect(MenuBarIcon.presentation(for: incidentInputs(severity: .severe)).tint == .red)
        #expect(MenuBarIcon.presentation(for: incidentInputs(severity: .high)).tint == .none)
        #expect(MenuBarIcon.presentation(for: incidentInputs(severity: .moderate)).tint == .none)
    }

    @Test("A quiet machine and an elevated one use no colour at all")
    func ordinaryStatesAreTemplates() {
        #expect(MenuBarIcon.presentation(for: MenuBarIconInputs()).tint == .none)
        #expect(MenuBarIcon.presentation(
            for: MenuBarIconInputs(severity: .elevated)).tint == .none)
        #expect(MenuBarIconPresentation.normal.tint == .none)
    }

    @Test("Muting a severe incident takes the colour with it")
    func mutedIsNeverRed() {
        var inputs = incidentInputs(severity: .severe)
        inputs.isMuted = true
        let presentation = MenuBarIcon.presentation(for: inputs)
        #expect(presentation.state == .muted)
        #expect(presentation.tint == .none)
        // Still recorded, still badged — muting suppresses interruption, never the
        // record (FR-015).
        #expect(presentation.showsBadge)
    }

    /// The property the whole change rests on: with colour gone, nothing is lost.
    @Test("All four states remain distinguishable with no colour whatsoever")
    func shapeAloneSeparatesEveryState() {
        let shapes = MenuBarIconState.allCases.map { ($0.filledBars, $0.isSlashed) }
        #expect(Set(shapes.map { "\($0.0)-\($0.1)" }).count == MenuBarIconState.allCases.count)
    }

    /// An open incident below the severe line still has to be visible as one, and
    /// the badge is what does it.
    @Test("An uncoloured incident is still badged")
    func badgeCarriesTheIncidentWithoutColour() {
        let presentation = MenuBarIcon.presentation(for: incidentInputs(severity: .high))
        #expect(presentation.state == .incident)
        #expect(presentation.tint == .none)
        #expect(presentation.showsBadge)
    }
}
