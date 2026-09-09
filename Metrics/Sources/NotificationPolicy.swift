import Foundation

/// Why an alert was withheld, as a fact the app can act on rather than a sentence
/// written for a person (FR-014, FR-015, FR-016, FR-019).
///
/// Only one of these is *a rule the user wrote about an application*, and that is
/// the only one FR-016's audit trail is about. Answering "why was I not told" with
/// "you muted alerts" when the truth was "you marked Xcode expected" — or the
/// reverse — would make the trail worse than no trail at all. `reason` is the
/// sentence and this is the cause; they are produced in the same place so they
/// cannot disagree, which parsing the sentence back out would not guarantee.
public enum SuppressionCause: Sendable, Equatable {
    /// The "tell me about slowdowns" switch is off.
    case alertsOff
    case belowMinimumSeverity
    /// Every condition in this incident is one we record rather than announce
    /// (FR-014 amendment 1). Not a severity judgement and not a user setting:
    /// a statement that nothing here carries a decision the user could act on.
    case recordedNotAnnounced
    /// A per-application rule (FR-016), naming the application **and** the
    /// condition the rule is about. Both, since amendment 1: a rule that named only
    /// the application could not distinguish "Xcode's compiles are expected" from
    /// "Xcode is never a problem", and the trail inherited that ambiguity.
    case applicationPolicy(application: String, condition: IncidentCondition)
    /// The user turned this condition's interruptions off for every application
    /// (FR-016 amendment 1, design 5f's third sentence and 5g's toggles).
    ///
    /// Distinct from `recordedNotAnnounced`, which is our default and not a
    /// decision the user made. Answering "you asked not to be told" when nobody
    /// asked would be the misattribution the trail exists to prevent.
    case conditionSilenced(condition: IncidentCondition)
    /// Quiet for this work session (FR-016 amendment 1). A blanket, like a mute,
    /// but bounded by the login session rather than by a clock the user has to
    /// remember.
    case sessionQuiet
    /// Muted for a period (FR-015). A rule about *time*, not about an application.
    case muted
    case focus
    /// Held during playback, a call or recording (FR-019).
    case audio
    /// The one-alert-per-incident rule, which is not a user preference at all.
    case alreadyAnnounced
}

/// Why a notification was or was not delivered. Recorded rather than discarded,
/// so a user who wonders why they were not told can find out (FR-014, FR-016).
public enum NotificationDecision: Sendable, Equatable {
    case send(reason: String)
    case suppress(reason: String, cause: SuppressionCause)

    public var shouldSend: Bool { if case .send = self { true } else { false } }
    public var reason: String {
        switch self {
        case .send(let reason), .suppress(let reason, _): reason
        }
    }

    /// The cause, or nil for a decision to send.
    public var suppressionCause: SuppressionCause? {
        if case .suppress(_, let cause) = self { return cause }
        return nil
    }
}

/// Muting (FR-015).
///
/// Monitoring continues while muted — only the interruption is suppressed — so
/// the history is intact when the mute expires.
public struct MuteState: Sendable, Equatable {
    public var until: Date?

    public init(until: Date? = nil) { self.until = until }

    public func isMuted(at date: Date) -> Bool {
        guard let until else { return false }
        return date < until
    }

    public func remaining(at date: Date) -> Duration? {
        guard let until, date < until else { return nil }
        return .seconds(until.timeIntervalSince(date))
    }

    public static let notMuted = MuteState()
}

/// External conditions that should hold a notification back.
public struct InterruptionContext: Sendable {
    /// macOS Focus is on. FR-014 requires Focus be respected.
    public let focusActive: Bool
    /// An application is playing audio or using the microphone. FR-019 requires we
    /// not interrupt playback, meetings or recording — now implementable per
    /// application, since TASK-28 measured the capability as available.
    public let audioActive: Bool
    public let audioApplication: String?

    public init(focusActive: Bool = false, audioActive: Bool = false,
                audioApplication: String? = nil) {
        self.focusActive = focusActive
        self.audioActive = audioActive
        self.audioApplication = audioApplication
    }

    public static let quiet = InterruptionContext()
}

