---
id: TASK-41
title: Per-process wakeups and sleep-prevention (FR-048)
status: Parked
assignee: []
created_date: '2026-08-02 01:07'
labels:
  - parked
  - blocked-by-sandbox
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PARKED: proc_pid_rusage is fully blocked under App Sandbox (verified 1/1058, self only), so ri_interrupt_wkups is unobtainable. Spec instruction is to omit rather than approximate. Revisit only if the distribution model changes.
<!-- SECTION:DESCRIPTION:END -->
