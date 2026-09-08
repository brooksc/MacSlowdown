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
    /// A per-application rule (FR-016), naming the application the rule is about.
    case applicationPolicy(application: String)
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
    /// Applications the user marked as expected (FR-016). Suppressed detections
    /// still appear in history, so the audit trail survives.
    public var expectedApplications: Set<String>
    /// Conditions the user has asked to hear about even though they are recorded
    /// rather than announced by default. Empty by default (FR-014 amendment 1).
    public var announcedConditions: Set<IncidentCondition> = []

    public init(
        announcesIncidents: Bool = true,
        minimumSeverity: IncidentSeverity = .high,
        respectFocus: Bool = true,
        deferDuringAudio: Bool = true,
        expectedApplications: Set<String> = []
    ) {
        self.announcesIncidents = announcesIncidents
        self.minimumSeverity = minimumSeverity
        self.respectFocus = respectFocus
        self.deferDuringAudio = deferDuringAudio
        self.expectedApplications = expectedApplications
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

    public func decide(
        incident: Incident,
        leadingContributor: String? = nil,
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
        let announceable = incident.conditions.filter {
            $0.announcesByDefault || settings.announcedConditions.contains($0)
        }
        if announceable.isEmpty {
            let names = incident.conditions.sorted { $0.label < $1.label }
                .map(\.label).joined(separator: " and ")
            return .suppress(
                reason: names.isEmpty
                    ? "this is recorded rather than announced"
                    : "\(names) is recorded rather than announced",
                cause: .recordedNotAnnounced)
        }

        if let contributor = leadingContributor,
           settings.expectedApplications.contains(contributor) {
            return .suppress(reason: "you marked \(contributor) as expected",
                             cause: .applicationPolicy(application: contributor))
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
