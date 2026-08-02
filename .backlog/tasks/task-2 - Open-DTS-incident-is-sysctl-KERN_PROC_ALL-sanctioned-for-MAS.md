---
id: TASK-2
title: Verify sysctl KERN_PROC_ALL is acceptable AND durable for MAS
status: Done
assignee: []
created_date: '2026-08-02 01:05'
updated_date: '2026-08-02 05:57'
labels:
  - risk
  - blocked-external
milestone: m-0
dependencies: []
priority: low
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
- [x] #3 If negative, escalate to product decision before further Phase 1 work
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

WEB RESEARCH, 2026-08-01. Two findings, pulling in opposite directions.

EVIDENCE THE CAPABILITY SHIPS ON MAS:
- iStat Menus 7 is on the Mac App Store and its listing advertises 'a list of the apps using the most CPU'. Bjango's documented MAS limitations (v6-era) are weather, fan control, CPU frequency and helper-required sensors -- per-process CPU is NOT among them.
- Pulse (paid, MAS) lists 'top processes' among its metrics.
So per-process CPU visibility demonstrably passes App Review in some form.

BUT neither confirms the MECHANISM. iStat Menus' MAS build requires a separately downloaded Helper app for some stats, so its process list may come from the helper rather than from a sandboxed sysctl call. This is an existence proof for the feature, not for our implementation.

Counterpoint: Better Resource Monitor is MAS, open source (MIT), explicitly 'fully sandboxed, no privileged helper, no private APIs' -- and offers aggregate metrics only, no per-process list. Absence of a feature is not proof it is blocked, but it is the one app whose sandbox posture matches ours exactly, and it does not do what we do.

NEW AND MORE IMPORTANT RISK -- DURABILITY, NOT REVIEW:
Apple deliberately closed this exact API on iOS. A developer reported KERN_PROC_ALL working through iOS 8 and returning 'Operation not permitted' from iOS 9 beta 3; the resolution was that Apple 'basically removed that sysctl option', with the stated rationale that apps 'are not permitted to see what other apps are running'.

That is Apple stating intent about the precise call we depend on, and the rationale applies verbatim to us. macOS has not followed -- it has always permitted more introspection, and ps, top and Activity Monitor exist for users -- but the sandbox already gates sysctl per-node (sysctl-read denials are a documented violation type), so gating kern.proc would require no new machinery.

So the question to ask Apple should be BOTH:
1. Is sysctl KERN_PROC_ALL acceptable for a sandboxed MAS app? (No rejection precedent found.)
2. Is it expected to remain available on macOS, given it was withdrawn on iOS 9 for this exact use?

Question 2 matters more. A review rejection is a one-time problem we would find out about at submission; a future OS closing the API breaks shipped installs, and A-01 already commits us to macOS 26 and 27 with later versions to follow.

Still not a gate on m-2: the NSRunningApplication fallback bounds the damage either way. But it raises the value of asking, and of keeping the enumeration behind a single swappable function -- which it already is.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RESOLVED BY PRODUCT DECISION, not by an answer from Apple. Recorded as decision-1.

Decision: use sysctl KERN_PROC_ALL and proceed, accepting the risk because it is reversible at bounded cost. Without a process list the product is a gauge, which section 1.2 says is not the product, so the capability is worth the exposure.

AC#3 is satisfied in the sense that mattered: the risk was escalated and a product decision was taken before further work, which is what the criterion existed to force. AC#1 and AC#2 are deliberately left unchecked -- no question was filed and no Apple answer was recorded, so checking them would misrepresent what happened.

Follow-ups created:
- TASK-49: make enumeration failure degrade honestly rather than reading as "nothing is running". This is the concrete thing that makes "we can remove it later" true rather than aspirational.
- TASK-50: ask Apple the durability question when convenient. Low priority, gates nothing.

The seam that makes this reversible already exists: ProcessSampler.processTable() is the single point of contact, and no caller reaches around it. Keeping that property is now a documented consequence of the decision rather than an accident of the current design.
<!-- SECTION:FINAL_SUMMARY:END -->
