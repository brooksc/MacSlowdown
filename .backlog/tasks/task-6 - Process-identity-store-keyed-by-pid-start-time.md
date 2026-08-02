---
id: TASK-6
title: 'Process identity store keyed by (pid, start time)'
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:24'
labels:
  - core
milestone: m-1
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
- [ ] #4 Identity resolved once per process lifetime, never per-sweep
- [ ] #5 Both signature and path identity recorded per process
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Settled by the TASK-3 spike:

- Identity resolution (proc_pidpath + SecCodeCopyGuestWithAttributes) costs
  ~760ms for a full sweep, ~400x the 1.8ms metrics sweep. It is the dominant
  cost in the system.
- Therefore: resolve identity ONCE per process lifetime, keyed by
  (pid, p_starttime), and cache. The per-sweep hot path must touch only sysctl
  enumeration + PROC_PIDTASKALLINFO.
- Store both identity sources so a policy survives one becoming unavailable:
  teamID+bundleID (stable across app updates, available for 810/1063 sandboxed)
  and outermost .app path (available for 1042/1063, unaffected by sandbox).
<!-- SECTION:PLAN:END -->