/// Which conditions may interrupt, and which are recorded silently
/// (FR-014 amendment 1, FR-063).
///
/// **The test is not severity, it is whether a decision plausibly attaches.**
/// Severity orders measurements; it says nothing about whether the user can act,
/// and for a long time this product used it as though it did.
///
/// Sustained CPU load is the case that forced the rule. On a developer's machine
/// the most common cause of it is a build the user started deliberately, and a
/// build produces the same reading, for the same duration, with the same
/// attribution as a genuine problem. Interrupting for it is not over-sensitivity —
/// it tells the user we have misread their work. So it is recorded, stays visible
/// on every live surface and in history, and the user may opt in to announcements.
///
/// Memory pressure and low storage still announce, because something can be
/// closed or deleted and the machine's behaviour will change. Thermal pressure is
/// recorded because the machine already signals it by getting hot and slow, and
/// there is nothing to be done about it that the user is not already doing.
///
/// **This is a bet with a known risk**, recorded here so it is revisited on
/// evidence rather than drifting: a product that rarely interrupts may rarely be
/// opened, and "opt-in" and "off" are close to the same thing in practice. The
/// counter is that a noisy product is uninstalled while a quiet one is merely
/// underused, and that FR-064's user-reported slowdowns are what will settle it.
extension IncidentCondition {
    /// Whether this condition may interrupt the user by default.
    ///
    /// A switch rather than a set, so a new condition cannot be added without
    /// someone deciding this question about it.
    public var announcesByDefault: Bool {
        switch self {
        case .memoryPressure, .lowStorage: true
        case .cpuSaturation, .thermalPressure: false
        // Already demoted to a record entirely (FR-046 amendment 5); it cannot
        // open an incident, so this is belt and braces.
        case .repeatedApplicationQuits: false
        }
    }

    /// Why the default above is what it is, in the words a settings screen shows
    /// beside the switch (design 5g).
    ///
    /// Kept next to the rule rather than in the view so the sentence and the
    /// behaviour cannot drift apart — the failure this repository has hit more than
    /// once, most recently with a menu bar icon whose design claimed a refresh path
    /// the code did not have.
    public var interruptionRationale: String {
        switch self {
        case .memoryPressure:
            "There's a list of apps to look at, so there's a decision."
        case .lowStorage:
            "Worth knowing before it stops you saving."
        case .cpuSaturation:
            "Off by default — usually it's work you started on purpose, and there's "
                + "nothing for us to suggest. Still recorded, and in the overview."
        case .thermalPressure:
            "Off by default — the Mac already signals this by slowing down, and "
                + "there's nothing to do about it that you aren't doing. Still recorded."
        case .repeatedApplicationQuits:
            "Recorded only. MacSlowdown can see that an app went and came back; it "
                + "cannot see that it stopped responding, so it never says so."
        }
    }
}

/// One suppression rule: what it silences, named rather than inferred
/// (FR-016 amendment 1).
///
/// **Naming is the whole point.** The rule this replaces was evaluated against
/// "the leading measurable contributor", and that ranking is incomplete by
/// construction — FR-055's unattributable share is often larger than any named
/// application — so a one-place change in an unstable ordering decided whether two
/// otherwise identical conditions announced. A rule now states its own subject, and
/// what it is tested against is *membership* of the contributor list, which no
/// re-ranking can change.
/// One rule, one application, one condition. Design 5f's third sentence — "Never
/// tell me about CPU load", any application — is deliberately *not* a rule with a
/// wildcard here: it is the same fact as switching that condition off in
/// `silencedConditions`, and expressing it twice would let two mechanisms disagree
/// about a condition's state with no way for a screen to say which won.
public struct SuppressionRule: Sendable, Equatable, Hashable {
    public let application: String
    public let condition: IncidentCondition

    public init(application: String, condition: IncidentCondition) {
        self.application = application
        self.condition = condition
    }

    /// Whether this rule silences one condition of an incident.
    ///
    /// `contributors` is every measurable contributor the incident recorded, in
    /// whatever order attribution produced. Order is deliberately not consulted.
    public func silences(condition: IncidentCondition, contributors: [String]) -> Bool {
        self.condition == condition && contributors.contains(application)
    }
}

