---
id: TASK-117
title: 'All processes renders completely blank below ~560 pt — not degraded, blank'
status: Done
assignee: []
created_date: '2026-09-16 02:36'
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
**Found by looking, 2026-09-15** — the first time this screen has ever been seen. Rendered offscreen through Xcode 27's `RenderPreview` MCP tool from `MacSlowdown/Sources/AllProcessesPreviews.swift`, so no display was taken over to find it.

Narrow the All processes view and the table does not degrade, reflow, or clip. It draws **nothing at all**: no column headers, no rows, no unmeasurable section, no census footer. An empty window with a title bar.

Measured by bracketing, same data and same height (480 pt) in every case, width the only variable:

| Width | Result |
|---|---|
| 720 pt | draws |
| 640 pt | draws |
| 580 pt | draws — but the last row is clipped under the footer |
| 540 pt | **blank** |
| 504 pt | **blank** |

So the edge is between 540 and 580 pt.

**Why this matters more than it looks.** TASK-97 records that the four-column change cut the Apps table's minimum from ~644 pt to ~504 pt, and asks whether the tables fit the window's minimum width — with the instruction to measure rather than assume. Measured: at a width the window is now allowed to reach, this screen shows the user nothing. A blank pane is indistinguishable from a broken app, and it is silent — no error, no empty state, no log line.

It is also the worst possible failure for *this* product specifically. The screen's stated job is to be honest about the two thirds of the process table an application-grouped list cannot show. Showing nothing is not honest; it reads as "there is nothing here", which is the same defect class as TASK-65.16 (empty search must never imply nothing is running).

**Likely cause, unconfirmed.** `Table` with five columns whose widths do not compress. At 580 pt the columns are already at their floor and the name column is down to ~14 characters; below that the table appears to give up entirely rather than clip. Worth checking whether a `min`/`ideal`/`max` width on `TableColumn` changes the behaviour, and whether the row content's `fixedSize` interacts here the way it did in TASK-75 — that defect was also a SwiftUI sizing negotiation producing an absurd answer rather than a visible error.

**Related but distinct, seen in the same renders** (file separately if they do not fall out of the fix):

- The **Process column is starved while numeric columns are oversized**. At 720 pt, "CPU" holds a three-character value in roughly the same width as the name column, and names truncate at ~20 characters: "Brave Browser Hel…", "com.apple.WebKit…", "containermana…". Subtitles truncate too. This is the visible cause of TASK-65.22's truncated names.
- The **footer is four lines**, where design 4 calls for one. Better than the seven recorded in TASK-65.22, still not one.
- The unmeasurable section's own explanatory sentence truncates mid-word: "They sort to the end…".

**What the renders confirm is right**, so a fix does not regress it: unmeasurable rows say "Not measurable" in both numeric columns rather than showing zeros; they carry a lock glyph *and* text, so the state is not conveyed by colour alone; and the census sums honestly (681 measurable + 286 not = 967 total, "only 145 belong to an app").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 At 504 pt — the window's currently allowed minimum — the All processes table draws its headers, rows, unmeasurable section and census footer
- [x] #2 The width at which the table stops drawing is either eliminated, or the window's minimum width is raised above it so the state is unreachable
- [x] #3 No width between 400 pt and 1200 pt produces a blank pane; if content must be dropped when narrow, something is shown that says so rather than nothing
- [x] #4 A rendered preview is attached or its path recorded for the narrow case, so the fix is verified by looking and not by inference
- [ ] #5 The Process column gets the width, relative to the numeric columns, that the design's hierarchy calls for — or that is split out as its own task with the renders attached
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Verified by looking, 2026-09-17.** The fix landed in 4653c88 (every `TableColumn` states min/ideal/max, minimums summing to 448 against the window's 480 pt floor) but the task was never closed. Re-rendered at the width that used to be blank: `design/verified/2026-09-17/previews/all-processes-480.png` shows headers, all five measurable rows, the "3 processes we can't measure" section and the census footer, with "Not measurable" written in full rather than truncated to a fragment. AC#1–#4 met.

AC#5 (the Process column's share of the width relative to the numeric columns) is **split out rather than claimed**: names that previously cut at ~20 characters now show whole at 480 pt — "Brave Browser Helper (Renderer)" in full — which is the substance of it, but the footer is still three lines where design 4 calls for one. That remainder belongs to TASK-65.22 and is tracked there.

The same defect class was then found in the **Now** table, which is a hand-built grid and so had nothing negotiating a minimum on its behalf: blank at 480 pt, and the name column crushed out of existence at 620 pt. Fixed under TASK-118.
<!-- SECTION:NOTES:END -->
