---
id: TASK-5
title: 'Build metrics sampler: sysctl enumeration + PROC_PIDTASKALLINFO'
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:07'
labels:
  - core
milestone: m-1
dependencies:
  - TASK-4
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the validated probe approach into the app. Enumerate via sysctl KERN_PROC_ALL; per-process metrics via PROC_PIDTASKALLINFO (one syscall instead of two).

MUST scale CPU times by mach_timebase_info -- they are mach ticks, not nanoseconds, and omitting this under-reports CPU by ~42x on Apple Silicon.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Synthetic single- and dual-core workloads read accurately vs ps (FR-004 acceptance criteria)
- [ ] #2 CPU derived from deltas of monotonic counters, never cumulative totals
- [ ] #3 Denied processes labeled unavailable, not omitted silently (FR-002)
- [ ] #4 Sweep cost stays within FR-030 budget at 2s cadence
<!-- AC:END -->
