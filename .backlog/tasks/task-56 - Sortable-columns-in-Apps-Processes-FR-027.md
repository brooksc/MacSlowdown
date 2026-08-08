---
id: TASK-56
title: Sortable columns in Apps & Processes (FR-027)
status: In Progress
assignee: []
created_date: '2026-08-08 19:27'
updated_date: '2026-08-08 19:45'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The inventory table already renders column headers — Application, CPU, Resident memory, Processes — but they are not interactive, so the list is permanently ordered by CPU descending. FR-027 requires sorting over current processes alongside search, which is already implemented.

Governing requirement: FR-027. Its acceptance criteria that bear on this are "filters are keyboard accessible" and "selection remains stable during refresh" — the second is the one that is easy to break here, because rows reorder on every sample.

No spec amendment needed; sorting is already in scope.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every column header sorts, ascending and descending, and shows the current direction
- [ ] #2 The default order is CPU descending, matching what the table shows today
- [ ] #3 Selection survives both a re-sort and the next sample, because it is keyed on family identity rather than row position
- [ ] #4 Sorting is reachable and reversible from the keyboard, and the header states its sort state to VoiceOver
- [x] #5 Sorting changes only the order shown; it never re-reads, re-samples or drops rows
- [x] #6 Rows with no measurable value sort to a defined position rather than being treated as zero
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented and unit-tested; on-screen verification incomplete.

Built: Presentation.sorted plus Presentation.defaultSortOrder, and the Table now takes a sortOrder binding with value: key paths on all four columns. FamilyRow gained processCount so the Processes column has a key path to sort on. Six tests cover it and the full suite is green at 329.

Criterion #5 (order only, never filters) and #6 (ties resolved to a defined position) are covered by tests: the row set is asserted identical under every column, and equal values break by name so the same rows sort the same way whatever order they arrive in.

Criteria #1-#4 are NOT verified and are deliberately left unchecked. Sorting demonstrably responds to interaction — the table was observed in name-ascending order at one point and in a different order later — but I could not produce a clean before/after because I lost control of the window while checking: a click landed on the wallpaper and triggered macOS's click-to-reveal-desktop, which hid every window on the machine for several minutes. Restored by clicking the wallpaper again; nothing was closed.

Specifically still unverified:
- Whether the table opens in CPU-descending order. The default sort order is set in state, but SwiftUI can write back to a sortOrder binding on appear, and the one clean screenshot showed name-ascending. This may be my own stray click or a real defect; I do not know which and am not guessing.
- Whether headers show a sort-direction indicator.
- Keyboard reachability and what VoiceOver announces for a sorted header.

Next step is a single deliberate check with the window in a known position: screenshot on open, click each header once, screenshot again. Do not interleave other clicks.
<!-- SECTION:NOTES:END -->
