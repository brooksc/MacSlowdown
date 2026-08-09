import Foundation

/// A degradation condition the system can observe.
public enum IncidentCondition: String, Sendable, CaseIterable, Codable {
    case cpuSaturation
    case memoryPressure
    case lowStorage
    case thermalPressure

    public var label: String {
        switch self {
        case .cpuSaturation: "CPU saturation"
        case .memoryPressure: "Memory pressure"
        case .lowStorage: "Low storage"
        case .thermalPressure: "Thermal pressure"
        }
    }
}

public enum IncidentSeverity: Int, Sendable, Comparable, Codable {
    case moderate, high, severe
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var label: String {
        switch self {
        case .moderate: "Moderate"
        case .high: "High"
        case .severe: "Severe"
        }
    }
}

/// Thresholds and durations. Every value is configurable, as FR-006 and FR-011
/// require, so these defaults are a starting point rather than a decision.
///
/// The defaults trade false alarms against missed events deliberately:
///   - **3 minutes** of sustained CPU saturation. Long enough that a build, an
///     export or a Spotlight burst has to genuinely persist; short enough that a
///     user who notices a slowdown will find it recorded.
///   - **85% of machine capacity**, not of one core. On an 8-core Mac that is
///     roughly 6.8 cores busy, which is a machine in trouble rather than a
///     machine working.
///   - **60 seconds of recovery** before closing. Hysteresis exists so a workload
///     that dips for one sample does not split into two incidents.
///   - **2-minute merge window**, so related conditions arriving slightly apart
///     become one episode rather than several.
public struct IncidentPolicy: Sendable, Equatable {
    public var cpuBusyFractionThreshold: Double
    public var cpuSustainedDuration: Duration
    public var memoryPressureSustainedDuration: Duration
    public var thermalSustainedDuration: Duration
    public var recoveryDuration: Duration
    public var mergeWindow: Duration

    public init(
        cpuBusyFractionThreshold: Double = 0.85,
        cpuSustainedDuration: Duration = .seconds(180),
        memoryPressureSustainedDuration: Duration = .seconds(90),
        thermalSustainedDuration: Duration = .seconds(120),
        recoveryDuration: Duration = .seconds(60),
        mergeWindow: Duration = .seconds(120)
    ) {
        self.cpuBusyFractionThreshold = cpuBusyFractionThreshold
        self.cpuSustainedDuration = cpuSustainedDuration
        self.memoryPressureSustainedDuration = memoryPressureSustainedDuration
        self.thermalSustainedDuration = thermalSustainedDuration
        self.recoveryDuration = recoveryDuration
        self.mergeWindow = mergeWindow
    }

    public static let `default` = IncidentPolicy()

    func sustainedDuration(for condition: IncidentCondition) -> Duration {
        switch condition {
        case .cpuSaturation: cpuSustainedDuration
        case .memoryPressure: memoryPressureSustainedDuration
        case .thermalPressure: thermalSustainedDuration
        case .lowStorage: .seconds(60)
        }
    }
}

/// One reading of everything the detector considers.
public struct SystemObservation: Sendable {
    public let at: Date
    /// Fraction of total machine capacity in use, 0...1.
    public let cpuBusyFraction: Double
    public let memoryPressure: MemoryPressureLevel
    public let thermalState: ThermalState
    public let lowStorage: Bool
    /// What was busy at this instant, for the detector to record on the incident.
    ///
    /// Optional because rolling attribution up to applications costs more than the
    /// rest of the observation, and there is nothing to record it on unless a
    /// condition is breaching or an incident is already open. `nil` means "not
    /// offered", never "nothing was running".
    public var attribution: AttributionSample?

    public init(
        at: Date,
        cpuBusyFraction: Double,
        memoryPressure: MemoryPressureLevel = .normal,
        thermalState: ThermalState = .nominal,
        lowStorage: Bool = false,
        attribution: AttributionSample? = nil
    ) {
        self.at = at
        self.cpuBusyFraction = cpuBusyFraction
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
        self.lowStorage = lowStorage
        self.attribution = attribution
    }

    public func breaches(_ condition: IncidentCondition, policy: IncidentPolicy) -> Bool {
        switch condition {
        case .cpuSaturation: cpuBusyFraction >= policy.cpuBusyFractionThreshold
        case .memoryPressure: memoryPressure >= .warning
        case .thermalPressure: thermalState.rawValue >= ThermalState.serious.rawValue
        case .lowStorage: lowStorage
        }
    }
}