public struct NotificationSettings: Sendable {
    /// Whether to announce anything at all (FR-014). Off is the "tell me about
    /// slowdowns" switch turned off, and it is a separate fact from
    /// `minimumSeverity`: raising the floor to `.severe` still announces severe
    /// incidents, which is not what someone who turned alerts off asked for.
    /// Detection and recording are unaffected either way.
    public var announcesIncidents: Bool
    /// Incidents below this are recorded but never announced.
    public var minimumSeverity: IncidentSeverity
    public var respectFocus: Bool
    public var deferDuringAudio: Bool
    /// The user's suppression rules (FR-016 amendment 1). Each names one condition
    /// and, unless it applies everywhere, one application. Suppressed detections
    /// still appear in history, so the audit trail survives.
    public var rules: [SuppressionRule]
    /// Conditions the user has asked to hear about even though they are recorded
    /// rather than announced by default. Empty by default (FR-014 amendment 1).
    public var announcedConditions: Set<IncidentCondition> = []
    /// Conditions the user has turned *off* although they announce by default —
    /// design 5g's switches, in the other direction.
    ///
    /// Two sets rather than one, because the third state matters: a condition in
    /// neither set is one the user has not had an opinion about, and its behaviour
    /// must follow `announcesByDefault` if we ever change that default. Storing a
    /// single "these interrupt" set would freeze today's defaults into every
    /// installation the moment anyone opened Settings.
    public var silencedConditions: Set<IncidentCondition> = []
    /// "Quiet for this work session" is running (FR-016 amendment 1).
    ///
    /// Not persisted anywhere: it is held in memory by the app and therefore ends
    /// at logout or restart with nothing for the user to remember. See
    /// `SessionQuiet`.
    public var sessionQuiet: Bool = false

    public init(
        announcesIncidents: Bool = true,
        minimumSeverity: IncidentSeverity = .high,
        respectFocus: Bool = true,
        deferDuringAudio: Bool = true,
        rules: [SuppressionRule] = []
    ) {
        self.announcesIncidents = announcesIncidents
        self.minimumSeverity = minimumSeverity
        self.respectFocus = respectFocus
        self.deferDuringAudio = deferDuringAudio
        self.rules = rules
    }

    /// Whether one condition may interrupt at all, before any rule about an
    /// application is consulted. The user's switch wins over the default in both
    /// directions; the default answers when they have not said.
    public func interrupts(_ condition: IncidentCondition) -> Bool {
        if silencedConditions.contains(condition) { return false }
        return condition.announcesByDefault || announcedConditions.contains(condition)
    }

    public static let `default` = NotificationSettings()
}

/// Decides whether an incident should interrupt the user (FR-014, FR-015).
///
/// The property this exists to guarantee: **one notification per incident**,
/// unless severity materially increases. An incident that grumbles on for an hour
/// must not produce an alert every sample.
public struct NotificationGate: Sendable {
    public var settings: NotificationSettings

    public struct State: Sendable {
        /// Highest severity already announced, per incident.
        var announced: [UUID: IncidentSeverity] = [:]
        public init() {}
    }

    public init(settings: NotificationSettings = .default) {
        self.settings = settings
    }

