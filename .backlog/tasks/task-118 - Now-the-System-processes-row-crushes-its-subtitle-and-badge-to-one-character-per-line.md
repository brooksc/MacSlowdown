---
id: TASK-118
title: >-
  Now: the System processes row crushes its subtitle and badge to one character
  per line
status: Done
assignee: []
created_date: '2026-09-17 02:30'
updated_date: '2026-09-17 18:00'
labels:
  - ui
milestone: m-1
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Seen on screen 2026-09-16**, in the real running app on macOS 26.6.2 in a VM — not a preview, not inferred from a test.

On the **Now** screen, the app table's "System processes" row renders its subtitle and its badge as near-vertical text, roughly one to three characters per line:

```
>  🔒  Sy…   286      Ca
              pro-     n't
              cess-    be
              es       bro
                       ken
                       do
                       wn
```

The name truncates to "Sy…", "286 processes" stacks as `286 / pro- / cess- / es`, and the "Can't be broken down" badge stacks as `Ca / n't / be / bro / ken / do / wn`. The row becomes several times the height of an ordinary row as a result, and it is the second row on the app's primary screen.

**This is the TASK-75 failure mode again.** There, a `NavigationSplitView` proposed no width, caption text under `fixedSize(horizontal: false, vertical: true)` wrapped to about one word per line, and the view answered with a height in the thousands of points. Same shape here: a cell is being offered almost no width, and text that is allowed to grow vertically takes the offer. The fix is likely the same family — give the name column a real minimum width, and stop the subtitle and badge from being compressible to nothing.

Worth checking whether this is the same root cause as [[TASK-117]], which was the All processes table drawing nothing at all below ~560 pt because **no column declared a width**. The Now table's columns should be audited the same way: Now, Last minute, Resident memory, Retained history and Age are all present and none was checked.

**Why it was not caught earlier.** The row only appears when there is an unmeasurable aggregate to show, and it needs a live machine with other-uid processes — so no unit test constructs it, and the previews added so far cover `AllProcessesView` rather than the Now table.

Screenshot: `02-now.png` from the 2026-09-16 VM capture run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The System processes row on Now renders its name, its process count and its badge on single lines at the default window size
- [x] #2 The row's height matches an ordinary app row rather than expanding to fit vertical text
- [x] #3 Every column in the Now table declares a width, as the All processes table now does after TASK-117
- [x] #4 Checked at the window's 480 pt minimum as well as the 900 pt default, and neither produces vertical text or a blank table
- [x] #5 Verified by looking — a rendered preview or a VM screenshot is attached, not a passing test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Fixed and seen, 2026-09-17.** Renders in `design/verified/2026-09-17/previews/`.

**Root cause, and it was two faults stacked.** The row is a hand-built `HStack`, and the name, the process count, the badges and the trailing `Spacer` were all loose siblings competing for one pool of width. The Spacer won, the texts were offered almost nothing, and text allowed to grow vertically took the offer — the TASK-75 failure mode exactly.

First attempt grouped name+count+badges and gave the group `layoutPriority(1)` over the Spacer, with `fixedSize()` on the count and badges to stop them wrapping. That fixed the vertical text but produced a worse defect, which only showed up because the fix was **rendered rather than assumed**: `fixedSize` is rigid at any layout priority, so the qualifiers took their ideal widths first and the name was compressed to nothing — at 620 pt the System processes row rendered as a lock, "286 processes" and an *empty pill*, with no name on it at all.

The shipped arrangement uses no `fixedSize` anywhere in the cell. Everything is `lineLimit(1)`, which is what actually forbids the wrapping; the ranking is done with layout priority plus a 96 pt floor on the name. A badge may truncate; a row may not lose its name.

**AC#3 uncovered a second, larger fault.** Auditing the columns as instructed: the four numeric columns do declare widths, but nothing declared a minimum for the *table*, so below ~560 pt it drew **completely blank** — TASK-117's defect, in the other table, never previously looked at. `contributorTableMinimumWidth` (610 pt) is now declared and both the header and the rows carry it, and the table scrolls horizontally below that rather than compressing — the same trade TASK-117 settled for All processes.

**AC#4 measured at both ends.** 480 pt: names in full, one line each, ordinary row height, numeric columns reached by scrolling, no blank pane (`now-table-480.png`). 900 pt: everything visible (`now-table-900.png`). The worst cell the product can produce — a count *and* two badges — also renders on one line (`now-table-two-badges.png`).

One fixture note worth keeping: the first preview set `isMeasurable: false` on the system aggregate and was wrong. `InventoryRow.tree` builds it `true`, because FR-055's total is a measured difference between host busy and everything we could read. The corrected fixture matches the tree; the false case is kept as a separate stress preview.

The fix reaches Overview as well, which draws the same table through the same two views.
<!-- SECTION:NOTES:END -->
