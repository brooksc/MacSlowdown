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
public struct IncidentPolicy: Sendable {
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

    public init(
        at: Date,
        cpuBusyFraction: Double,
        memoryPressure: MemoryPressureLevel = .normal,
        thermalState: ThermalState = .nominal,
        lowStorage: Bool = false
    ) {
        self.at = at
        self.cpuBusyFraction = cpuBusyFraction
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
        self.lowStorage = lowStorage
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

    public var isOpen: Bool { closedAt == nil }
    public var duration: Duration {
        .seconds((closedAt ?? Date()).timeIntervalSince(beganAt))
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
        public internal(set) var current: Incident?
        /// Kept after closing so a new breach inside the merge window can rejoin
        /// the previous episode rather than starting a second one.
        var lastClosed: Incident?
    }

    public init(policy: IncidentPolicy = .default) {
        self.policy = policy
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
            state.current = previous
            state.lastClosed = nil
            return .updated(previous)
        }

        let incident = Incident(
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
        state.current = incident
        return .opened(incident)
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
