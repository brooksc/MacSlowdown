import Foundation

/// What to say when a search of the applications finds nothing (FR-002, FR-027).
///
/// An empty list reads as an answer. If the user searches `backupd` in Apps and
/// sees "No results", they will conclude backupd is not running — when it is, and
/// is very possibly the cause of what they are investigating. Only about one
/// process in seven belongs to an application, so a search scoped to applications
/// misses most of the process table by construction.
///
/// So the empty state runs the same search against every process before it says
/// anything, and reports what it found. Pure values rather than view code, so the
/// wording is checkable — including the case that genuinely matches nothing, which
/// must not read like the case that matched somewhere else.
struct InventorySearchOutcome: Equatable {
    let query: String
    /// How many processes the same search matches in the all-processes scope.
    let matchesInAllProcesses: Int
    /// The whole process table, not the filtered set: "412 processes running" has
    /// to stay true while the user is searching.
    let totalProcesses: Int

    /// True when the thing the user searched for exists — just not here.
    var matchesElsewhere: Bool { matchesInAllProcesses > 0 }

    var title: String {
        matchesElsewhere
            ? "No application matches “\(query)”"
            : "Nothing matches “\(query)”"
    }

    var message: String {
        if matchesElsewhere {
            return "Only about one process in seven belongs to an application. "
                + "Daemons and command-line tools — including \(query) — run on their own "
                + "and are listed under All processes."
        }
        return "No application matches this, and neither does any of the "
            + "\(totalProcesses) \(totalProcesses == 1 ? "process" : "processes") running — "
            + "including the ones whose CPU and memory macOS does not report to us. "
            + "Nothing on this Mac answers to that name right now."
    }

    /// Nil when there is nowhere useful to go: offering to search a scope that
    /// also has no answer would be a button that does nothing.
    var actionTitle: String? {
        matchesElsewhere ? "Search All processes instead" : nil
    }

    /// The count that proves the point, under the empty state.
    var countSummary: String {
        let processes = "\(totalProcesses) \(totalProcesses == 1 ? "process" : "processes") running"
        guard matchesElsewhere else { return "No matches in All processes · \(processes)" }
        let matches = matchesInAllProcesses == 1
            ? "1 match in All processes"
            : "\(matchesInAllProcesses) matches in All processes"
        return "\(matches) · \(processes)"
    }

    /// One string for VoiceOver, since the empty state is three separate views on
    /// screen and reading them apart loses the argument (FR-034).
    var accessibilityDescription: String {
        [title, message, countSummary].joined(separator: ". ")
    }
}
