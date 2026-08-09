---
id: TASK-63
title: Inventory opens alphabetically instead of busiest-first (FR-027)
status: To Do
assignee: []
created_date: '2026-08-09 01:43'
updated_date: '2026-08-09 01:43'
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
