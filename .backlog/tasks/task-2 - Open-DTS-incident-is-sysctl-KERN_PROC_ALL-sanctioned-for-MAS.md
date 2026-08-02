---
id: TASK-2
title: 'Open DTS incident: is sysctl KERN_PROC_ALL sanctioned for MAS?'
status: Parked
assignee: []
created_date: '2026-08-02 01:05'
updated_date: '2026-08-02 05:49'
labels:
  - risk
  - blocked-external
milestone: m-0
dependencies: []
priority: medium
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

CORRECTION (I had overstated this). Calling a negative answer 'architectural' was wrong.

The sysctl call lives in one function, ProcessSampler.processTable(), roughly 30 lines. Removing or replacing it is a contained change. Nothing in the module structure, identity model, grouping, attribution maths or UI depends on how the process list arrives.

What a negative answer would actually cost:
- Everything downstream needs SOME process list, so without one there is no inventory (FR-002), no family grouping (FR-003), no contributor ranking (FR-006), and attributed CPU falls to zero -- the unattributed bucket becomes 100%.
- What survives is aggregate CPU, memory pressure, swap, thermal, storage and power. That is a gauge, which section 1.2 explicitly says is not the product.

But a fallback exists and it bounds the damage. Tier 0 measured NSRunningApplication returning 119 apps (113 with bundle IDs), and proc_pidinfo succeeded for 118 of those 119 pids. So enumeration could fall back to GUI applications only, still with real CPU and memory.

The cost of that fallback is helpers: Chrome's 23 renderers and Xcode's swift-frontend are not NSRunningApplication entries, so helper-heavy applications would show only their main process and badly under-report -- the exact case FR-003 exists to handle. Their usage would sink into the unattributed bucket.

Risk recalibrated to MEDIUM. sysctl is public API, we request no entitlements, and entitlement requests are where rejections actually cluster. No precedent of a rejection for this was found; the earlier concern came from a forum caution, not evidence. Rejection would also not arrive as 'you used sysctl' -- App Review cites guidelines, not syscalls.

Still worth asking, because it is cheap. No longer treated as a gate on m-2.
<!-- SECTION:NOTES:END -->