/// A degradation episode (FR-011).
public struct Incident: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// When the condition first breached, which precedes the trigger by the
    /// sustained duration.
    public let beganAt: Date
    /// When it had persisted long enough to count as an incident.
    public let triggeredAt: Date
    /// When conditions last cleared. Set while recovery hysteresis runs; cleared
    /// again if the condition returns before the incident closes.
    public var recoveryStartedAt: Date?
    /// When the incident closed, after recovery held for the hysteresis period.
    public var closedAt: Date?

    public var conditions: Set<IncidentCondition>
    public var severity: IncidentSeverity
    public var peakCPUBusyFraction: Double
    public var peakMemoryPressure: MemoryPressureLevel

    /// What the incident was attributed to, recorded while it was open and frozen
    /// when it closed (FR-011's "leading contributors", FR-013's evidence).
    ///
    /// `nil` means no attribution was recorded — either nothing measurable was
    /// running or none was offered. It never means "we could not decide", and a
    /// screen must not fall back to live state to fill the gap: live state
    /// describes the machine now, not the machine that was in trouble.
    public var attribution: IncidentAttribution?

    /// User actions recorded during this incident (FR-050). Only ever appended by
    /// `record(_:)`, which requires an action to have actually run.
    public var actions: [ActionVerification] = []

    /// Detections a user policy suppressed during this incident (FR-016). A
    /// suppressed alert is still a recorded incident; this is the audit trail that
    /// says why the user never saw it.
    public var suppressions: [SuppressedDetection] = []

    /// Whether `beganAt` was established from retained readings rather than from
    /// observations made after the condition was first noticed (TASK-69).
    ///
    /// Set only when a threshold change re-decided an already-present condition
    /// against samples the app had already kept. It is the reason an incident can
    /// appear the instant a setting changes and claim to have begun minutes
    /// earlier — a claim that is true, and that FR-038 requires be attributable.
    public var beganAtEstablishedFromRetainedHistory = false

    /// Why this incident is dated before the moment its threshold changed
    /// (FR-038). Nil when nothing unusual established the start.
    public var startProvenance: Conclusion? {
        guard beganAtEstablishedFromRetainedHistory else { return nil }
        return Conclusion(
            "Dated from readings MacSlowdown had already kept. When the threshold "
                + "changed, CPU was above the new line and the retained readings show "
                + "it had been since \(beganAt.formatted(date: .omitted, time: .standard)) "
                + "— so this is recorded from when the condition actually began, not "
                + "from when the setting changed.",
            evidence: .measured)
    }

    public var isOpen: Bool { closedAt == nil }
    public var duration: Duration {
        .seconds((closedAt ?? Date()).timeIntervalSince(beganAt))
    }

    /// Whether a moment falls inside the incident. An open incident is unbounded
    /// at its end, which is the honest answer while it is still running.
    public func covers(_ date: Date) -> Bool {
        date >= beganAt && date <= (closedAt ?? .distantFuture)
    }

    /// Links a user action to this incident (FR-050).
    ///
    /// Two conditions, both required, and neither is "the machine got better
    /// afterwards": the action must have **actually run**, and it must have been
    /// requested inside the incident's window. Recovery that merely coincides with
    /// something the user did is not evidence that they did anything — FR-050
    /// forbids reading an outcome out of correlation, and this is where that rule
    /// is enforced rather than in the wording of a label.
    ///
    /// Returns whether the link was made, so a caller cannot quietly assume it was.
    @discardableResult
    public mutating func record(_ verification: ActionVerification) -> Bool {
        guard verification.result.didRun, covers(verification.requestedAt) else { return false }
        actions.append(verification)
        return true
    }

    /// Links a policy-suppressed detection to the incident it suppressed (FR-016).
    @discardableResult
    public mutating func record(_ suppression: SuppressedDetection) -> Bool {
        guard covers(suppression.at) else { return false }
        suppressions.append(suppression)
        return true
    }

    /// How this incident ended, derived only from what was recorded.
    public var outcome: IncidentOutcome {
        if isOpen { return .open }
        if let action = actions.last { return .recoveredAfterRecordedAction(action) }
        if let suppression = suppressions.last { return .notAlerted(suppression) }
        return .recovered
    }
}

