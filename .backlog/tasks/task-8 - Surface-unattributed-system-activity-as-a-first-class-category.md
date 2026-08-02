---
id: TASK-8
title: Surface unattributed system activity as a first-class category
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:07'
labels:
  - core
milestone: m-1
dependencies:
  - TASK-5
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Direct consequence of the Tier 0 finding: ~40 percentage points of busy CPU cannot be attributed to any visible process, because other-uid processes (WindowServer, mds_stores, backupd, coreaudiod, launchd) are denied.

Contributor lists must never silently fail to sum. Show the remainder explicitly as unattributed system activity. This is what FR-038 evidence classification and FR-013 confidence labeling exist for.

Note users may compare against Activity Monitor, which sees everything via a privileged helper (sysmond).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Aggregate CPU minus attributed CPU is displayed, never hidden
- [ ] #2 Copy explains the limitation without overstating causation (FR-013, FR-036)
- [ ] #3 Classified as measured fact vs derived per FR-038
<!-- AC:END -->
