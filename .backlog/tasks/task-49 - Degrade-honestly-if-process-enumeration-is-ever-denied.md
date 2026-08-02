---
id: TASK-49
title: Degrade honestly if process enumeration is ever denied
status: To Do
assignee: []
created_date: '2026-08-02 05:57'
labels:
  - core
  - risk
milestone: m-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follows decision-1. "We can remove it later" is only true if failure is survivable, so this is the task that makes the decision's escape route real rather than aspirational.

Today, if sysctl KERN_PROC_ALL were denied, ProcessSampler.processTable() returns an empty array and the app would show an empty inventory and zero attributed CPU. That reads as "nothing is running" when the truth is "we are not allowed to look" -- exactly the failure FR-002 forbids, and the same class of mistake as a contributor list that silently fails to sum.

This is not speculative: Apple withdrew this API on iOS 9 for this precise use, so denial on a future macOS is a real scenario rather than an invented one.

Scope: distinguish "enumeration returned nothing" from "enumeration failed", and say so. Aggregate CPU, memory pressure, thermal and storage all keep working in that state, so the app remains useful as a monitor and should say what it can no longer do.

Do NOT build the NSRunningApplication fallback here. It is documented in decision-1 as a costed retreat; building it now would be speculative.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 processTable() distinguishes an empty result from a failed call
- [ ] #2 The interface states that process information is unavailable rather than showing an empty list
- [ ] #3 Aggregate metrics continue to work and are still shown in that state
- [ ] #4 A test simulates enumeration failure and asserts the honest message, not a blank inventory
<!-- AC:END -->
