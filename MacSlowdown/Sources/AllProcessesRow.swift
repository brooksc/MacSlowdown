import Darwin
import Foundation
import Metrics

/// One process in the flat "All processes" view (FR-002, FR-027).
///
/// The peer of the application-grouped inventory, not a replacement for it. Only
/// about one process in seven belongs to an application, so a view organised by
/// application cannot show most of what is running — and the process a user is
/// hunting is very often one of the other six.
struct AllProcessesRow: Identifiable, Equatable {
    /// `(pid, start time)`. A PID alone is not an identity: macOS wraps PID
    /// allocation at 99999 and reuse is routine on a machine that has been up for
    /// days.
    let id: String
    let pid: pid_t
    let parentPID: pid_t
    /// The best name we have. Never the bare 16-byte `p_comm` fragment presented
    /// as though it were the process's real name (FR-002).
    let name: String
    /// The application this process belongs to, where it belongs to one. Nil for
    /// the great majority of the table — daemons and command-line tools are
    /// first-class, not families of one.
    let owningApplication: String?
    /// What this process is for, when we know. Nil is honest and common.
    let descriptor: String?
    /// The parent's command, when the parent could be identified. Used to say
    /// "parent launchd" rather than leaving lineage as a bare number.
    let parentCommand: String?
    let startedAt: Date
    /// Percentage of one core. Meaningless unless `isMeasurable` — read `cpuText`,
    /// never this, for anything a user sees.
    let percentOfOneCore: Double
    let residentBytes: UInt64
    /// False when macOS refuses this process's per-process counters. Decided
    /// exactly by uid: own-uid readable, other-uid denied, no exceptions either
    /// way. Not a sandbox effect — root-owned processes are denied identically to
    /// an unsandboxed build.
    let isMeasurable: Bool
    let executablePath: String?

