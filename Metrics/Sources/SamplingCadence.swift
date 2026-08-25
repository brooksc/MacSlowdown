import Foundation

/// How often we are sampling, and why (FR-031).
public enum SamplingMode: String, Sendable, CaseIterable {
    /// Steady state. As slow as we can be while still catching a sustained
    /// condition promptly.
    case normal
    /// Something looks wrong, or an incident is open. Higher resolution while it
    /// matters, so the evidence window is usable afterwards.
    case investigation

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .investigation: "Investigation"
        }
    }
}

/// Chooses the sampling cadence and explains itself (FR-031).
///
/// FR-031 requires the user be able to inspect the current cadence, so this
/// exposes both the interval and the reason rather than hiding the decision.
public struct SamplingCadence: Sendable, Equatable {
    public let mode: SamplingMode
    public let interval: Duration
    /// Why we are sampling at this rate, in plain language.
    public let reason: String

    public var description: String {
        let seconds = interval.totalSeconds
        let formatted = seconds < 1
            ? String(format: "%.0f ms", seconds * 1000)
            : String(format: "%.0f s", seconds)
        return "Sampling every \(formatted) · \(mode.label.lowercased()) · \(reason)"
    }
}

/// Raises resolution when something looks wrong and lowers it afterwards.
///
/// Two properties this guarantees, both tested:
///   - **No sample is lost across a transition.** The controller only ever changes
///     the *next* interval; it never cancels an in-flight sample or resets a
///     schedule mid-flight, so a mode change cannot create a gap.
///   - **Normal mode is no faster than necessary**, which is what keeps the
///     FR-030 idle budget met.
public struct CadenceController: Sendable {
    public var normalInterval: Duration
    public var investigationInterval: Duration
    /// How long elevated sampling continues after conditions clear, so the
    /// recovery window is captured at full resolution rather than dropping to
    /// normal the instant things improve.
    public var investigationLinger: Duration

    /// Defaults amended 2026-08-25 (FR-031, product owner): normal 2 s → **1 s**,
    /// investigation 1 s → **0.5 s**.
    ///
    /// The product explains sustained behaviour, and every per-application figure
    /// it showed was one sample — visibly twitching, and unaverageable because no
    /// per-application history was kept. A trailing mean and a per-application
    /// curve both need per-second retention, which needs per-second sampling.
    ///
    /// Investigation tightens in step so that FR-031's actual requirement —
    /// resolution *rises* while something looks wrong — survives; at equal rates it
    /// would not. The escalation is now 2× rather than up to 5×, which is also
    /// gentler on a machine already in trouble (FR-032).
    public init(
        normalInterval: Duration = .seconds(1),
        investigationInterval: Duration = .milliseconds(500),
        investigationLinger: Duration = .seconds(60)
    ) {
        self.normalInterval = normalInterval
        self.investigationInterval = investigationInterval
        self.investigationLinger = investigationLinger
    }

    public struct State: Sendable {
        var mode: SamplingMode = .normal
        var elevatedUntil: Date?
        /// Counted so a test can prove no sample is skipped across a transition.
        public private(set) var samplesTaken = 0
        public private(set) var modeChanges = 0

        public init() {}

        mutating func recordSample() { samplesTaken += 1 }
        mutating func recordModeChange() { modeChanges += 1 }
    }

    /// The cadence to use for the next sample.
    ///
    /// `incidentOpen` covers an incident already running; `conditionBreaching`
    /// covers the pre-trigger case, where a condition is breaching but has not yet
    /// persisted long enough to count. FR-031 asks for higher resolution on a
    /// *suspected* incident, so waiting for the trigger would miss the evidence
    /// leading up to it.
    public func cadence(
        at now: Date,
        incidentOpen: Bool,
        conditionBreaching: Bool,
        state: inout State
    ) -> SamplingCadence {
        state.recordSample()

        let shouldElevate = incidentOpen || conditionBreaching
        if shouldElevate {
            state.elevatedUntil = now.addingTimeInterval(investigationLinger.totalSeconds)
        }

        let lingering = (state.elevatedUntil.map { now < $0 }) ?? false
        let mode: SamplingMode = (shouldElevate || lingering) ? .investigation : .normal

        if mode != state.mode {
            state.mode = mode
            state.recordModeChange()
        }
        if mode == .normal { state.elevatedUntil = nil }

        return SamplingCadence(
            mode: mode,
            interval: mode == .investigation ? investigationInterval : normalInterval,
            reason: Self.reason(
                mode: mode, incidentOpen: incidentOpen,
                conditionBreaching: conditionBreaching, lingering: lingering)
        )
    }

    static func reason(
        mode: SamplingMode, incidentOpen: Bool,
        conditionBreaching: Bool, lingering: Bool
    ) -> String {
        _ = lingering
        switch mode {
        case .normal:
            return "nothing needs a closer look"
        case .investigation where incidentOpen:
            return "an incident is open"
        case .investigation where conditionBreaching:
            return "a condition is breaching but has not lasted long enough to count yet"
        case .investigation:
            return "capturing the recovery after a recent incident"
        }
    }
}
