---
id: TASK-50
title: Ask Apple whether sysctl KERN_PROC_ALL will remain available on macOS
status: To Do
assignee: []
created_date: '2026-08-02 05:57'
updated_date: '2026-09-09 19:37'
labels:
  - risk
  - blocked-external
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follows decision-1, which accepted the risk and proceeded. This gates nothing; it is worth asking only because the answer is cheap and would let us plan rather than react.

Frame it as durability, not permission. The review question found no rejection precedent and is largely settled by iStat Menus 7 and Pulse shipping per-process CPU on the Mac App Store. The sharper question is:

  Apple withdrew sysctl CTL_KERN/KERN_PROC/KERN_PROC_ALL on iOS 9, stating that
  apps are not permitted to see what other apps are running. Is that API expected
  to remain available to sandboxed Mac App Store apps on macOS?

Developer Forums is the right venue -- Apple engineers answer there and it costs nothing. A DTS incident is overkill.

Also worth watching passively: if a macOS beta's release notes mention process-table restrictions, or the call starts returning EPERM on a beta, that answers the question without asking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Question posted, or a beta observation answers it
- [ ] #2 Answer recorded in probe/FINDINGS.md and decision-1
- [ ] #3 If negative, decision-1 is revisited and the NSRunningApplication fallback is scheduled
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Raised to High, 2026-09-09.** It was Low while §10.3 called the same thing the largest single risk in the project. Those cannot both be true, and the reason it stayed Low is precisely why it is dangerous: **it gates no code**, so every session finds something more urgent, and it is the one risk no amount of building resolves.

Everything in this product rests on enumerating processes through `sysctl KERN_PROC_ALL`. `proc_listpids` is explicitly denied under the sandbox and Apple DTS has confirmed no entitlement lifts it. The sysctl works, is public, and requests nothing — but Apple withdrew this same call on iOS 9, and no statement blesses it on macOS. If it goes, the product does not degrade; it stops.

The partial comfort recorded in TASK-2 is that iStat Menus 7 and Pulse ship per-process CPU on the Mac App Store, so the *feature* is evidently permitted. That is an existence proof for the capability, not for our mechanism — iStat's MAS build requires a separately downloaded helper, so its process list may not come from a sandboxed sysctl at all.

**This is the product owner's action, not a work item.** What would settle it is a DTS incident asking about durability rather than permission: not "may we", but "is this expected to remain available".
<!-- SECTION:NOTES:END -->