/// The end state of an incident, in the four forms the evidence can support.
///
/// There is deliberately no case for "recovered because you acted". The strongest
/// thing the measurements license is that the two happened in that order, which is
/// what `recoveredAfterRecordedAction` says and what its statement is careful to
/// keep saying.
public enum IncidentOutcome: Sendable, Equatable {
    case open
    /// Recovered, with no user action recorded during the incident.
    case recovered
    /// Recovered, and a user action was recorded inside the incident's window.
    case recoveredAfterRecordedAction(ActionVerification)
    /// A user policy suppressed the alert. The incident was still recorded.
    case notAlerted(SuppressedDetection)

    /// The statement to show, carrying its evidence class (FR-038).
    public var statement: Conclusion {
        switch self {
        case .open:
            Conclusion("Still going.", evidence: .measured)
        case .recovered:
            Conclusion("Recovered — no action was recorded.", evidence: .measured)
        case .recoveredAfterRecordedAction(let verification):
            Conclusion(
                "Recovered after you used \"\(verification.action.title)\" on "
                    + "\(verification.target). \(verification.summary)",
                evidence: .measured)
        case .notAlerted(let suppression):
            Conclusion(
                "Not alerted — you marked \(suppression.application) as "
                    + "\"\(suppression.classification.label)\". It was still recorded.",
                evidence: .userProvided)
        }
    }
}

/// What the detector did with an observation.
public enum IncidentEvent: Sendable, Equatable {
    case opened(Incident)
    /// Conditions changed or severity rose while the incident stayed open.
    case updated(Incident)
    case closed(Incident)
}

/// Turns a stream of observations into episodes (FR-011).
///
/// Three properties this exists to guarantee, all of which are tested:
///   - A transient spike shorter than the sustained duration never opens an
///     incident (FR-006).
///   - Repeated observations while an incident is open do not create duplicates.
///   - An incident closes only after recovery has held for the hysteresis period,
///     so a workload that dips for one sample does not split in two.
public struct IncidentDetector: Sendable {
    public var policy: IncidentPolicy

    /// Mutable detector state, kept explicit so the type stays a value and tests
    /// can drive it deterministically.
    public struct State: Sendable {
        public init() {}
        var breachStart: [IncidentCondition: Date] = [:]
        /// Conditions whose `breachStart` was established from retained readings
        /// by `adopt(_:state:retainedCPU:)` rather than by a live observation.
        var breachStartFromRetainedHistory: Set<IncidentCondition> = []
        public internal(set) var current: Incident?
        /// Kept after closing so a new breach inside the merge window can rejoin
        /// the previous episode rather than starting a second one.
        var lastClosed: Incident?

        /// Links a user action to the open incident, if one covers it (FR-050).
        ///
        /// Only the open incident: a closed one has already been handed to whoever
        /// keeps the history, and mutating the detector's private copy of it would
        /// leave two versions of the same incident disagreeing about what the user
        /// did. The caller links closed incidents in the collection it owns.
        @discardableResult
        public mutating func record(_ verification: ActionVerification) -> Bool {
            current?.record(verification) == true
        }

        @discardableResult
        public mutating func record(_ suppression: SuppressedDetection) -> Bool {
            current?.record(suppression) == true
        }
    }

    public init(policy: IncidentPolicy = .default) {
        self.policy = policy
    }

    // MARK: - Changing thresholds while the machine is already in trouble (TASK-69)

    /// One retained CPU reading, in the units the detector judges (fraction of
    /// total machine capacity, 0...1).
    ///
    /// A separate type rather than `HistorySample` because the detector must not
    /// be handed anything it could be tempted to derive a *second* opinion from.
    /// The only thing re-deciding a threshold is allowed to use is a busy fraction
    /// and the moment it was measured.
    public struct RetainedCPUReading: Sendable, Equatable {
        public let at: Date
        public let busyFraction: Double

        public init(at: Date, busyFraction: Double) {
            self.at = at
            self.busyFraction = busyFraction
        }
    }