    /// The second line under the name: which application owns this, or what the
    /// process is for and why we cannot measure it.
    var subtitle: String? {
        if let owningApplication { return owningApplication }
        var parts: [String] = []
        if let descriptor { parts.append(descriptor) }
        if !isMeasurable {
            if let parentCommand { parts.append("parent \(parentCommand)") }
            // "Protected" is the reason, stated on the row. A user should not have
            // to infer from a blank cell that we were refused.
            parts.append("protected")
        } else if descriptor != nil {
            parts.append("user level")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// FR-002: a reading we were refused reads as refused, never as a number.
    static let notMeasurableText = "Not measurable"

    var cpuText: String {
        isMeasurable ? CPUPresentation.percentOfOneCore(percentOfOneCore) : Self.notMeasurableText
    }

    var memoryText: String {
        isMeasurable
            ? ByteCountFormatStyle().format(Int64(residentBytes))
            : Self.notMeasurableText
    }

    /// Sort keys.
    ///
    /// Negative for an unmeasurable row so that "we were not allowed to look"
    /// cannot land among genuine zeroes. This is a second line of defence only:
    /// the guarantee that unmeasurable rows never outrank a measurable one comes
    /// from `AllProcesses.listing`, which sorts the two sets separately. A key
    /// alone would fail the moment the user sorted ascending.
    var cpuSortKey: Double { isMeasurable ? percentOfOneCore : -1 }
    var memorySortKey: Double { isMeasurable ? Double(residentBytes) : -1 }
    var pidSortKey: Int { Int(pid) }
    var startedSortKey: Double { startedAt.timeIntervalSince1970 }
}

/// The process table, counted honestly (FR-002, FR-038).
struct ProcessCensus: Equatable {
    let total: Int
    let measurable: Int
    let belongingToApplication: Int

    var notMeasurable: Int { total - measurable }

    /// The line under the table. States what we can measure and what we cannot, so
    /// that neither number can be mistaken for the other.
    var summary: String {
        "\(total) processes · \(measurable) measurable · \(notMeasurable) not measurable "
            + "· only \(belongingToApplication) belong to an app"
    }
}

/// Measurable and unmeasurable rows, in that order, always.
struct AllProcessesListing: Equatable {
    let measurable: [AllProcessesRow]
    let unmeasurable: [AllProcessesRow]

    /// The heading over the unmeasurable section, with the rule it obeys stated on
    /// screen rather than left as an implementation detail.
    var unmeasurableHeading: String {
        "\(unmeasurable.count) \(unmeasurable.count == 1 ? "process" : "processes") we can't measure"
    }

    static let unmeasurableRule =
        "Name, PID, parent and start time are readable. CPU and memory are not. "
        + "They sort to the end and never count as zero."
}

/// Building, filtering and ordering the flat process list.
///
/// Free functions over their inputs, so the rules that matter — that an
/// unmeasurable process never sorts as idle, that filtering never changes the
/// census — are reachable from a test rather than trapped inside a view.
enum AllProcesses {
    /// Builds one row per process from the grouped families.
    ///
    /// Families are the input rather than the raw snapshot because grouping is
    /// what knows which application a process belongs to, and because every
    /// process in the table appears in exactly one family — bundled or standalone.
    static func rows(
        _ families: [ProcessFamily],
        contributions: [ProcessIdentity: Double]
    ) -> [AllProcessesRow] {
        let parents = parentCommands(families)

        return families.flatMap { family in
            family.members.map { member -> AllProcessesRow in
                let record = member.record
                let measurements = record.measurements
                return AllProcessesRow(
                    id: "\(record.identity.pid):\(record.identity.startTime)",
                    pid: record.identity.pid,
                    parentPID: record.ppid,
                    name: member.resolved.displayName(command: record.command),
                    owningApplication: family.bundlePath == nil ? nil : family.displayName,
                    descriptor: SystemProcessDescriptors.meaning(forCommand: record.command),
                    parentCommand: parentCommand(
                        of: record, in: parents),
                    startedAt: Date(
                        timeIntervalSince1970: Double(record.identity.startTime) / 1_000_000),
                    percentOfOneCore: contributions[record.identity] ?? 0,
                    residentBytes: measurements?.residentBytes ?? 0,
                    isMeasurable: measurements != nil,
                    executablePath: member.resolved.executablePath)
            }
        }
    }

    /// Whether a row answers a search.
    ///
    /// One predicate, used both for the rows shown and for the count the empty
    /// application search reports (FR-027). Two predicates would eventually
    /// disagree, and the empty state would promise matches that the other scope
    /// does not contain.
    static func matches(_ row: AllProcessesRow, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if row.name.localizedCaseInsensitiveContains(query) { return true }
        if row.owningApplication?.localizedCaseInsensitiveContains(query) == true { return true }
        // Searching "Time Machine" should find `backupd`. The descriptor is how a
        // person names a daemon they cannot name.
        if row.descriptor?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }

    /// Filters, then orders — measurable first, always.
    ///
    /// **The rule this file exists for.** Unmeasurable processes sort to the end
    /// under *every* sort order, ascending or descending, on any column, because
    /// the two sets are ordered separately and concatenated. A process whose CPU
    /// we were refused is not a process using no CPU: ranking it as 0% would put
    /// the busiest processes on the machine — WindowServer, mds_stores, backupd —
    /// at the bottom of a CPU-sorted list, which is precisely the list a user
    /// opens when the machine is slow.
    static func listing(
        _ rows: [AllProcessesRow],
        query: String = "",
        by order: [KeyPathComparator<AllProcessesRow>]
    ) -> AllProcessesListing {
        let matching = query.isEmpty ? rows : rows.filter { matches($0, query: query) }
        return AllProcessesListing(
            measurable: sorted(matching.filter(\.isMeasurable), by: order),
            unmeasurable: sorted(matching.filter { !$0.isMeasurable }, by: order))
    }

    /// The census over the whole table, never over the filtered rows: "412
    /// processes running" has to stay true while the user is searching.
    static func census(_ rows: [AllProcessesRow]) -> ProcessCensus {
        ProcessCensus(
            total: rows.count,
            measurable: rows.count(where: \.isMeasurable),
            belongingToApplication: rows.count { $0.owningApplication != nil })
    }

    /// Ordering only — never filters, re-reads or re-samples. A tie breaks on name
    /// so that the many equal values do not shuffle between samples and make the
    /// table look busier than the machine is.
    static func sorted(
        _ rows: [AllProcessesRow],
        by order: [KeyPathComparator<AllProcessesRow>]
    ) -> [AllProcessesRow] {
        rows.sorted { first, second in
            for comparator in order {
                switch comparator.compare(first, second) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    /// The order the list opens in: busiest first, which is the question the
    /// screen exists to answer.
    static let defaultSort = [
        KeyPathComparator(\AllProcessesRow.cpuSortKey, order: .reverse)
    ]

    // MARK: - Lineage

    /// pid → (command, start time) for every process in the table.
    private static func parentCommands(
        _ families: [ProcessFamily]
    ) -> [pid_t: (command: String, startTime: UInt64)] {
        var index: [pid_t: (command: String, startTime: UInt64)] = [:]
        for family in families {
            for member in family.members {
                let identity = member.record.identity
                // A recycled PID can appear twice within one sweep only if the
                // table is inconsistent; prefer the later start, which is the one
                // currently holding the number.
                if let existing = index[identity.pid], existing.startTime > identity.startTime {
                    continue
                }
                index[identity.pid] = (member.record.command, identity.startTime)
            }
        }
        return index
    }

    /// The parent's command, or nil.
    ///
    /// Rejects a "parent" that started after its child: PIDs are reused, so the
    /// process currently holding a `ppid` is not necessarily the one that forked
    /// this process. Claiming otherwise would attribute a process to an unrelated
    /// parent.
    private static func parentCommand(
        of record: ProcessRecord,
        in parents: [pid_t: (command: String, startTime: UInt64)]
    ) -> String? {
        guard record.ppid != record.identity.pid, let parent = parents[record.ppid] else {
            return nil
        }
        guard parent.startTime <= record.identity.startTime else { return nil }
        return parent.command
    }
}
