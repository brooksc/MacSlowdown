import Foundation
import Metrics

/// One row of the inventory, which may have children (FR-003, FR-027).
///
/// A single type for both levels so the table can sort and select uniformly.
/// FR-003 requires the individual PID records be preserved beneath the aggregate;
/// this is how they become reachable.
struct InventoryRow: Identifiable {
    enum Kind: Equatable {
        case application
        /// Processes owned by another uid. Named and counted, never measured —
        /// `proc_pidinfo` is denied for every one of them, so any per-process
        /// figure would be invented.
        case systemProcesses
        /// A single process beneath a family.
        case member
    }

    let id: String
    let name: String
    /// Where to look for an icon. Nil for rows that have none.
    let executablePath: String?
    let kind: Kind
    /// Percentage of one core. Meaningless unless `isMeasurable`.
    let percentOfOneCore: Double
    let residentBytes: UInt64
    /// False when the sandbox denied this process's metrics. Such a row shows
    /// "unavailable", never a zero that would read as "idle" (FR-002).
    let isMeasurable: Bool
    let processCount: Int
    /// Why this process is grouped where it is, when that needs saying (FR-003).
    let qualification: String?
    let children: [InventoryRow]

    var hasChildren: Bool { !children.isEmpty }

    /// Sort key for CPU.
    ///
    /// Unmeasurable rows take a negative value so they occupy a defined position
    /// — last, descending — rather than mixing in with genuine zeroes. Sorting
    /// them as 0 would put "we were not allowed to look" alongside "idle".
    var cpuSortKey: Double { isMeasurable ? percentOfOneCore : -1 }
    var memorySortKey: Double { isMeasurable ? Double(residentBytes) : -1 }
}

extension Presentation {
    /// Builds the inventory tree.
    ///
    /// Two things this does that the old flat list did not: it keeps each family's
    /// members as children, and it collects the processes we are not permitted to
    /// measure into one group instead of dropping them. They were previously
    /// filtered out for having no usage, which silently hid a quarter of the
    /// process table behind a figure that said only "unattributed".
    static func inventory(
        _ families: [ProcessFamily],
        contributions: [ProcessIdentity: Double],
        unattributedPercentOfOneCore: Double
    ) -> [InventoryRow] {
        var applications: [InventoryRow] = []
        var systemMembers: [InventoryRow] = []

        for family in families {
            let members = family.members.map { member -> InventoryRow in
                let measurements = member.record.measurements
                return InventoryRow(
                    id: "\(member.record.identity.pid):\(member.record.identity.startTime)",
                    name: member.resolved.displayName(command: member.record.command),
                    executablePath: member.resolved.executablePath,
                    kind: .member,
                    percentOfOneCore: contributions[member.record.identity] ?? 0,
                    residentBytes: measurements?.residentBytes ?? 0,
                    isMeasurable: measurements != nil,
                    processCount: 1,
                    qualification: qualification(for: member.membership),
                    children: [])
            }

            // A family we may not measure at all belongs in the system group. Its
            // members keep their names; none of them gets a number.
            if members.allSatisfy({ !$0.isMeasurable }) {
                systemMembers.append(contentsOf: members)
                continue
            }

            let cpu = members.reduce(0) { $0 + $1.percentOfOneCore }
            let memory = members.reduce(UInt64(0)) { $0 + $1.residentBytes }
            guard cpu > 0 || memory > 0 else { continue }

            applications.append(InventoryRow(
                id: family.id,
                name: family.displayName,
                executablePath: family.members.first?.resolved.executablePath,
                kind: .application,
                percentOfOneCore: cpu,
                residentBytes: memory,
                isMeasurable: true,
                processCount: members.count,
                // A single-process family carries its member's qualification
                // itself: there is no expansion to put it in.
                qualification: members.count == 1 ? members[0].qualification : nil,
                // No children when the family IS the process. A disclosure
                // triangle that opens to one row identical to the one above it is
                // noise on the great majority of rows, since most applications
                // are a single process.
                children: members.count > 1 ? members : []))
        }

        guard !systemMembers.isEmpty else { return applications }

        // FR-055: the total is the measured difference between host busy and
        // everything we could read. It is not divided among the members, because
        // it also contains kernel time and processes that came and went between
        // samples.
        applications.append(InventoryRow(
            id: "system-processes",
            name: "System processes",
            executablePath: nil,
            kind: .systemProcesses,
            percentOfOneCore: unattributedPercentOfOneCore,
            residentBytes: 0,
            isMeasurable: true,
            processCount: systemMembers.count,
            qualification: nil,
            children: systemMembers.sorted { $0.name < $1.name }))

        return applications
    }

    /// What to say about why a process sits where it does, or nil when the
    /// grouping needs no explanation.
    static func qualification(for membership: FamilyMembership) -> String? {
        switch membership {
        case .certain: nil
        case .uncertain(let reason): reason
        case .byParent(let reason): reason
        case .userAssigned: "you put this here"
        }
    }

    /// Applies the sort order to families and, independently, to each family's
    /// children.
    ///
    /// Sorting a flattened list would scatter children away from their parents.
    static func sortedInventory(
        _ rows: [InventoryRow],
        by order: [KeyPathComparator<InventoryRow>]
    ) -> [InventoryRow] {
        let sorted = order.isEmpty ? rows : rows.sorted { first, second in
            for comparator in order {
                switch comparator.compare(first, second) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }

        return sorted.map { row in
            guard row.hasChildren else { return row }
            return InventoryRow(
                id: row.id, name: row.name, executablePath: row.executablePath,
                kind: row.kind, percentOfOneCore: row.percentOfOneCore,
                residentBytes: row.residentBytes, isMeasurable: row.isMeasurable,
                processCount: row.processCount, qualification: row.qualification,
                children: sortedInventory(row.children, by: order))
        }
    }

    /// The order the inventory opens in: busiest application first.
    static let defaultInventorySort = [
        KeyPathComparator(\InventoryRow.cpuSortKey, order: .reverse)
    ]
}
