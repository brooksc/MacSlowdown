import Darwin
import Foundation

/// How a conclusion came to be known (FR-038).
///
/// Every figure and every statement the app makes carries one of these, so a user
/// or support recipient can judge it. It is part of the data, not presentation: a
/// calculated remainder must never be presented as though it were read from a
/// counter, and a hypothesis must never be presented as either.
public enum Evidence: String, Sendable, CaseIterable, Codable {
    /// Read directly from a kernel counter.
    case measured
    /// Derived arithmetically from measured values.
    case calculated
    /// An interpretation of the measurements. Always carries a confidence level,
    /// because it could be wrong.
    case heuristic
    /// Supplied by the user, e.g. marking a workload as expected.
    case userProvided

    public var label: String {
        switch self {
        case .measured: "Measured"
        case .calculated: "Calculated"
        case .heuristic: "Likely"
        case .userProvided: "You told us"
        }
    }

    /// Only a heuristic can be wrong in a way a confidence level describes.
    public var requiresConfidence: Bool { self == .heuristic }
}

/// How much weight a heuristic conclusion deserves (FR-013).
public enum Confidence: String, Sendable, CaseIterable, Codable {
    case low, moderate, high
    public var label: String {
        switch self {
        case .low: "low confidence"
        case .moderate: "moderate confidence"
        case .high: "high confidence"
        }
    }
}

public struct AttributedFigure: Sendable {
    public let label: String
    /// Percentage of one core. 100% is one core fully busy.
    public let percentOfOneCore: Double
    public let evidence: Evidence
}

/// A protected process that was running during the interval.
///
/// We can name every process regardless of ownership — `sysctl KERN_PROC_ALL`
/// returns name, uid, parent and start time for all of them. Only CPU and memory
/// are denied. So which protected processes were running is a **measured fact**,
/// even though how much CPU each used is not obtainable. That distinction is what
/// makes the unattributed bucket useful rather than an anonymous blob.
public struct ProtectedProcess: Sendable {
    public let identity: ProcessIdentity
    public let command: String
    public let uid: uid_t
    /// Start time as a wall-clock date, so it can be correlated with an incident
    /// window (FR-045).
    public var startedAt: Date {
        Date(timeIntervalSince1970: Double(identity.startTime) / 1_000_000)
    }
}

/// The complete CPU picture for an interval, guaranteed to account for 100%.
///
/// Roughly 40 percentage points of busy CPU typically cannot be attributed to any
/// visible process, because other-uid processes (WindowServer, mds_stores, backupd,
/// coreaudiod, launchd) are denied — identically whether or not we are sandboxed.
/// A contributor list that silently failed to sum would misrepresent the machine,
/// so the remainder is a first-class figure rather than an omission.
public struct CPUAttribution: Sendable {
    /// Measured: from `host_processor_info`.
    public let totalBusyPercentOfOneCore: Double
    /// Measured: the sum of per-process counters we were permitted to read.
    public let attributedPercentOfOneCore: Double
    /// Calculated: total minus attributed. Never negative.
    public let unattributedPercentOfOneCore: Double
    /// Per-process usage that could be attributed, largest first.
    public let contributors: [ProcessCPUUsage]
    /// Named processes whose usage we could not read. Measured fact.
    public let protectedProcesses: [ProtectedProcess]
    public let logicalCoreCount: Int

    /// Unattributed as a share of all busy CPU, 0...1.
    public var unattributedShare: Double {
        guard totalBusyPercentOfOneCore > 0 else { return 0 }
        return unattributedPercentOfOneCore / totalBusyPercentOfOneCore
    }

    /// Every figure with its evidence class, for a UI that must never show a list
    /// that fails to sum.
    public var figures: [AttributedFigure] {
        [
            AttributedFigure(label: "Total CPU",
                             percentOfOneCore: totalBusyPercentOfOneCore, evidence: .measured),
            AttributedFigure(label: "Attributed to applications",
                             percentOfOneCore: attributedPercentOfOneCore, evidence: .measured),
            AttributedFigure(label: "Unattributed system activity",
                             percentOfOneCore: unattributedPercentOfOneCore, evidence: .calculated),
        ]
    }

    /// Plain-language explanation of the limitation.
    ///
    /// States what was measured and what was not, without claiming causation
    /// (FR-013) and without implying the remainder is waste or a fault (FR-036).
    public var explanation: String {
        guard unattributedPercentOfOneCore > 0 else {
            return "All busy CPU in this interval was attributed to processes we can measure."
        }
        let share = Int((unattributedShare * 100).rounded())
        // Names come from p_comm, which the kernel truncates to 16 bytes, so
        // distinct processes can share a name. Dedupe rather than repeating one.
        var seen = Set<String>()
        let names = protectedProcesses
            .map(\.command)
            .filter { seen.insert($0).inserted }
            .prefix(3)
            .joined(separator: ", ")

        var text = "\(share)% of busy CPU came from system processes whose per-process "
        text += "usage macOS does not report to App Store apps. "
        text += "The figure is the measured difference between total CPU and everything "
        text += "we are permitted to read, not an estimate."
        if !names.isEmpty {
            text += " Processes running during this interval include \(names)"
            text += " — we can see that they ran, but not how much CPU they used."
        }
        return text
    }
}

public enum CPUAttributionCalculator {
    /// Builds the full picture for the interval between two snapshots.
    public static func attribution(
        from earlier: ProcessSnapshot,
        to later: ProcessSnapshot,
        hostEarlier: HostCPUSample,
        hostLater: HostCPUSample,
        logicalCoreCount: Int = MachineTopology.logicalCoreCount,
        naming: (ProcessIdentity) -> String? = { _ in nil }
    ) -> CPUAttribution {
        let contributors = CPUUsage.between(earlier, later, naming: naming)
            .sorted { $0.percentOfOneCore > $1.percentOfOneCore }
        let attributed = contributors.reduce(0) { $0 + $1.percentOfOneCore }

        let busyFraction = HostCPU.busyFraction(from: hostEarlier, to: hostLater) ?? 0
        let hostTotal = busyFraction * Double(logicalCoreCount) * 100

        // The host aggregate and the per-process counters are read at slightly
        // different instants, so under heavy load the attributed sum can marginally
        // exceed the host total. Clamping the remainder at zero was not enough:
        // it left attributed + unattributed > total, breaking the FR-055 invariant
        // that the parts account for the whole. This was caught by the saturation
        // test, not by review.
        //
        // Both figures are measurements, so when they disagree the sum of the parts
        // is a lower bound on the whole — a machine cannot be less busy than the
        // work we positively observed. Taking the larger keeps every measurement,
        // discards none, and makes the invariant hold by construction.
        let totalBusy = max(hostTotal, attributed)
        let unattributed = totalBusy - attributed

        let protected = later.records.values
            .filter { $0.metrics == .notPermitted }
            .map { ProtectedProcess(identity: $0.identity, command: $0.command, uid: $0.uid) }
            .sorted { $0.command < $1.command }

        return CPUAttribution(
            totalBusyPercentOfOneCore: totalBusy,
            attributedPercentOfOneCore: attributed,
            unattributedPercentOfOneCore: unattributed,
            contributors: contributors,
            protectedProcesses: protected,
            logicalCoreCount: logicalCoreCount
        )
    }
}
