---
id: TASK-49
title: Degrade honestly if process enumeration is ever denied
status: Done
assignee: []
created_date: '2026-08-02 05:57'
updated_date: '2026-08-02 06:05'
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
- [x] #1 processTable() distinguishes an empty result from a failed call
- [x] #2 The interface states that process information is unavailable rather than showing an empty list
- [x] #3 Aggregate metrics continue to work and are still shown in that state
- [x] #4 A test simulates enumeration failure and asserts the honest message, not a blank inventory
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Makes decision-1's escape route real rather than aspirational. 71 assertions passing; live app verified unchanged (menu bar figures still sum exactly: 64+26+20+104+88 = 302 total).

- AC#1 systemProcessTable() now returns Result rather than an array, so a refused call is distinguishable from an empty table. ProcessSnapshot carries an EnumerationOutcome. A test asserts the two cases produce identical record counts but opposite meanings, which is the entire point. A lost sysctl resize race is also reported as failure rather than as an empty machine.
- AC#2 Both surfaces refuse to render an empty list. NowView shows a banner headed "Applications can't be listed on this Mac"; the inventory replaces the table with a ContentUnavailableView rather than an empty one. Copy is asserted by test to avoid speculation and alarm -- no "denied", "blocked", "sandbox", "error" or "Apple".
- AC#3 Aggregate measurement is independent of enumeration, and the explanation says so: "Total CPU, memory pressure, thermal state and storage are unaffected and are still being recorded." A test drives a denied sampler through a real attribution and confirms total CPU is still measured, everything lands in the remainder, and the totals still account for the whole.
- AC#4 Denial is simulated through an injected enumerator, so the failure path is exercised without needing a kernel that refuses.

The injected enumerator is also the seam decision-1 requires: swapping the enumeration strategy now means replacing one closure, and nothing downstream reaches around it. Testability and reversibility turned out to be the same requirement.

Note on behaviour under denial: with nothing attributable, unattributed becomes 100% of busy CPU. That is the honest answer rather than a degenerate case -- the machine is genuinely busy and we genuinely cannot say with what -- and FR-055's sum invariant still holds.
<!-- SECTION:NOTES:END -->
