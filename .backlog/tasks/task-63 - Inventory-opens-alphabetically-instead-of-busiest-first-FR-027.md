---
id: TASK-63
title: Inventory opens alphabetically instead of busiest-first (FR-027)
status: Out of Scope
assignee: []
created_date: '2026-08-09 01:43'
updated_date: '2026-08-09 02:27'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Apps & Processes table sorts correctly when a heading is clicked, but it opens ordered by name ascending rather than CPU descending. That is close to useless as a first impression: the point of the surface is "which application is using the most", and the first screen is an alphabetical list of daemons at 0.0%.

Cause: SwiftUI's Table overwrites its sortOrder binding with its first sortable column during layout. Four approaches were tried and none survived, each verified on screen rather than inferred:

1. @State initialised to the default comparator — overwritten.
2. .onAppear reassignment — overwritten.
3. .task reassignment, which runs after layout — overwritten.
4. Deriving an effective order from a "has the user clicked yet" flag, treating the first onChange as the framework's own write — the framework appears to write more than once during layout, so the flag was set before any user action.

Untried options, roughly in order of preference:
- Make the CPU column the first sortable column and check whether the automatic default is ascending or descending. Free if descending; wrong in a different way if ascending.
- Drop the sortOrder binding and drive ordering from our own state with a custom header. More code, fully deterministic.
- Sorting the data so the alphabetical comparator happens to produce the wanted order — rejected, it would make the header arrows lie.

Do not fix this by removing sorting from the Application column just to change which column is first. Sorting by name is genuinely useful on a table this long.

The ordering logic itself is correct and unit-tested (Presentation.sortedInventory, defaultInventorySort). This is only about which order the view starts in.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The inventory opens with the busiest application first, verified on screen and not only in a test
- [ ] #2 Clicking any heading still sorts that column both ways, and the arrow reflects the real order
- [ ] #3 The fix does not make a header arrow disagree with the order actually shown
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Observation from a screenshot session on macOS 27 (built Debug app, no code changes): the inventory opened sorted **CPU-descending**, not alphabetically. `screenshots/03-apps-processes.png` shows System processes 114%, MacSlowdown 39%, iconservicesagent 27%, then descending — with the sort chevron on the CPU column.

The window was opened via the popover's 'Open MacSlowdown' button on a fresh launch, so this was the first render of the view, not a state left over from a manual sort. That is the opposite of what this task describes.

Do not read this as fixed. It may be state-dependent (the container preferences carry an `NSSplitView`/window frame from earlier sessions, so other view state may persist too), or it may differ between a cold first-ever launch and a returning one. Worth reproducing from a clean container before spending effort on the untried approaches listed above — if it already sorts correctly on a fresh profile, the remaining problem is narrower than the task assumes.

Fifth approach tried and reverted: temporarily moving the CPU column to the front, to test whether SwiftUI installs the *first* column's comparator.

Evidence, not proof, because I could not get the table scrolled cleanly to the top: with CPU first, the rows at the top of the list all read 0.0%. If SwiftUI had installed CPU descending, the busiest would have been there. That is consistent with the framework installing 'first sortable column, ASCENDING'.

If that reading is right it kills the cheapest option: making CPU the first column would open the inventory least-busy-first, which is wrong in a more confusing way than alphabetical. Someone should confirm it before relying on it — 30 seconds with the window scrolled to the top settles it.

Reverted, because the Application column should lead the table and I was not willing to trade the layout for a partial answer.

That leaves option 2 from the description: drop the sortOrder binding and drive ordering from our own state with a custom header. Fully deterministic, more code. It is the option I would take next.

Also worth recording for whoever picks this up: the ordering logic is already correct and covered by tests (Presentation.sortedInventory, defaultInventorySort, and the sorting suite in InventoryTreeTests). Nothing about the data layer needs to change — this is entirely about which order the view starts in.

Attempting to read the table through the accessibility API to avoid screenshot archaeology returned nothing: SwiftUI's Table did not expose rows or static text to System Events traversal. Worth knowing before trying the same shortcut.

NOT A DEFECT. I misdiagnosed this, and the parallel session's screenshot (screenshots/03-apps-processes.png) settles it: the table opens CPU-descending, with the sort chevron on the CPU column — System processes 145%, MacSlowdown 47%, 2.1.220 25%, TerminalApp 6.5%, descending from there.

What I actually saw: the alphabetical tail of a correctly sorted list. Ties break by name, and the great majority of the table sits at 0.0%, so everything below the busy rows is in name order by design. Every screenshot I took had the window scrolled into that tail — the saved window frame put the viewport there and the column headers were above the visible area, so I never saw the chevron that would have told me immediately.

Fifteen consecutive rows reading 0.0% in alphabetical order is exactly what a correct sort looks like from that position. I read it as a broken default and never checked the header.

Consequences worth owning:
- Four 'fixes' were written and reverted for a problem that did not exist: @State reassignment, .onAppear, .task, and an onChange heuristic. None were needed. All are reverted; the committed code is the original simple binding.
- The fifth experiment, moving the CPU column first, was also unnecessary. Its 'evidence' that SwiftUI installs the first column ascending is unreliable for the same reason — I was reading the 0.0% tail again. Disregard that note.

Lesson for next time, and the reason this is worth writing down: when judging a sorted list from a screenshot, check the header chevron and confirm the viewport is at the top. A scrolled view of a tie-broken tail is indistinguishable from a wrong sort.

Closing as out of scope rather than done, since nothing needed doing.
<!-- SECTION:NOTES:END -->
