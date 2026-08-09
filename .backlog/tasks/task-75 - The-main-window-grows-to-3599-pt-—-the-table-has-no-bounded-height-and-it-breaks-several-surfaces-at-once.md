---
id: TASK-75
title: >-
  The main window grows to 3599 pt — the table has no bounded height, and it
  breaks several surfaces at once
status: To Do
assignee: []
created_date: '2026-08-09 18:33'
labels:
  - ui
milestone: m-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by the product owner and measured on screen 2026-08-09, macOS 27, built Debug app.

**`Apps & Processes` makes the window 1300 x 3599 points on a 1107-point-tall screen.** Measured via the accessibility API while the window was open. Setting the window to 860 pt high does not stick — it springs back, because the content is forcing the size.

The inventory `Table` is laid out at its full intrinsic height for ~720 rows rather than being given a bounded frame and scrolling internally. The window resizes to fit it.

## This is one cause with several symptoms

All of these were reported or observed together, and all follow from the geometry:

1. **The list cannot be scrolled.** There is no scroll view to scroll — the window itself is enormous and the user sees a slice of it.
2. **Column headers are cut off and not pinned.** They are at the top of a 3599 pt layout, above the visible slice.
3. **The sidebar disappears.** It is inside the same over-tall window. Collapsing and re-expanding does not bring it back, because the sidebar's state is not what is wrong.
4. **The segmented control, search field and census footer are unreachable** for the same reason. Screen 1m's "Show unmeasurable" toggle and the "N of M processes belong to an app" footer cannot be seen.
5. **Very probably the blank Incidents pane (TASK-51.1).** `ContentUnavailableView` centres itself vertically. In a detail column thousands of points tall, the empty state sits roughly 1800 pt below the fold and the unconditional `Divider` and footer sit at the very bottom — all outside the visible area. That matches every observation: the title and toolbar render (they belong to the window), the body appears empty, and the *unconditional* elements are missing too.

## Why two investigations missed it

TASK-51.1 found the persisted `NSSplitView` frames recording a 6020 pt height and tested precisely this hypothesis — but tested it in an offscreen `NSHostingView`, where SwiftUI clamped to the given size, and recorded "SwiftUI clamps. Hypothesis dead." The mechanism was right; the venue was wrong. **A hosting view constrains height in a way a real `Window` scene does not.**

That is the durable lesson here: an offscreen render harness cannot answer a question about window sizing, because the harness supplies the size.

## What to check

- Give the table a bounded frame so it scrolls internally instead of growing the window.
- Confirm the window then honours a set size and stops springing back.
- Re-check the Incidents pane immediately afterwards, before doing anything else to it — if this fixes it, TASK-51.1's remaining criteria close and the `.inspector` suspicion is dropped rather than pursued.
- Check whether the persisted `NSSplitView Subview Frames` / `NSWindow Frame main` entries in the container carry a bad size forward across launches, and whether a fresh container behaves differently. A saved 6020 pt frame may make this worse or make it appear to persist after a fix.
- Watch for interaction with TASK-74's ordering damping: fewer row moves will not help if the height is unbounded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The main window no longer resizes itself to the content height; a window set to a given size keeps it, verified by measuring the window on screen
- [ ] #2 The inventory scrolls internally, and its column headers stay visible while scrolling
- [ ] #3 The sidebar remains visible when switching to Apps & Processes, and collapse/expand works
- [ ] #4 The segmented control, search field and census footer are reachable without resizing the window
- [ ] #5 The Incidents pane is re-checked immediately after this fix and the result recorded on TASK-51.1, whichever way it goes
- [ ] #6 Behaviour is checked against both an existing container with persisted window frames and a fresh one
<!-- AC:END -->
