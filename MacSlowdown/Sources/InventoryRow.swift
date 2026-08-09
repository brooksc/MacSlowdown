import Darwin
import Foundation
import Metrics

/// How a family's members came to be grouped together (FR-003, FR-038, FR-039).
///
/// Counted rather than summarised into a single word, because "22 by bundle, 1 by
/// name only" is a statement a user can check and "grouped" is not.
struct GroupingProvenance: Equatable {
    /// The executable lives inside the bundle and nothing contradicts it.
    var byBundle = 0
    /// Inside the bundle, but the code signature says it belongs to something else.
    /// This is the heuristic case — the one the design chips as "grouped by guess".
    var byGuess = 0
    /// Outside the bundle entirely; grouped because this application started it.
    var byParent = 0
    /// The user put it here (FR-039).
    var userAssigned = 0

    var total: Int { byBundle + byGuess + byParent + userAssigned }

    /// One sentence per kind of evidence, in decreasing strength. Empty when there
    /// is only one process and therefore nothing to explain.
    var sentences: [String] {
        guard total > 1 || byGuess > 0 else { return [] }
        var lines: [String] = []
        if byBundle > 0 {
            lines.append("\(byBundle) \(processes(byBundle)) run from inside this "
                         + "application's bundle.")
        }
        if byGuess > 0 {
            lines.append("\(byGuess) \(processes(byGuess)) run from inside the bundle but "
                         + "carry a different code signature, so the match is a guess.")
        }
        if byParent > 0 {
            lines.append("\(byParent) \(processes(byParent)) live outside the bundle and are "
                         + "grouped here because this application started them.")
        }
        if userAssigned > 0 {
            lines.append("\(userAssigned) \(processes(userAssigned)) were placed here by you.")
        }
        return lines
    }

    private func processes(_ count: Int) -> String {
        count == 1 ? "process" : "processes"
    }

    static func of(_ members: [FamilyMember]) -> GroupingProvenance {
        var provenance = GroupingProvenance()
        for member in members {
            switch member.membership {
            case .certain: provenance.byBundle += 1
            case .uncertain: provenance.byGuess += 1
            case .byParent: provenance.byParent += 1
            case .userAssigned: provenance.userAssigned += 1
            }
        }
        return provenance
    }
}

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
    /// The application bundle this row represents, when it is one. Nil for
    /// standalone processes, member rows and the system group.
    var bundlePath: String?
    let kind: Kind
    /// Percentage of one core. Meaningless unless `isMeasurable`.
    let percentOfOneCore: Double
    let residentBytes: UInt64
    /// False when the sandbox denied this process's metrics. Such a row shows
    /// "unavailable", never a zero that would read as "idle" (FR-002).
    let isMeasurable: Bool
    let processCount: Int
    /// The process's own PID. Nil on an aggregate row, where there is no single
    /// PID and a made-up one would be worse than a dash.
    var pid: pid_t?
    /// When the process started. On a family row, the earliest of its members —
    /// the moment that family first appeared.
    var startedAt: Date?
    /// Why this process is grouped where it is, when that needs saying (FR-003).
    let qualification: String?
    /// True when this member is inside a bundle whose signature contradicts it —
    /// the case the design marks "Grouped by guess".
    var isGroupedByGuess = false
    /// How this family's members were matched. Empty for member rows.
    var provenance = GroupingProvenance()
    var children: [InventoryRow]

    var hasChildren: Bool { !children.isEmpty }

    /// Sort key for CPU.
    ///
    /// Unmeasurable rows take a negative value so they occupy a defined position
    /// — last, descending — rather than mixing in with genuine zeroes. Sorting
    /// them as 0 would put "we were not allowed to look" alongside "idle".
    var cpuSortKey: Double { isMeasurable ? percentOfOneCore : -1 }
    var memorySortKey: Double { isMeasurable ? Double(residentBytes) : -1 }
    /// Aggregates have no PID and sort together, below every real one.
    var pidSortKey: Int { pid.map(Int.init) ?? -1 }
    /// A start time we do not have sorts before every one we do, rather than
    /// landing at 1970 among the real values.
    var startedSortKey: Double { startedAt?.timeIntervalSince1970 ?? -1 }
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
                    pid: member.record.identity.pid,
                    startedAt: startDate(member.record.identity.startTime),
                    qualification: qualification(for: member.membership),
                    isGroupedByGuess: member.membership.isUncertain,
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
                bundlePath: family.bundlePath,
                kind: .application,
                percentOfOneCore: cpu,
                residentBytes: memory,
                isMeasurable: true,
                processCount: members.count,
                // A family has no PID of its own. A single-process family does,
                // and showing it is the whole point of the column for daemons.
                pid: members.count == 1 ? members[0].pid : nil,
                // The moment this application first appeared, which is the
                // earliest of its members — a helper started later did not start
                // the app.
                startedAt: members.compactMap(\.startedAt).min(),
                // A single-process family carries its member's qualification
                // itself: there is no expansion to put it in.
                qualification: members.count == 1 ? members[0].qualification : nil,
                isGroupedByGuess: members.count == 1 && members[0].isGroupedByGuess,
                provenance: .of(family.members),
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
            startedAt: systemMembers.compactMap(\.startedAt).min(),
            qualification: nil,
            children: systemMembers.sorted { $0.name < $1.name }))

        return applications
    }

    /// A process start time as a date.
    ///
    /// `kinfo_proc.kp_proc.p_starttime` is microseconds since the epoch. Zero means
    /// the kernel gave us nothing, which reads as "unknown" rather than 1970.
    static func startDate(_ startTime: UInt64) -> Date? {
        guard startTime > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(startTime) / 1_000_000)
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
            var copy = row
            copy.children = sortedInventory(row.children, by: order)
            return copy
        }
    }

    /// The order the inventory opens in: busiest application first.
    static let defaultInventorySort = [
        KeyPathComparator(\InventoryRow.cpuSortKey, order: .reverse)
    ]
}
