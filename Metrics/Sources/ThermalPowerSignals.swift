import Foundation
import IOKit.ps

/// The system's thermal assessment (FR-010).
///
/// Deliberately **state only, never temperature**. Raw sensor values need
/// undocumented SMC keys, which A-03 and FR-010 both rule out, and inventing a
/// number would breach FR-036. macOS's own thermal state is a supported public
/// signal and is what actually correlates with reduced performance.
public enum ThermalState: Int, Sendable, CaseIterable {
    case nominal, fair, serious, critical

    public var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    /// States what macOS reports without asserting undocumented throttling detail.
    public var explanation: String {
        switch self {
        case .nominal: "macOS reports normal thermal conditions."
        case .fair: "macOS reports slightly raised thermal conditions."
        case .serious:
            "macOS reports serious thermal conditions and may be reducing performance "
                + "to manage heat."
        case .critical:
            "macOS reports critical thermal conditions and is reducing performance to "
                + "manage heat."
        }
    }

    public static var current: ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}

/// Power context for interpreting performance and thermal behaviour (FR-047).
///
/// Every battery field is optional because desktop Macs have none, and FR-047
/// requires they degrade gracefully rather than reporting a fabricated zero.
public struct PowerContext: Sendable, Equatable {
    public enum Source: String, Sendable {
        case battery
        case externalPower = "external power"
        case unknown
    }

    public let source: Source
    /// Nil on a machine with no battery.
    public let batteryPercentage: Int?
    public let isCharging: Bool?
    public let lowPowerModeEnabled: Bool

    public var hasBattery: Bool { batteryPercentage != nil }

    /// Description that omits battery entirely when there is none, rather than
    /// saying "0%" or "unknown".
    public var summary: String {
        var parts: [String] = ["On \(source.rawValue)"]
        if let percentage = batteryPercentage {
            parts.append("battery \(percentage)%")
            if isCharging == true { parts.append("charging") }
        }
        if lowPowerModeEnabled { parts.append("Low Power Mode on") }
        return parts.joined(separator: " · ")
    }
}

public enum PowerSignals {
    /// Reads power source information. Available under App Sandbox.
    public static func current() -> PowerContext {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, first)?
                  .takeUnretainedValue() as? [String: Any]
        else {
            // No power source information at all — a desktop with no battery.
            // Report what we know rather than inventing battery figures.
            return PowerContext(source: .externalPower, batteryPercentage: nil,
                                isCharging: nil, lowPowerModeEnabled: lowPower)
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        let source: PowerContext.Source =
            state == kIOPSBatteryPowerValue ? .battery
            : state == kIOPSACPowerValue ? .externalPower
            : .unknown

        var percentage: Int?
        if let current = description[kIOPSCurrentCapacityKey] as? Int,
           let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
            percentage = Int((Double(current) / Double(maximum) * 100).rounded())
        }

        return PowerContext(
            source: source,
            batteryPercentage: percentage,
            isCharging: description[kIOPSIsChargingKey] as? Bool,
            lowPowerModeEnabled: lowPower
        )
    }
}
