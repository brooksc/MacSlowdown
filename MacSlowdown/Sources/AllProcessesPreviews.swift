#if DEBUG
import Metrics
import SwiftUI

/// Previews for `AllProcessesView`, so the screen can be *seen* without launching
/// the app.
///
/// **Why this file exists.** A great deal of this interface is built and almost
/// none of it has been looked at, because looking meant launching a menu bar app
/// onto the owner's display while they were using it. Xcode 27's `RenderPreview`
/// MCP tool renders a `#Preview` to a snapshot offscreen, which turns "nobody has
/// seen this" into something answerable in a terminal — but only for views that
/// have a preview to render, and this project had none.
///
/// **What a preview can and cannot settle.** It answers layout: truncation,
/// column widths, whether the footer fits on one line, what an empty result looks
/// like. It cannot answer anything about the running application — first run under
/// `LSUIElement`, the menu bar icon at 16 pt, the real restored window frame — and
/// a rendered preview must never be offered as evidence for those.
///
/// **The numbers below are placeholders, and the shapes are not.** Counts come
/// from a real sandboxed probe sweep (`probe/FINDINGS.md`): 967 processes, 681
/// measurable, and only ~15% belonging to any application. The rows deliberately
/// include the cases that have caused defects — a name truncated at the kernel's
/// 16-byte `p_comm` limit, processes owned by another uid that we are denied, a
/// long application name that has to truncate somewhere, and a daemon owned by no
/// application at all. Treat the figures as illustrative and the situations as
/// the requirement.

/// One placeholder row. Defaults chosen so each preview states only what it is
/// exercising.
private func row(
    _ pid: pid_t,
    _ name: String,
    cpu: Double,
    memoryMB: UInt64,
    owner: String? = nil,
    descriptor: String? = nil,
    parentCommand: String? = "launchd",
    measurable: Bool = true,
    shortened: Bool = false,
    path: String? = nil
) -> AllProcessesRow {
    AllProcessesRow(
        id: "\(pid)-\(UInt64(pid) * 1000)",
        pid: pid,
        parentPID: 1,
        name: name,
        nameIsShortened: shortened,
        owningApplication: owner,
        descriptor: descriptor,
        parentCommand: parentCommand,
        startedAt: Date(timeIntervalSinceNow: -3600),
        percentOfOneCore: cpu,
        residentBytes: memoryMB * 1024 * 1024,
        isMeasurable: measurable,
        executablePath: path)
}

/// A table with the four situations that have actually produced defects here.
private let mixedRows: [AllProcessesRow] = [
    // Ours, busy, belongs to an application.
    row(1352, "Brave Browser Helper (Renderer)", cpu: 38.2, memoryMB: 620,
        owner: "Brave Browser",
        path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser Helper"),
    row(2115, "Google Drive", cpu: 81.5, memoryMB: 126, owner: "Google Drive",
        path: "/Applications/Google Drive.app/Contents/MacOS/Google Drive"),
    // A long name with no application, which is where truncation shows.
    row(92813, "com.apple.WebKit.WebContent.Development", cpu: 12.0, memoryMB: 958,
        descriptor: "Web page content"),
    // The kernel's 16-byte limit reached: the name IS a fragment, and must not be
    // presented as though it were the whole name (FR-002).
    row(29627, "mediaanalysisd…", cpu: 17.8, memoryMB: 191,
        descriptor: "Photo and video analysis", shortened: true),
    // A daemon that belongs to nothing — the common case, not an edge case.
    row(991, "fileproviderd", cpu: 8.6, memoryMB: 83, descriptor: "File provider"),
    // Other-uid: denied by uid, exactly, and not a sandbox effect. CPU and memory
    // here are meaningless and the view must not print them as numbers.
    row(1, "launchd", cpu: 0, memoryMB: 0, descriptor: "System process manager",
        parentCommand: nil, measurable: false),
    row(956, "containermanagerd", cpu: 0, memoryMB: 0,
        descriptor: "App container management", measurable: false),
    row(78221, "WindowServer", cpu: 0, memoryMB: 0,
        descriptor: "Display and window compositing", measurable: false),
]

/// Measured proportions, not invented ones.
private let census = ProcessCensus(total: 967, measurable: 681, belongingToApplication: 145)

/// Wraps the view so the previews can supply the three bindings without repeating
/// the boilerplate, and so a preview can start in a chosen state.
private struct AllProcessesPreviewHost: View {
    var rows: [AllProcessesRow] = mixedRows
    var initialQuery: String = ""
    var initialShowsUnmeasurable: Bool = true

    @State private var query: String = ""
    @State private var showsUnmeasurable = true
    @State private var sortOrder = [
        KeyPathComparator(\AllProcessesRow.percentOfOneCore, order: .reverse)
    ]

    var body: some View {
        AllProcessesView(
            rows: rows,
            census: census,
            freshness: "updated 2 seconds ago",
            query: $query,
            showsUnmeasurable: $showsUnmeasurable,
            sortOrder: $sortOrder,
            // No icons: a preview has no icon cache, and `NSWorkspace.icon` never
            // returns nil — it returns a generic icon, which would claim an icon
            // the interface does not have.
            icon: { _ in nil })
        .onAppear {
            query = initialQuery
            showsUnmeasurable = initialShowsUnmeasurable
        }
    }
}

/// The ordinary case, and the one to read for truncation and column widths.
#Preview("All processes — mixed table") {
    AllProcessesPreviewHost()
        .frame(width: 720, height: 520)
}

/// `TASK-97` asks whether the tables fit the window's minimum width, and says to
/// measure rather than assume. This is that measurement at the narrow end.
#Preview("All processes — at minimum width") {
    AllProcessesPreviewHost()
        .frame(width: 504, height: 480)
}

/// Bracketing the width at which the table stops drawing. Rendered 2026-09-15:
/// 720 pt draws, 504 pt comes back **completely blank** — no header, no rows, no
/// footer. These three find the edge, because "it breaks when narrow" is not
/// actionable and "it breaks below N pt" is.
#Preview("All processes — 640 pt") {
    AllProcessesPreviewHost()
        .frame(width: 640, height: 480)
}

#Preview("All processes — 580 pt") {
    AllProcessesPreviewHost()
        .frame(width: 580, height: 480)
}

#Preview("All processes — 540 pt") {
    AllProcessesPreviewHost()
        .frame(width: 540, height: 480)
}

/// Unmeasurable rows hidden. The census footer must still account for them, or the
/// counts silently stop summing (FR-013, FR-038).
#Preview("All processes — measurable only") {
    AllProcessesPreviewHost(initialShowsUnmeasurable: false)
        .frame(width: 720, height: 520)
}

/// A search that matches nothing. This must never read as "nothing is running" —
/// the defect `TASK-65.16` exists for.
#Preview("All processes — search matches nothing") {
    AllProcessesPreviewHost(initialQuery: "zzzznomatch")
        .frame(width: 720, height: 520)
}
#endif
