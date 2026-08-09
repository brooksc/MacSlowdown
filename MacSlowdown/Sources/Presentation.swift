import Foundation
import Metrics

/// Pure formatting and ranking used by `MonitorStore`.
///
/// Separated from the store because the store's state is only ever written by the
/// sampling loop, which makes these rules unreachable from a test while they live
/// on it. As free functions over their inputs they can be checked against the
/// cases that matter — zero, missing, saturated — rather than whatever the machine
/// happened to be doing.
enum Presentation {
    /// FR-030 self-report.
    static func selfCost(cpuPercentOfOneCore: Double, residentBytes: UInt64) -> String {
        let memory = ByteCountFormatStyle().format(Int64(residentBytes))
        return String(format: "MacSlowdown itself: %.1f%% CPU, %@",
                      cpuPercentOfOneCore, memory as NSString)
    }

    /// Aggregate disk throughput (FR-009).
    ///
    /// Aggregate because per-process I/O is blocked under the sandbox. Always a
    /// rate over the measured interval, never a cumulative total.
    /// Nil rates are stated as unavailable, never as zero: a disk driver that will
    /// not report its statistics is not an idle disk (FR-002, FR-010).
    static func diskThroughput(_ rates: DiskRates?) -> String {
        guard let rates else { return "Not available" }
        let read = ByteCountFormatStyle().format(Int64(rates.readBytesPerSecond))
        let write = ByteCountFormatStyle().format(Int64(rates.writeBytesPerSecond))
        return "\(read)/s read · \(write)/s write"
    }

    /// Swap activity, described without implying memory can be freed (FR-036).
    static func swapActivity(_ rates: PagingRates) -> String {
        rates.isSwapping
            ? "macOS is moving memory to and from disk"
            : "No swapping"
    }

    /// Families with measurable usage, largest first.
    ///
    /// A family with neither CPU nor memory is dropped rather than shown as a row
    /// of zeroes: an inventory of nothing is noise, and FR-002 would require
    /// labelling those zeroes as unavailable rather than measured.
    static func rankedFamilies(
        _ families: [ProcessFamily],
        contributions: [ProcessIdentity: Double]
    ) -> [MonitorStore.FamilyRow] {
        families.map { family in
            let usage = family.members.reduce(into: (cpu: 0.0, memory: UInt64(0))) { totals, member in
                if let contribution = contributions[member.record.identity] {
                    totals.cpu += contribution
                }
                totals.memory += member.record.measurements?.residentBytes ?? 0
            }
            return MonitorStore.FamilyRow(
                family: family, percentOfOneCore: usage.cpu, residentBytes: usage.memory)
        }
        .filter { $0.percentOfOneCore > 0 || $0.residentBytes > 0 }
        .sorted { $0.percentOfOneCore > $1.percentOfOneCore }
    }

    /// Applies the table's sort order (FR-027).
    ///
    /// Ordering only. Sorting must never filter, re-read or re-sample: the set of
    /// rows a user sees has to be the same set whichever column they clicked, or
    /// the table would quietly hide processes as a side effect of being tidied.
    ///
    /// A tie is broken by name so that equal values — very common, since most
    /// processes sit at 0% — do not shuffle between samples and make the table
    /// look busier than the machine is.
    static func sorted(
        _ rows: [MonitorStore.FamilyRow],
        by order: [KeyPathComparator<MonitorStore.FamilyRow>]
    ) -> [MonitorStore.FamilyRow] {
        guard !order.isEmpty else { return rows }
        return rows.sorted { first, second in
            for comparator in order {
                switch comparator.compare(first, second) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return first.family.displayName.localizedCaseInsensitiveCompare(
                second.family.displayName) == .orderedAscending
        }
    }

    /// The order the table opens in: busiest first, which is what the surface is
    /// for. Named so the view and its test cannot disagree about it.
    static let defaultSortOrder = [
        KeyPathComparator(\MonitorStore.FamilyRow.percentOfOneCore, order: .reverse)
    ]

    /// Keeps the most recent incidents, newest first (FR-005 bounds evidence).
    static func retained(_ incidents: [Incident], limit: Int) -> [Incident] {
        incidents.count > limit ? Array(incidents.prefix(limit)) : incidents
    }

    /// Share of total machine capacity, from a percentage of one core.
    ///
    /// Kept here rather than inline because getting it wrong is the FR-004 trap:
    /// 800% of one core is full saturation on 8 cores and a quarter of it on 32.
    static func busyShareOfMachine(percentOfOneCore: Double, logicalCores: Int) -> Double {
        guard logicalCores > 0 else { return 0 }
        return percentOfOneCore / (Double(logicalCores) * 100)
    }
}
