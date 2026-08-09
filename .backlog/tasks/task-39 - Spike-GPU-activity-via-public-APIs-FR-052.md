---
id: TASK-39
title: 'Spike: GPU activity via public APIs (FR-052)'
status: Out of Scope
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-09 00:57'
labels:
  - spike
milestone: m-4
dependencies: []
priority: low
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Duplicate of TASK-59, which is Done. Both asked whether GPU activity is reachable through public APIs under the sandbox. Answer recorded there and in probe/FINDINGS.md: yes, machine-wide utilisation via IOAccelerator's Device Utilization %, verified against a real Metal load. No temperature, no frequency, nothing per-process.
<!-- SECTION:NOTES:END -->
