---
id: TASK-45
title: Re-validate all Tier 0 findings on macOS 26
status: To Do
assignee: []
created_date: '2026-08-02 01:19'
labels:
  - m1-core-monitor
  - risk
  - spike
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A-01 requires macOS 26 AND 27. Every Tier 0 finding was measured on macOS 27.0 (26A5388g) only.

Sandbox profile behavior is exactly the kind of thing that differs across major releases. Specifically unverified on macOS 26:
- Whether sysctl KERN_PROC_ALL is permitted sandboxed (our entire enumeration strategy)
- Whether proc_listpids is denied there too
- Whether proc_pid_rusage is denied there too
- Whether the mach timebase and PROC_PIDTASKALLINFO layouts match

If sysctl enumeration is denied on macOS 26, the app cannot ship to that OS and A-01 needs a product decision.

Requires a macOS 26 VM or second machine -- not available on the current host.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 probe/build-sandboxed.sh run on macOS 26 and output captured
- [ ] #2 Any divergence from macOS 27 recorded in probe/FINDINGS.md
- [ ] #3 If enumeration differs, escalate as an A-01 scope decision
<!-- AC:END -->
