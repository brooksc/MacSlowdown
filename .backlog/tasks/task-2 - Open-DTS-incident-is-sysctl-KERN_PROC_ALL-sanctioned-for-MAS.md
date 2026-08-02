---
id: TASK-2
title: 'Open DTS incident: is sysctl KERN_PROC_ALL sanctioned for MAS?'
status: Parked
assignee: []
created_date: '2026-08-02 01:05'
updated_date: '2026-08-02 03:32'
labels:
  - risk
  - blocked-external
milestone: m-0
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
proc_listpids is explicitly denied under App Sandbox and Apple DTS has stated no entitlement lifts it. We enumerate via sysctl KERN_PROC_ALL instead, which works and is public API, but no Apple statement blesses it as the sanctioned alternative.

Risk: a reviewer reads "enumerate the process table after the designated API was denied" as circumventing the sandbox. We request no entitlements, which is where rejections normally cluster, but this cannot be settled by testing.

This is the single largest unretired risk in the project. A wrong answer invalidates the architecture.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DTS incident or Developer Forums question filed
- [ ] #2 Answer recorded in probe/FINDINGS.md and CLAUDE.md
- [ ] #3 If negative, escalate to product decision before further Phase 1 work
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PARKED: requires a response from Apple (DTS incident or Developer Forums), which is outside this machine and outside my control.

Unchanged in substance: proc_listpids is explicitly denied under App Sandbox with no entitlement remedy per Apple DTS, and MacSlowdown enumerates via sysctl KERN_PROC_ALL instead. That works, uses only public API, and requests no entitlements -- but no Apple statement blesses it as the sanctioned alternative, and the risk is that a reviewer reads it as working around the sandbox.

This remains the single largest unretired risk in the project and cannot be settled by testing. The m-1 build now depends on it end to end, so a negative answer would invalidate the enumeration layer (ProcessSampler.processTable) though not the rest of the architecture.
<!-- SECTION:NOTES:END -->
