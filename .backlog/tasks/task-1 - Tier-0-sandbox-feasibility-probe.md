---
id: TASK-1
title: Tier 0 sandbox feasibility probe
status: Done
assignee: []
created_date: '2026-08-02 01:05'
updated_date: '2026-08-02 01:27'
labels:
  - spike
milestone: m-0
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Determine whether per-process CPU/memory are reachable from a sandboxed MAS app.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
VERDICT: GO. sysctl KERN_PROC_ALL works sandboxed (proc_listpids is denied, no entitlement). proc_pidinfo gives own-uid CPU+RSS at parity with unsandboxed. proc_pid_rusage fully blocked. Binding limit is uid, not sandbox: ~40pp of busy CPU unattributable. See probe/FINDINGS.md.
<!-- SECTION:NOTES:END -->
