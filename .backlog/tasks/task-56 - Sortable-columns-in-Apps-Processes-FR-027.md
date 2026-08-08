---
id: TASK-56
title: Sortable columns in Apps & Processes (FR-027)
status: In Progress
assignee: []
created_date: '2026-08-08 19:27'
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
- [ ] #5 Sorting changes only the order shown; it never re-reads, re-samples or drops rows
- [ ] #6 Rows with no measurable value sort to a defined position rather than being treated as zero
<!-- AC:END -->
