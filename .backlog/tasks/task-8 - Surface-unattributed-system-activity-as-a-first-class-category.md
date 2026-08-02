---
id: TASK-8
title: Surface unattributed system activity as a first-class category
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 02:10'
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
- [ ] #4 Unattributed bucket lists which protected processes were running in the window, as measured fact, distinct from the unapportionable CPU total
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Design review finding: we can NAME every running process even when we cannot MEASURE it. sysctl KERN_PROC_ALL returns p_comm, uid, ppid and start time for all 1063 processes regardless of ownership; proc_pidpath resolves 1042/1063 and code signing 212/338 other-uid. Only CPU and memory are denied.

So the unattributed bucket should not be an anonymous blob. We can state as MEASURED FACT which protected processes were running during an incident window, and when they started and exited (FR-045). 'Time Machine (backupd) was running for the whole window' is a measured observation even though its CPU share is not.

This turns the hard case from 'we cannot tell you anything' into 'here is exactly what was running, and here is why we cannot apportion it' -- a materially better product for the ~40% of incidents that land here.
<!-- SECTION:PLAN:END -->
