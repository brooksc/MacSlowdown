---
id: TASK-97
title: The Now and Apps tables may not fit the window's minimum width
status: Done
assignee: []
created_date: '2026-08-31 16:45'
updated_date: '2026-09-17 18:23'
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
- [x] #1 The main window is resized to its minimum and both tables are looked at — the Now pane and Apps & Processes
- [x] #2 The application name stays legible at minimum width, or the window's minimum is raised so it cannot reach a width where it is not
- [x] #3 The Apps inspector's fixed 340 pt frame is checked against the table's column minimums at that width
- [x] #4 Rechecked with a long application name present, since that is the case that breaks first
- [x] #5 The fix is chosen after looking, not derived from the column arithmetic
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Measured by looking, 2026-09-17, exactly as the task insisted.** Every figure below came from a render at a stated width; nothing was derived from the column arithmetic, and the arithmetic turned out to be the *less* interesting half.

**Both tables were broken, and worse than the review predicted.** The review expected truncation and compression. What the renders showed was silence:

| Table | Before | After |
|---|---|---|
| All processes | **blank** below ~560 pt — no header, no rows, no footer | draws at 480 pt and at 140 pt, scrolling |
| Now / Overview contributors | **blank** at 480 pt; name crushed to *nothing* at 620 pt | draws at 480 pt, names whole |

The Now table had never been looked at narrow at all. It is a hand-built grid, so unlike `Table` nothing negotiated a minimum on its behalf — which is TASK-117's defect in a place TASK-117 did not reach. Fixed under TASK-118: `contributorTableMinimumWidth` is declared at 610 pt, carried by the header and the rows, and the table scrolls sideways below it.

**#2 — the name stays legible.** At 480 pt the Now table shows "Brave Browser", "MacSlowdown", "System processes" and "com.apple.WebKit.WebContent.Development" in full, each on one line (`previews/now-table-480.png`). The name keeps a 96 pt floor and the qualifiers beside it truncate first; nothing in the cell is `fixedSize`, which was the thing starving it. All processes at 480 pt shows every name whole (`previews/all-processes-480.png`).

**#3 — the inspector's 340 pt frame, measured at the width it actually leaves.** At the window's 480 pt minimum the table gets about **140 pt**, against column minimums summing to ~504. The question was what `Table` does below its own minimums, and TASK-117 is why it could not be answered on paper. Rendered at exactly 140 pt: it **draws and scrolls** — headers, five rows, the unmeasurable section header — rather than going blank. So the pane at its narrowest is cramped and usable, not broken, and the inspector needs no width change.

That render did expose a second thing: the All processes footer wrapped to sixteen lines at 140 pt and left room for **two rows**. A footer that crowds out the table it explains has stopped explaining anything. Compressed to one sentence with the rest behind a disclosure, the same shape TASK-65.22 settled for the Apps footer, and the memory caveat there — which was a verbatim second copy of `InventoryCensus.residentMemoryCaveat` — now reads the constant.

**#5 — the fix was chosen after looking, and changed twice because of it.** The first attempt at the name cell (`fixedSize` on the qualifiers) read as correct and produced a row with no name on it at 620 pt. Only the render showed that. The task's instruction not to fix this from the arithmetic was right, and for a sharper reason than it gave.

**Not verified**: the *running* window resized by hand to its minimum. These are renders at stated widths, which is what answers a layout question; what they cannot answer is whether AppKit lets the window reach 480 pt at all with the current sidebar. `MainWindowView` sets `minWidth: 480` on the detail column, so 480 is the floor the renders were aimed at.
<!-- SECTION:NOTES:END -->
