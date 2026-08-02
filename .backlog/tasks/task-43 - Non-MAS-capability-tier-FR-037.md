---
id: TASK-43
title: Non-MAS capability tier (FR-037)
status: Parked
assignee: []
created_date: '2026-08-02 01:07'
labels:
  - parked
  - non-mas
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PARKED per explicit product decision -- anything outside MAS is on hold.

Measured value if resumed:
- Unsandboxed Developer ID alone restores only proc_pid_rusage (footprint, per-process disk I/O, wakeups). It does NOT close the attribution gap -- system process visibility is byte-identical to sandboxed.
- Only a root-privileged helper closes the gap: verified 0/1058 denied under root vs 338/1058 sandboxed.

Requires a separate approved specification per FR-037.
<!-- SECTION:DESCRIPTION:END -->
