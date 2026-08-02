import Darwin
import Foundation

/// Minimum machine and OS context needed to interpret measurements (FR-049).
///
/// Deliberately excludes serial numbers, hardware UUIDs and any other persistent
/// identifier: FR-049 requires their absence unless separately justified and
/// consented, and nothing here needs them. Percentages, thresholds and capability
/// differences cannot be read correctly without this, which is why it travels with
/// every incident and export.
public struct MachineContext: Sendable, Codable, Equatable {
    public let osVersion: String
    public let hardwareModel: String
    public let architecture: String
    public let logicalCores: Int
    public let performanceCores: Int?
    public let efficiencyCores: Int?
    public let physicalMemoryBytes: UInt64
    public let appVersion: String
    public let appBuild: String
    /// Bumped when the retained sample format changes, so old records stay
    /// interpretable after an update (FR-040).
    public let schemaVersion: Int

    public static let currentSchemaVersion = 1

    public static func current(bundle: Bundle = .main) -> MachineContext {
        let topology = CoreTopology.current
        return MachineContext(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: sysctlString("hw.model") ?? "unknown",
            architecture: sysctlString("hw.machine") ?? "unknown",
            logicalCores: topology.logical,
            performanceCores: topology.performance,
            efficiencyCores: topology.efficiency,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            schemaVersion: currentSchemaVersion
        )
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard buffer.withUnsafeMutableBytes({ sysctlbyname(name, $0.baseAddress, &size, nil, 0) }) == 0
        else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    public var physicalMemoryGB: Double {
        Double(physicalMemoryBytes) / 1_073_741_824
    }
}
