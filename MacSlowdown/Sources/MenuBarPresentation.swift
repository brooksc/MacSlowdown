import Foundation
import Metrics

/// The menu bar icon's four states (design 2d).
///
/// Four, not three, because our `Severity` is a description of the machine right
/// now and the icon has to describe our *judgement* of it. FR-006's rule is that a
/// slowdown is sustained rather than transient; without a distinct elevated state
/// the icon steps straight from "fine" to "incident open" and the duration
/// threshold — the thing that makes the judgement honest — is invisible to the
/// only surface that is always on screen.
///
/// Every case is distinguished by **shape** first: the number of filled bars, and
/// for muted a slash through them. Colour is carried alongside as reinforcement
/// only, because a 16 pt glyph in a translucent strip cannot carry meaning in hue
/// (FR-034), and because macOS may render a menu bar label as a monochrome
/// template regardless of what we ask for.
enum MenuBarIconState: String, CaseIterable, Equatable, Sendable {
    case normal
    case elevated
    case incident
    case muted

    /// How many of the three bars are filled. Muted fills none and is slashed, so
    /// it can never be mistaken for normal — the design's explicit requirement
    /// ("still recording, just not interrupting; never silently invisible").
    var filledBars: Int {
        switch self {
        case .normal: 1
        case .elevated: 2
        case .incident: 3
        case .muted: 0
        }
    }

    /// The diagonal stroke across the bars. Muted only.
    var isSlashed: Bool { self == .muted }

    /// Reinforcement, never the carrier. `tint` is a name rather than a `Color` so
    /// this type stays free of SwiftUI and testable without a view.
    var tint: MenuBarIconTint {
        switch self {
        case .normal: .green
        case .elevated: .yellow
        case .incident: .red
        case .muted: .grey
        }
    }
}

enum MenuBarIconTint: String, Equatable, Sendable {
    case green, yellow, red, grey
}

/// Everything the icon is derived from, gathered in one value so the derivation is
/// a pure function of measured state and nothing in the view reaches for a
/// singleton.
struct MenuBarIconInputs: Equatable, Sendable {
    /// The live machine-wide judgement (`MonitorStore.severity`).
    var severity: Severity = .normal
    /// Whether an incident is open right now (FR-011).
    var incidentIsOpen = false
    var incidentSeverity: IncidentSeverity?
    /// The open incident's conditions, already ordered; the first is the one the
    /// spoken label names.
    var incidentConditions: [IncidentCondition] = []
    /// How long the open incident has been running, measured from `beganAt`.
    var incidentDuration: Duration?
    /// Conditions currently breaching without an incident yet — what "elevated"
    /// is about.
    var elevatedConditions: [IncidentCondition] = []
    var isMuted = false
    /// Nil while not muted, or when the mute is indefinite.
    var muteRemaining: Duration?
    var muteIsIndefinite = false
    /// The name of the application leading the attribution, when there is one.
    var leadingApplicationName: String?
    /// The user's rule for that application, if any (FR-016, design 1j).
    var leadingApplicationPolicy: PolicyClassification?

    /// Whether the leading application is one the user told us heavy load is
    /// normal for.
    ///
    /// `.ignored` counts as well as `.expected`. The design's sentence names
    /// "expected", but `.ignored` is the strictly stronger statement — "never
    /// alert me about this" — and it would be incoherent for the weaker rule to
    /// cap the icon while the stronger one did not.
    var leadingApplicationIsExpected: Bool {
        switch leadingApplicationPolicy {
        case .expected, .ignored: true
        case .watched, nil: false
        }
    }
}

/// What to draw and what to say. Everything the view needs, and nothing it has to
/// work out for itself.
struct MenuBarIconPresentation: Equatable, Sendable {
    let state: MenuBarIconState
    /// The small dot on the corner of the glyph. Present whenever an incident is
    /// open — including while muted, and including when the state was capped to
    /// elevated by a policy. The badge says "an episode is being recorded", which
    /// is a fact about the machine, not a severity we are allowed to withhold.
    let showsBadge: Bool
    /// True when a user policy held the icon below the state the measurement alone
    /// would have produced. Carried so the reason is available rather than
    /// inferred, and so a test can assert on the cap directly.
    let cappedByExpectedWorkload: Bool
    let accessibilityLabel: String

    static let normal = MenuBarIconPresentation(
        state: .normal, showsBadge: false, cappedByExpectedWorkload: false,
        accessibilityLabel: MenuBarIcon.name + ", normal")
}

/// The rules behind the menu bar icon, kept out of the view so that every one of
/// them is checkable without putting anything on screen.
enum MenuBarIcon {
    static let name = "MacSlowdown"

    /// One state change per this interval, at most (design 2d).
    static let minimumInterval: Duration = .seconds(2)

