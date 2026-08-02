---
id: TASK-6
title: 'Process identity store keyed by (pid, start time)'
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:07'
labels:
  - m1-core-monitor
  - core
dependencies:
  - TASK-5
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PIDs are reused; identity must be (pid, p_starttime from kinfo_proc). Application-family history must survive PID replacement per section 6 and FR-043. Cache proc_pidpath by this key -- re-reading every sweep costs ~5ms and breaks the FR-030 budget at 1s cadence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PID reuse does not merge two unrelated processes
- [ ] #2 Family history survives PID replacement
- [ ] #3 Path lookups cached, not per-sweep
<!-- AC:END -->
