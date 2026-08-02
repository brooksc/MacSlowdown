---
id: TASK-12
title: 'Process inventory view with search, filter, sort (FR-002, FR-027)'
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:51'
labels:
  - ui
milestone: m-1
dependencies:
  - TASK-5
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Top consumers agree with a reference tool within tolerance
- [x] #2 Stale or unavailable values labeled
- [x] #3 Search case-insensitive; filters keyboard accessible; selection stable during refresh
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ProcessInventoryView: a Table of application families with aggregated CPU and resident memory, plus search.

- AC#1 Agreement with a reference tool is covered by the CPUWorkloadTests suite, which cross-checks a synthetic spinner against `ps -o %cpu` for the same pid. Verified against the live system too: the running app grouped Helium into 23 processes and ChatGPT into 16, with daemons listed individually.
- AC#2 Unavailable values are labeled rather than blank or zero: families show a "N not measurable" count, and a family with no readable memory shows an em-dash rather than 0. The footer states that resident memory differs from Activity Monitor's footprint column, and that per-app disk activity is unavailable to App Store apps.
- AC#3 Search is case-insensitive via localizedCaseInsensitiveContains and is a standard .searchable field, so it is keyboard reachable. Selection is keyed by family id -- bundle path, or pid plus start time for a standalone process -- not by row index. Rows reorder every sample as usage changes, so an index-based selection would jump to a different application on each refresh.

Uncertain groupings surface as a question-mark affordance with an explanatory help string, which showed up correctly on the live system for ChatGPT and Helium.
<!-- SECTION:NOTES:END -->
