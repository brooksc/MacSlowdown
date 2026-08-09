---
id: TASK-67
title: >-
  AppKit logs a reentrant NSTableView delegate warning every ~2 s, and says it
  will become an assert
status: To Do
assignee: []
created_date: '2026-08-09 03:35'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed while investigating TASK-51.1, in a file that session did not own. Not investigated.

The running app logs an AppKit warning about a **"reentrant operation in its NSTableView delegate"** roughly every 2 seconds. The source is the inventory table (`ProcessInventoryView`), not the incidents pane. AppKit's own message states that this will become an assertion in a future release — so today it is noise, and at some macOS version it becomes a crash.

Every ~2 seconds is the sampling cadence, so the likely shape is that a sweep mutates the table's data while AppKit is inside a delegate callback for the previous update. SwiftUI's `Table` is `NSTableView`-backed, which is how a SwiftUI view produces an AppKit warning.

Worth knowing before starting: TASK-56 (sortable columns), TASK-60 (parent grouping), TASK-61 (expandable tree) and TASK-65.4 (inspector, adds a selection binding and per-family history recording) have all changed this table. TASK-65.4's work is on an unmerged branch, so reproduce against the merged state rather than against `main` alone.

Two reasons this is worth doing sooner than its severity suggests: a warning at 2-second intervals is drowning the log for anything else diagnosed from it, and the whole product depends on a table that updates continuously — this is the one control we cannot afford to have an assertion in.

Do not silence the warning. Find what reenters.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The reentrancy is reproduced and its trigger identified, against the merged state of the inventory table rather than main alone
- [ ] #2 The warning no longer appears in the log during sustained normal operation, verified by watching the log across several sampling cycles rather than by a single check
- [ ] #3 The fix addresses the reentrant call itself -- suppressing, delaying or silencing the warning is not acceptable
- [ ] #4 Table behaviour is unaffected: sorting, expansion, selection and continuous updates all still work, verified on screen
- [ ] #5 If the cause turns out to be a SwiftUI Table limitation rather than our own code, that is recorded with evidence and the options are stated rather than worked around silently
<!-- AC:END -->