    /// The cross-fade between two states. A fade, deliberately, and the only
    /// timed visual in the icon: nothing here moves, rotates or pulses. A spinning
    /// menu bar icon during a slowdown is the design's named worst case.
    static let crossFadeSeconds: Double = 0.25

    /// The window the optional sparkline covers.
    static let sparklineWindow: Duration = .seconds(60)

    // MARK: - Deriving the state

    /// The state, the badge and the spoken label, from measured inputs alone.
    ///
    /// Precedence, in order:
    ///  1. **Muted** wins the glyph. FR-015 makes muting a suppression of
    ///     interruption, and the always-visible icon is the one place that has to
    ///     keep saying so — a muted app that looked normal would be a silently
    ///     disabled monitor. The badge and the spoken label still carry the open
    ///     incident, so nothing is hidden by muting; only the colour is.
    ///  2. **An open incident** is the red state — but only if the leading
    ///     application is not one the user marked as expected.
    ///  3. **Expected workload caps at elevated.** "Red never appears for a
    ///     workload the user marked expected; that shows as yellow at most."
    ///  4. **Elevated** covers every non-normal live severity without an incident,
    ///     including `.severe`. Severe-but-not-yet-sustained is exactly the case
    ///     elevated exists for; promoting it to the incident glyph would make the
    ///     duration threshold invisible again.
    static func presentation(for inputs: MenuBarIconInputs) -> MenuBarIconPresentation {
        let capped = inputs.incidentIsOpen && inputs.leadingApplicationIsExpected
        let state: MenuBarIconState =
            if inputs.isMuted { .muted }
            else if inputs.incidentIsOpen && !capped { .incident }
            else if inputs.incidentIsOpen || inputs.severity > .normal { .elevated }
            else { .normal }

        return MenuBarIconPresentation(
            state: state,
            showsBadge: inputs.incidentIsOpen,
            cappedByExpectedWorkload: capped,
            accessibilityLabel: accessibilityLabel(state: state, inputs: inputs))
    }

    // MARK: - Saying it out loud (FR-034)

    /// The VoiceOver label, following the design's table.
    ///
    /// Two places go beyond the table, both because the table did not consider the
    /// combination and silence would be the worse answer:
    ///  - muted **with an incident open** appends the incident clause, so the one
    ///    always-present surface never omits that an episode is being recorded;
    ///  - an elevated state **capped by a policy** says which application was
    ///    marked expected, so a user who wonders why it is not red can hear why.
    static func accessibilityLabel(state: MenuBarIconState,
                                   inputs: MenuBarIconInputs) -> String {
        switch state {
        case .normal:
            return "\(name), normal"

        case .elevated:
            var parts = ["\(name), elevated"]
            if let condition = primaryCondition(inputs) {
                parts.append(conditionWord(condition))
            }
            if inputs.incidentIsOpen, let duration = inputs.incidentDuration {
                parts.append(durationPhrase(duration))
            }
            if inputs.leadingApplicationIsExpected, let app = inputs.leadingApplicationName {
                parts.append("\(app) is marked as expected")
            }
            return parts.joined(separator: ", ")

        case .incident:
            var parts = ["\(name), \(severityWord(inputs.incidentSeverity))"]
            if let condition = primaryCondition(inputs) {
                parts.append(conditionWord(condition))
            }
            if let duration = inputs.incidentDuration {
                parts.append(durationPhrase(duration))
            }
            return parts.joined(separator: ", ")

        case .muted:
            var label = mutedPhrase(inputs)
            if inputs.incidentIsOpen {
                var clause = ["incident open"]
                if let condition = primaryCondition(inputs) {
                    clause.append(conditionWord(condition))
                }
                if let duration = inputs.incidentDuration {
                    clause.append(durationPhrase(duration))
                }
                label += ", " + clause.joined(separator: ", ")
            }
            return label
        }
    }

    /// "muted for 41 more minutes", or the indefinite form. Always says muted, so
    /// the word is present however the mute was set.
    static func mutedPhrase(_ inputs: MenuBarIconInputs) -> String {
        if inputs.muteIsIndefinite || inputs.muteRemaining == nil {
            return "\(name), muted until you turn alerts back on"
        }
        guard let remaining = inputs.muteRemaining else {
            return "\(name), muted until you turn alerts back on"
        }
        let minutes = max(1, Int((remaining.totalSeconds / 60).rounded()))
        return "\(name), muted for \(minutes) more minute\(minutes == 1 ? "" : "s")"
    }

    /// The condition the label names: the incident's when one is open, otherwise
    /// whatever is breaching now.
    static func primaryCondition(_ inputs: MenuBarIconInputs) -> IncidentCondition? {
        if inputs.incidentIsOpen, let first = inputs.incidentConditions.first { return first }
        return inputs.elevatedConditions.first
    }