    /// - Parameter contributors: every measurable contributor the incident
    ///   recorded, in any order. A rule is tested against membership of this list
    ///   and never against a position in it (FR-016 amendment 1, FR-055).
    public func decide(
        incident: Incident,
        contributors: [String] = [],
        mute: MuteState = .notMuted,
        context: InterruptionContext = .quiet,
        at date: Date = Date(),
        state: inout State
    ) -> NotificationDecision {
        if !settings.announcesIncidents {
            return .suppress(reason: "you asked not to be told about slowdowns",
                             cause: .alertsOff)
        }

        if incident.severity < settings.minimumSeverity {
            return .suppress(reason: "below the severity you asked to hear about",
                             cause: .belowMinimumSeverity)
        }

        // Nothing here carries a decision the user could act on, so it is
        // recorded and not announced (FR-014 amendment 1). Checked after severity
        // so a severe CPU episode is still silent: severity orders the
        // measurement, it does not make the load actionable.
        let announceable = incident.conditions.filter { settings.interrupts($0) }
        if announceable.isEmpty {
            // Split so the two are never conflated: a condition the *user* switched
            // off is answered with their own decision, and one that is merely our
            // default is answered as our default. Preferring the user's decision
            // when both are true is the honest order — they asked, we did not.
            let silenced = incident.conditions
                .filter { settings.silencedConditions.contains($0) }
                .sorted { $0.label < $1.label }
            if let condition = silenced.first {
                return .suppress(
                    reason: "you asked not to be told about \(condition.label.lowercased())",
                    cause: .conditionSilenced(condition: condition))
            }
            let names = incident.conditions.sorted { $0.label < $1.label }
                .map(\.label).joined(separator: " and ")
            return .suppress(
                reason: names.isEmpty
                    ? "this is recorded rather than announced"
                    : "\(names) is recorded rather than announced",
                cause: .recordedNotAnnounced)
        }

        // FR-016 amendment 1. An incident announces if *any* of its announceable
        // conditions is unruled — a rule about CPU load from Xcode cannot silence
        // the memory pressure in the same episode, which is the defect the
        // amendment exists to fix. Only when every announceable condition is
        // covered does the incident go quiet, and the cause then names the rule
        // that covered the first of them rather than the application alone.
        let unruled = announceable.filter { condition in
            !settings.rules.contains {
                $0.silences(condition: condition, contributors: contributors)
            }
        }
        if unruled.isEmpty, !announceable.isEmpty {
            let condition = announceable.sorted { $0.label < $1.label }[0]
            // There is always a matching rule here — `unruled` is empty — but the
            // cause names the application, so it is read from the rule rather than
            // assumed. `announce` writes the trail entry from this, and inventing
            // an application for it would be inventing the user's decision.
            if let rule = settings.rules.first(where: {
                $0.silences(condition: condition, contributors: contributors)
            }) {
                return .suppress(
                    reason: "you asked not to be told about "
                        + "\(condition.label.lowercased()) from \(rule.application)",
                    cause: .applicationPolicy(
                        application: rule.application, condition: condition))
            }
        }

        if settings.sessionQuiet {
            return .suppress(
                reason: "you asked for quiet for this work session — "
                    + "this is waiting for you in Incidents",
                cause: .sessionQuiet)
        }

        if mute.isMuted(at: date) {
            let remaining = mute.remaining(at: date).map { Int($0.totalSeconds / 60) } ?? 0
            return .suppress(reason: "alerts are muted for another \(remaining) minutes",
                             cause: .muted)
        }

        if settings.respectFocus, context.focusActive {
            return .suppress(reason: "Focus is on — this is waiting for you in Incidents",
                             cause: .focus)
        }

        if settings.deferDuringAudio, context.audioActive {
            let application = context.audioApplication.map { " (\($0))" } ?? ""
            return .suppress(
                reason: "audio is playing or the microphone is in use\(application)",
                cause: .audio)
        }

        // The core rule: announce once, and again only on material escalation.
        if let alreadyAnnounced = state.announced[incident.id] {
            guard incident.severity > alreadyAnnounced else {
                return .suppress(reason: "already announced this incident",
                                 cause: .alreadyAnnounced)
            }
            state.announced[incident.id] = incident.severity
            return .send(reason: "severity rose to \(incident.severity.label.lowercased())")
        }

        state.announced[incident.id] = incident.severity
        return .send(reason: "new \(incident.severity.label.lowercased()) incident")
    }

    /// Notification text. States the resource and the leading contributor when one
    /// is known, and never claims a cause (FR-013, FR-036).
    public static func message(
        for incident: Incident,
        leadingContributor: String?
    ) -> (title: String, body: String) {
        let conditions = incident.conditions.map(\.label).sorted().joined(separator: " and ")
        let minutes = max(1, Int((incident.duration.totalSeconds / 60).rounded()))
        let title = "\(conditions) for \(minutes) minute\(minutes == 1 ? "" : "s")"

        var body = "Severity \(incident.severity.label.lowercased())."
        if let contributor = leadingContributor {
            body += " \(contributor) is the largest measurable contributor."
        }
        return (title, body)
    }
}