    /// Adopts a changed policy without postponing an incident that was already
    /// building (TASK-69).
    ///
    /// Two things go wrong if a threshold change is treated as a fresh start, and
    /// both delay the very incident the user tightened settings to catch sooner:
    ///
    ///  1. Clearing `breachStart` restarts the sustained-duration clock on a
    ///     condition that had already been running for minutes. So it is kept.
    ///  2. Keeping it is not enough. `breachStart` is only ever set while
    ///     `breaches()` is true, so *tightening* a threshold finds it nil for a
    ///     condition that was sitting just below the old line — and the clock then
    ///     starts from the next observation, delaying the incident by the whole
    ///     sustained duration for a condition that was present throughout.
    ///
    /// The second is fixed by re-deciding the start against `retainedCPU`: readings
    /// the app actually took and kept. **Nothing is assumed.** The walk stops at the
    /// first reading below the new threshold and at any gap wider than
    /// `maximumSampleGap`, so a period we did not measure can never be counted as a
    /// period the condition held. If the retained series does not reach back far
    /// enough, the answer is a shorter start — never a longer one.
    ///
    /// CPU only. Memory pressure and thermal state are not in the retained series,
    /// so for those conditions there is nothing to look back over and the clock
    /// legitimately starts from the change.
    ///
    /// `retainedCPU` must be in ascending time order, which is the order
    /// `MetricsHistory` accumulates it.
    ///
    /// Returns whether the start was moved back over retained readings, so a caller
    /// cannot quietly assume either outcome.
    @discardableResult
    public mutating func adopt(
        _ newPolicy: IncidentPolicy,
        state: inout State,
        retainedCPU: [RetainedCPUReading] = [],
        maximumSampleGap: Duration = .seconds(30)
    ) -> Bool {
        guard newPolicy != policy else { return false }
        // Deliberately left alone: a condition already breaching keeps every second
        // it has accumulated, whichever way the threshold moved.
        policy = newPolicy

        guard let derived = Self.earliestRetainedBreachStart(
            in: retainedCPU,
            threshold: newPolicy.cpuBusyFractionThreshold,
            maximumSampleGap: maximumSampleGap)
        else { return false }

        if let existing = state.breachStart[.cpuSaturation], existing <= derived {
            return false
        }
        state.breachStart[.cpuSaturation] = derived
        state.breachStartFromRetainedHistory.insert(.cpuSaturation)
        return true
    }

    /// The earliest moment in an unbroken run of retained readings, ending at the
    /// most recent one, that all sit at or above `threshold`.
    ///
    /// Nil when the most recent reading is below the threshold — which is the
    /// honest answer for "the condition is not present now" — and nil when there
    /// are no readings at all.
    static func earliestRetainedBreachStart(
        in readings: [RetainedCPUReading],
        threshold: Double,
        maximumSampleGap: Duration
    ) -> Date? {
        var start: Date?
        var previous: Date?
        for reading in readings.reversed() {
            guard reading.busyFraction >= threshold else { break }
            if let previous,
               previous.timeIntervalSince(reading.at) > maximumSampleGap.totalSeconds {
                break  // an unmeasured gap is not evidence the condition held
            }
            start = reading.at
            previous = reading.at
        }
        return start
    }

    public func observe(_ observation: SystemObservation, state: inout State) -> IncidentEvent? {
        // Which conditions are breaching right now, and for how long.
        var sustained: Set<IncidentCondition> = []
        for condition in IncidentCondition.allCases {
            if observation.breaches(condition, policy: policy) {
                let start = state.breachStart[condition] ?? observation.at
                state.breachStart[condition] = start
                let held = observation.at.timeIntervalSince(start)
                if held >= policy.sustainedDuration(for: condition).totalSeconds {
                    sustained.insert(condition)
                }
            } else {
                state.breachStart[condition] = nil
                state.breachStartFromRetainedHistory.remove(condition)
            }
        }

        if var incident = state.current {
            return update(&incident, with: observation, sustained: sustained, state: &state)
        }
        guard !sustained.isEmpty else { return nil }
        return open(observation, sustained: sustained, state: &state)
    }

