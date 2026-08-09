import Foundation
import Metrics

/// What the Apps list is and is not showing (FR-002, FR-038).
///
/// The design's footer states the census rather than leaving it implied, and it is
/// stated for a reason measured in `probe/FINDINGS.md`: only about 15% of the
/// process table belongs to an application, and roughly a quarter of it is owned by
/// another uid and cannot be measured at all. A list of applications that does not
/// say so reads as a complete account of the machine, which it is not.
struct InventoryCensus: Equatable {
    /// Families that are an application bundle.
    let applicationCount: Int
    /// Families that are neither an app nor owned by another uid — daemons and
    /// command-line tools running as you.
    let standaloneCount: Int
    let processesInApplications: Int
    let totalProcesses: Int
    /// Processes whose CPU and memory macOS refuses to report to us. Measurability
    /// is decided by uid, exactly.
    let notMeasurableProcesses: Int

    static let empty = InventoryCensus(
        applicationCount: 0, standaloneCount: 0, processesInApplications: 0,
        totalProcesses: 0, notMeasurableProcesses: 0)

    static func of(_ families: [ProcessFamily]) -> InventoryCensus {
        var applications = 0
        var standalone = 0
        var inApplications = 0
        var total = 0
        var notMeasurable = 0

        for family in families {
            total += family.members.count
            notMeasurable += family.notMeasurableCount
            if family.bundlePath == nil {
                standalone += 1
            } else {
                applications += 1
                inApplications += family.members.count
            }
        }

        return InventoryCensus(
            applicationCount: applications, standaloneCount: standalone,
            processesInApplications: inApplications, totalProcesses: total,
            notMeasurableProcesses: notMeasurable)
    }

    /// The footer sentence. Deliberately three plain counts rather than a
    /// percentage: a share invites the reader to treat the remainder as small.
    var summary: String {
        guard totalProcesses > 0 else { return "No processes have been read yet." }
        return "\(applicationCount) \(applicationCount == 1 ? "app" : "apps")"
            + " · \(processesInApplications) of \(totalProcesses) processes belong to an app"
            + " · \(notMeasurableProcesses) not measurable"
    }

    /// Why the two numbers that look like they should add up do not.
    static let explanation =
        "This view lists applications. Daemons and command-line tools do not belong "
        + "to an app and are not shown here — including when a search finds nothing. "
        + "Processes owned by another user account are named but never measured: "
        + "macOS reports their CPU and memory to no App Store app."

    /// How old the reading is, said in words rather than left to a timestamp the
    /// reader has to subtract (FR-002).
    static func freshness(lastUpdate: Date?, now: Date = Date()) -> String {
        guard let lastUpdate else { return "No reading yet" }
        let seconds = Int(now.timeIntervalSince(lastUpdate).rounded())
        switch seconds {
        case ..<0: return "Updated just now"
        case 0...1: return "Updated 1 s ago"
        case ..<90: return "Updated \(seconds) s ago"
        default: return "Updated \(seconds / 60) min ago"
        }
    }
}