    /// The one-word form the design uses — "CPU", "memory" — rather than
    /// `IncidentCondition.label`, which is written for a sentence in a report.
    static func conditionWord(_ condition: IncidentCondition) -> String {
        switch condition {
        case .cpuSaturation: "CPU"
        case .memoryPressure: "memory"
        case .lowStorage: "storage"
        case .thermalPressure: "thermal"
        // Not a resource at all — an application quitting repeatedly while the
        // machine is fine (FR-046, design 1o). "quits" rather than a resource
        // noun, because naming one here would imply we measured a shortage that
        // this condition exists to say we did not (TASK-71).
        case .repeatedApplicationQuits: "quits"
        }
    }

    static func severityWord(_ severity: IncidentSeverity?) -> String {
        (severity ?? .moderate).label.lowercased()
    }

    /// "11 minutes". Below a minute the count of minutes would round to zero or
    /// one and either would be a claim the clock does not support, so it is said
    /// in words instead.
    static func durationPhrase(_ duration: Duration) -> String {
        let seconds = max(0, duration.totalSeconds)
        guard seconds >= 60 else { return "less than a minute" }
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = minutes / 60
        let remainder = minutes % 60
        let hourPart = "\(hours) hour\(hours == 1 ? "" : "s")"
        guard remainder > 0 else { return hourPart }
        return "\(hourPart) \(remainder) minute\(remainder == 1 ? "" : "s")"
    }

    // MARK: - Ordering conditions

    /// A stable order for a set of conditions, so the spoken label does not change
    /// its mind between samples about which one to name first. `allCases` order is
    /// the declaration order in `Metrics`, which runs from the most common cause
    /// of a slowdown to the least.
    static func ordered(_ conditions: Set<IncidentCondition>) -> [IncidentCondition] {
        IncidentCondition.allCases.filter { conditions.contains($0) }
    }

    // MARK: - Matching a policy to the leading application (FR-016)

    /// Enough of an application to match a user policy against, without dragging a
    /// `ResolvedIdentity` — and therefore a live process — into the icon's inputs.
    /// An incident's recorded contributor and a live family both reduce to this.
    struct LeadingApplication: Equatable, Sendable {
        var bundleID: String?
        var bundlePath: String?
        var displayName: String

        init(bundleID: String? = nil, bundlePath: String? = nil, displayName: String) {
            self.bundleID = bundleID
            self.bundlePath = bundlePath
            self.displayName = displayName
        }
    }

    /// The user's rule for an application, matched the same way
    /// `ApplicationPolicy.matches` matches one: bundle identifier first, then
    /// bundle path, and a display-name match only for a policy that carries
    /// neither. Re-implemented rather than reused because `matches` takes a
    /// `ResolvedIdentity`, which an incident recorded weeks ago does not have.
    static func policy(for application: LeadingApplication?,
                       in policies: [ApplicationPolicy]) -> ApplicationPolicy? {
        guard let application else { return nil }
        return policies.first { policy in
            if let id = policy.bundleID, let candidate = application.bundleID, id == candidate {
                return true
            }
            if let path = policy.bundlePath, let candidate = application.bundlePath,
               path == candidate {
                return true
            }
            return policy.bundleID == nil && policy.bundlePath == nil
                && policy.displayName == application.displayName
        }
    }

    /// The application leading a live attribution, reduced to what a policy match
    /// needs.
    ///
    /// Found by locating the top contributor's family rather than by sorting the
    /// families, because the icon is redrawn far more often than the inventory and
    /// a sort per redraw is work the design's "high-priority path" cannot afford.
    /// Falls back to the contributor's own label when it belongs to no family —
    /// about 85% of the table is standalone (see CLAUDE.md), so that is the
    /// ordinary case, not an error.
    static func leadingApplication(attribution: CPUAttribution?,
                                   families: [ProcessFamily]) -> LeadingApplication? {
        guard let contributor = attribution?.contributors.first else { return nil }
        if let family = families.first(where: { family in
            family.members.contains { $0.record.identity == contributor.identity }
        }) {
            return LeadingApplication(
                bundleID: family.members.compactMap { $0.resolved.bundleID }.first,
                bundlePath: family.bundlePath,
                displayName: family.displayName)
        }
        return LeadingApplication(displayName: contributor.label)
    }

    /// The same, for an incident, from what the incident recorded while it was open
    /// — never from live state, which by then describes a different machine.
    static func leadingApplication(incident: Incident?) -> LeadingApplication? {
        guard let leader = incident?.attribution?.leadingApplication else { return nil }
        return LeadingApplication(
            bundleID: leader.bundleID,
            bundlePath: leader.bundlePath,
            displayName: leader.displayName)
    }
}
