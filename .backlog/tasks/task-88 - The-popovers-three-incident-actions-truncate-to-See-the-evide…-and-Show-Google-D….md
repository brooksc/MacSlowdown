---
id: TASK-88
title: >-
  The popover's three incident actions truncate to "See the evide…" and "Show
  Google D…"
status: In Progress
assignee: []
created_date: '2026-08-24 04:03'
updated_date: '2026-08-24 04:25'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on screen by the product owner, 2026-08-23, who noted it did not happen before — which is consistent with the cause.

`MenuBarContentView.incidentActions` (`MacSlowdown/Sources/MenuBarContentView.swift:480`) puts three controls in one `HStack` inside a fixed-width popover: "See the evidence", the Show-target button, and the Mute menu. The Mute menu carries `.fixedSize()`, so it is guaranteed its intrinsic width and the other two absorb the entire shortfall. Observed: "See the evide…" and "Show Google D…".

TASK-65.21 added the third action (the design 1b action row) and its criteria were checked against tests, not against a running popover. This is the regression that introduced.

Design 1b is the reference for what the row should look like. Options include wrapping to two rows, shortening the primary to "See evidence", letting only the Show button truncate, or giving the Show button a `truncationMode` that keeps the application name legible — the name is the informative half of "Show Google Drive", so truncating it at the end is the worst of the available choices (FR-002's rule against showing a fragment as if it were the name is the same family of concern).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 At the popover's real width, no action button label is truncated in the default case
- [ ] #2 Where an application name is long enough that something must give, the application name remains identifiable and the fixed vocabulary gives way first
- [x] #3 The row is checked against design 1b
- [ ] #4 Verified on screen at the popover's real width with a long application name and a short one
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The three controls are extracted to `evidenceButton`, `showButton` and `muteMenu`, and the row is wrapped in `ViewThatFits(in: .horizontal)` offering design 1b's single row first and a two-row fallback second — the prominent action on its own line, then Show and Mute beside each other.

**All three now carry `.fixedSize()`, which is the part that makes it work.** Previously only Mute did, so the other two were willing to truncate and a layout that "fits" only because a label agreed to shrink is not a fit — `ViewThatFits` would have chosen the single row every time and reproduced the defect. With every child at its intrinsic width the first layout genuinely does not fit, and the fallback is taken.

Design 1b's row is preserved wherever it is honestly available: it shows "Show Xcode", which fits. "Show Google Drive" is what did not, and it now costs a line rather than its own name — satisfying AC #2 by never truncating the name at all rather than by choosing a truncation mode.

**Not verified on screen (AC #1, #2, #4).** `ViewThatFits` decides at layout time and no test can see which layout it chose; this needs the popover open at its real width with a long application name and a short one. The mechanism is sound but the result is exactly the class of claim CLAUDE.md forbids inferring from a green test.
<!-- SECTION:NOTES:END -->
