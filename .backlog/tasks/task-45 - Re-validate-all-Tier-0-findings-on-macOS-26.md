---
id: TASK-45
title: Re-validate all Tier 0 findings on macOS 26
status: Parked
assignee: []
created_date: '2026-08-02 01:19'
updated_date: '2026-08-02 03:32'
labels:
  - risk
  - spike
milestone: m-1
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PARKED: needs a macOS 26 machine or VM, which is not available on this host (running macOS 27.0, build 26A5388g). Cannot be verified here.

What must be re-checked when a macOS 26 environment exists, in priority order:
1. Whether sysctl KERN_PROC_ALL is permitted under App Sandbox. The entire enumeration strategy rests on it; if it is denied on macOS 26, the app cannot ship there and A-01 needs a product decision.
2. Whether proc_listpids is denied there too (expected, but unconfirmed).
3. Whether proc_pid_rusage is denied there too, which decides whether FR-009 per-process I/O and FR-043 footprint could be restored on that OS.
4. That the mach timebase and proc_taskinfo layout match, since the CPU maths depends on both.

probe/build-sandboxed.sh runs standalone with only swiftc and codesign, so it can be executed on a macOS 26 machine without setting up the full project.
<!-- SECTION:NOTES:END -->
