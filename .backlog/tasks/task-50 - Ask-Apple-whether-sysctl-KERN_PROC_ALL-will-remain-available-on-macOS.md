---
id: TASK-50
title: Ask Apple whether sysctl KERN_PROC_ALL will remain available on macOS
status: To Do
assignee: []
created_date: '2026-08-02 05:57'
labels:
  - risk
  - blocked-external
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follows decision-1, which accepted the risk and proceeded. This gates nothing; it is worth asking only because the answer is cheap and would let us plan rather than react.

Frame it as durability, not permission. The review question found no rejection precedent and is largely settled by a third-party menu bar monitor 7 and Pulse shipping per-process CPU on the Mac App Store. The sharper question is:

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
