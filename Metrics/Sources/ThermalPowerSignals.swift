import Foundation
import AudioToolbox
import CoreAudio
import Darwin
import IOKit.ps

/// The system's thermal assessment (FR-010).
///
/// Deliberately **state only, never temperature**. Raw sensor values need
/// undocumented SMC keys, which A-03 and FR-010 both rule out, and inventing a
/// number would breach FR-036. macOS's own thermal state is a supported public
/// signal and is what actually correlates with reduced performance.
/// `Codable` so an incident can record the worst state it saw, and `Comparable` so
/// "worst" is a comparison rather than a hand-written ladder. The raw values are
/// ordered by severity and are part of the persisted format — do not renumber them.
public enum ThermalState: Int, Sendable, CaseIterable, Codable, Comparable {
    case nominal, fair, serious, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

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

/// Per-application audio activity (FR-019).
///
/// Measured available in TASK-28 with no microphone permission and no entitlement
/// beyond app-sandbox. Used to defer notifications during playback, meetings or
/// recording rather than interrupting them.
public enum AudioSignals {
    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func flag(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    /// Whether any process is currently playing audio or capturing from the mic.
    public static func isAnyProcessPlaying() -> Bool {
        processObjects().contains { flag($0, kAudioProcessPropertyIsRunning) }
    }

    /// The name of an audio-active process, for explaining why an alert waited.
    public static func firstActiveProcessName() -> String? {
        for object in processObjects() where flag(object, kAudioProcessPropertyIsRunning) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = -1
            var size = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr,
                  pid > 0 else { continue }
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, 3, 0, &info, infoSize) == infoSize {
                let name = withUnsafeBytes(of: &info.pbi_name) {
                    String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
                }
                if !name.isEmpty { return name }
            }
        }
        return nil
    }
}