    private func open(
        _ observation: SystemObservation,
        sustained: Set<IncidentCondition>,
        state: inout State
    ) -> IncidentEvent {
        let began = sustained
            .compactMap { state.breachStart[$0] }
            .min() ?? observation.at

        // Rejoin a recently closed episode rather than starting a second one for
        // what a user would experience as the same slowdown (FR-011 merge window).
        //
        // The window is measured from when the new condition BEGAN, not from when
        // it had persisted long enough to trigger. Using the trigger time would
        // add the whole sustained duration to the gap, so a stutter of a few
        // seconds would still split into two incidents whenever the sustained
        // duration exceeded the merge window — which it does by default.
        if var previous = state.lastClosed,
           let closedAt = previous.closedAt,
           began.timeIntervalSince(closedAt) <= policy.mergeWindow.totalSeconds {
            previous.closedAt = nil
            previous.recoveryStartedAt = nil
            previous.conditions.formUnion(sustained)
            Self.recordAttribution(from: observation, into: &previous)
            state.current = previous
            state.lastClosed = nil
            return .updated(previous)
        }

        var incident = Incident(
            id: UUID(),
            beganAt: began,
            triggeredAt: observation.at,
            recoveryStartedAt: nil,
            closedAt: nil,
            conditions: sustained,
            severity: severity(for: observation, conditions: sustained),
            peakCPUBusyFraction: observation.cpuBusyFraction,
            peakMemoryPressure: observation.memoryPressure
        )
        // If the start we are dating this from was recovered from retained readings
        // after a threshold change, say so on the incident rather than leave a user
        // to discover an incident that appeared instantly and claims to be minutes
        // old (TASK-69, FR-038).
        incident.beganAtEstablishedFromRetainedHistory = sustained.contains {
            state.breachStartFromRetainedHistory.contains($0) && state.breachStart[$0] == began
        }
        // FR-011: an incident is created with its leading contributors, not merely
        // with its times and severity.
        Self.recordAttribution(from: observation, into: &incident)
        state.current = incident
        return .opened(incident)
    }

    /// Folds the observation's attribution into the incident, if one was offered.
    ///
    /// Deliberately never reports a change: refreshing the recorded attribution is
    /// not a reason to emit `.updated`, or every sample would re-notify the user
    /// about an incident they have already been told about (FR-014).
    static func recordAttribution(from observation: SystemObservation, into incident: inout Incident) {
        guard let sample = observation.attribution else { return }
        if incident.attribution == nil {
            incident.attribution = IncidentAttribution(sample: sample, at: observation.at)
        } else {
            incident.attribution?.merge(sample, at: observation.at)
        }
    }

    private func update(
        _ incident: inout Incident,
        with observation: SystemObservation,
        sustained: Set<IncidentCondition>,
        state: inout State
    ) -> IncidentEvent? {
        // Any breach at all keeps the incident alive, not only a sustained one:
        // once an episode is open, a continuing condition should not have to
        // re-serve its duration.
        let stillBreaching = IncidentCondition.allCases.contains {
            observation.breaches($0, policy: policy)
        }

        // Kept current for as long as the incident is open, on every path below —
        // including the recovery clock, so the last thing recorded is what the
        // machine looked like as it came back.
        Self.recordAttribution(from: observation, into: &incident)

        var changed = false
        if stillBreaching {
            if incident.recoveryStartedAt != nil {
                incident.recoveryStartedAt = nil  // recovered, then relapsed
                changed = true
            }
            let newConditions = incident.conditions.union(sustained)
            if newConditions != incident.conditions {
                incident.conditions = newConditions
                changed = true
            }
            if observation.cpuBusyFraction > incident.peakCPUBusyFraction {
                incident.peakCPUBusyFraction = observation.cpuBusyFraction
                changed = true
            }
            if observation.memoryPressure > incident.peakMemoryPressure {
                incident.peakMemoryPressure = observation.memoryPressure
                changed = true
            }
            let escalated = severity(for: observation, conditions: incident.conditions)
            if escalated > incident.severity {
                incident.severity = escalated
                changed = true
            }
            state.current = incident
            return changed ? .updated(incident) : nil
        }

        // Nothing is breaching: run the recovery clock.
        let recoveryStart = incident.recoveryStartedAt ?? observation.at
        incident.recoveryStartedAt = recoveryStart

        if observation.at.timeIntervalSince(recoveryStart) >= policy.recoveryDuration.totalSeconds {
            incident.closedAt = observation.at
            state.current = nil
            state.lastClosed = incident
            return .closed(incident)
        }

        state.current = incident
        return nil  // recovering, but not yet closed
    }

    private func severity(
        for observation: SystemObservation,
        conditions: Set<IncidentCondition>
    ) -> IncidentSeverity {
        if observation.memoryPressure == .critical
            || observation.thermalState == .critical
            || conditions.count >= 3 {
            return .severe
        }
        if observation.cpuBusyFraction >= 0.95
            || observation.memoryPressure == .warning
            || conditions.count == 2 {
            return .high
        }
        return .moderate
    }
}
