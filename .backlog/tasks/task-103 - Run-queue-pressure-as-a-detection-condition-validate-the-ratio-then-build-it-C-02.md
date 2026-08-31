---
id: TASK-103
title: >-
  Run-queue pressure as a detection condition: validate the ratio, then build it
  (C-02)
status: To Do
assignee: []
created_date: '2026-08-31 20:42'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
type: spike
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product owner, 2026-08-31, on challenge C-02: revise as appropriate. The revision is proposed in FR-006 and needs validating before its numbers are fixed.

**The measurement that prompted it.** 40 samples at one second on the product owner's M2, 8 logical cores:

| | |
|---|---|
| Load average, peak | **95.8** — about twelve runnable threads per core |
| CPU busy then | 93% |
| Load average 30 s later | 45.9 — nearly six per core |
| CPU busy then | **44–51%** |
| Correlation across the run | **0.68** |

At six runnable threads per core the machine is unusable, and at 44% busy FR-006 sees nothing: its condition needs 85% sustained for three minutes. The two signals are related but distinct, and busy time is the weaker predictor of the thing this product exists to explain. Waiting on the run queue is what "slow" feels like; busy time is what "working" looks like.

**Proposed and not yet built:** a second, independent condition — sustained run-queue pressure, breaching above a ratio of runnable threads per logical core (initial proposal 2.0) held for a duration (initial proposal 60 s). `vm.loadavg` is a public sysctl, one call, available sandboxed. FR-006's CPU threshold is untouched; this adds a case rather than loosening one.

**What the spike has to settle before the numbers are fixed.**

1. **Does the ratio separate felt-slow from busy-but-fine?** Sample across a build, a video export, an idle machine and a machine deliberately oversubscribed, and find where the boundary actually falls. 2.0 is a starting guess, not a finding.
2. **How much of macOS's load average is uninterruptible I/O rather than runnable work?** On macOS the figure counts both. A machine waiting on a slow disk reads high with an idle CPU — arguably still a slowdown worth reporting, but it means the condition must not be described as a CPU condition, and it may want its own wording.
3. **Does it fire on this machine during ordinary developer work?** The false-positive history of FR-046 is the cautionary tale: a condition that breaches whenever you compile is worse than no condition.
4. **What duration?** 60 s is proposed because run-queue pressure is felt immediately, unlike CPU saturation where three minutes filters out builds. Validate rather than assume.

**Presentation constraint, already in the spec.** A load average is never shown as a percentage or as a bare number beside percentages — "18.45" invites exactly the wrong reading. It is expressed as runnable threads per core, or as a described state. Measured fact under FR-038; any claim about what it causes stays heuristic.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The ratio and duration are set from measurement across at least four workload shapes, not from the initial proposal
- [ ] #2 The contribution of uninterruptible I/O to the figure is measured, and the condition's wording reflects what it actually indicates
- [ ] #3 The condition does not breach during ordinary developer work on this machine
- [ ] #4 The user-facing expression is runnable threads per core or a described state, never a bare load-average number
- [ ] #5 FR-006's amendment is updated with the measured values and moved from proposed to approved
<!-- AC:END -->
