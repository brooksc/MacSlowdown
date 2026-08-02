---
id: TASK-19
title: Aggregate disk I/O only -- per-process is blocked (FR-009)
status: To Do
assignee: []
created_date: '2026-08-02 01:07'
labels:
  - m2-incident-diagnosis
  - core
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rescoped by the Tier 0 probe: proc_pid_rusage is fully blocked under sandbox, so per-process I/O deltas are unobtainable. The spec permits omitting per-process detail in restricted builds. Aggregate throughput only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cumulative bytes never mislabeled as current rate
- [ ] #2 Absence of per-process attribution stated explicitly
<!-- AC:END -->
