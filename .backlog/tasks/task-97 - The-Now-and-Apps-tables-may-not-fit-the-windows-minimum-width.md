---
id: TASK-97
title: The Now and Apps tables may not fit the window's minimum width
status: To Do
assignee: []
created_date: '2026-08-31 16:45'
updated_date: '2026-08-31 16:45'
labels:
  - ui
milestone: m-3
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review finding 15 of TASK-96, and the only one of the 27 that could not be settled from the code. **It has since got worse by my own hand**: I added a "Last minute" column to the Now table (finding 13) and reserved the age cell unconditionally (finding 14) after the arithmetic below was done, so the real figure is now higher than the review's.

The review's arithmetic, as written: the Now contributor row's fixed cells total 400 pt (464 with the age column), plus 24 pt padding, plus roughly nine inter-element gaps at 8 pt, plus icon, chips and process count — before the name gets a single point. The detail column's `minWidth` is 480. At or near minimum width the name (`lineLimit(1)`) truncates to nothing and the numeric columns compress.

The same shape in Apps & Processes: `InventoryTable`'s column minimums total about 560 and the inspector is a hard `.frame(width: 340)`, so that pane wants roughly 900 pt in a window whose minimum is about 680.

This is the family TASK-88 and TASK-75 came from, and it is the reason the geometry cannot settle it: SwiftUI's actual behaviour at the boundary is what matters, and the last time this project reasoned about a width from the code it was wrong about the cause for an hour — TASK-75, where the window grew to 3599 pt for a reason nobody predicted and the row count turned out to be irrelevant.

**Do not fix this from the arithmetic.** Resize the window to its minimum, look, then decide. The likely answers are a larger `minWidth` on the detail column, dropping a column below some width, or letting the name wrap — but which one is a design judgement that needs the screen in front of you.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The main window is resized to its minimum and both tables are looked at — the Now pane and Apps & Processes
- [ ] #2 The application name stays legible at minimum width, or the window's minimum is raised so it cannot reach a width where it is not
- [ ] #3 The Apps inspector's fixed 340 pt frame is checked against the table's column minimums at that width
- [ ] #4 Rechecked with a long application name present, since that is the case that breaks first
- [ ] #5 The fix is chosen after looking, not derived from the column arithmetic
<!-- AC:END -->
