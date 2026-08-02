---
id: TASK-2
title: 'Open DTS incident: is sysctl KERN_PROC_ALL sanctioned for MAS?'
status: To Do
assignee: []
created_date: '2026-08-02 01:05'
labels:
  - m0-feasibility
  - risk
  - blocked-external
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
