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

    /// The one sentence the footer shows without being asked (design 4,
    /// TASK-65.22).
    ///
    /// **Why there is a short form at all.** The footer had grown to five or more
    /// rendered lines under a table — the census, a paragraph about what is
    /// listed, and a paragraph about why the order is damped — where the design
    /// calls for a single sentence and a separated census line. A block of
    /// explanation that size under every table is not read, which means its
    /// contents are not conveyed, which is the same outcome as deleting them and
    /// costs a third of the pane as well.
    ///
    /// Both facts it names are the ones a reader will otherwise misread as
    /// defects: an application-only list looks like a list that has lost the
    /// daemons, and a damped order under a column header that says CPU looks like
    /// broken sorting — which is precisely what TASK-63 turned out to be, an hour
    /// spent on a table that was sorting correctly.
    ///
    /// The full text is not deleted; it is one disclosure away, and it is the
    /// same constants rather than a paraphrase of them.
    static let shortExplanation =
        "Applications only, and rows hold their places for "
        + "\(Int(OrderStability.settleInterval)) s while you read."

    /// The same sentence for the All processes scope, which lists everything and
    /// so cannot say "applications only". The order rule is the half that carries
    /// over, and it is the half a reader is most likely to mistake for a defect.
    static let shortExplanationForAllProcesses =
        "Every process on this Mac, and rows hold their places for "
        + "\(Int(OrderStability.settleInterval)) s while you read."

    /// Everything the short sentence stands in for, in the order it should be
    /// read. Composed from the constants rather than restated, so the disclosed
    /// text cannot drift from the summary or from the inspector (FR-060).
    static var fullExplanations: [String] {
        [explanation, OrderStability.explanation, residentMemoryCaveat,
         perApplicationDiskCaveat].compactMap { $0 }
    }

    /// Why our memory figure and Activity Monitor's disagree.
    ///
    /// One constant because there were two copies with different wording — the
    /// inventory footer's and the inspector's — which is precisely how TASK-80
    /// found two differently-worded paraphrases of the per-app disk limitation on
    /// the Now screen, with a test asserting one of them verbatim. A caveat that
    /// exists twice is a caveat that will disagree with itself.
    static let residentMemoryCaveat =
        "Resident memory. Activity Monitor's Memory column shows a different "
        + "measure (footprint), so the numbers will not match exactly."

    /// Why there is no per-application disk column, and never will be in this build.
    static let perApplicationDiskCaveat =
        "Per-app disk activity is not available to App Store apps. macOS reports "
        + "per-process disk I/O only to unsandboxed tools, so there is no figure "
        + "here to show."

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
