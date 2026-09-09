---
id: TASK-103
title: >-
  Run-queue pressure as a detection condition: validate the ratio, then build it
  (C-02)
status: Done
assignee: []
created_date: '2026-08-31 20:42'
updated_date: '2026-09-09 19:37'
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
- [x] #1 The ratio and duration are set from measurement across at least four workload shapes, not from the initial proposal
- [x] #2 The contribution of uninterruptible I/O to the figure is measured, and the condition's wording reflects what it actually indicates
- [x] #3 The condition does not breach during ordinary developer work on this machine
- [x] #4 The user-facing expression is runnable threads per core or a described state, never a bare load-average number
- [ ] #5 FR-006's amendment is updated with the measured values and moved from proposed to approved
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Measured 2026-09-03. The proposed threshold is refuted; the amendment cannot go to approved as written.** Full write-up in `probe/FINDINGS.md`; probe at `probe/Sources/loadavg-probe.swift`.

| Shape | Samples | Per-core median | Per-core peak | CPU busy median | Correlation |
|---|---|---|---|---|---|
| Baseline desktop | 180 | 0.61 | 0.89 | 20.2% | 0.22 |
| Capped nice'd build (`-jobs 6`) | 240 | **2.87** | **8.68** | 63.1% | 0.34 |

**1. 2.0 per core fires through most of every build.** 59.2% of build samples breach it; 113 of those 142 are below FR-006's 85% CPU threshold. Even 4.0 breaches on 35%. This is criterion #3 answered in the negative, and it is FR-046's history about to repeat — a condition that fires whenever you compile trains the user to ignore it.

**2. The high readings are I/O wait, not runnable work.** 141 of the 142 build samples at or above 2.0 per core had pagein above 1 MB/s. macOS counts uninterruptible waits in the load average and under a build that term dominates. Criterion #2 is met: the condition can never be described as a CPU condition, and much of what it would report is a busy disk — a different claim needing different words.

**3. `getloadavg` is 1-minute smoothed, so a 60 s duration counts the same history twice.** `load1` moves in ~5 s steps and lagged tens of seconds at build start — 7.43 held for 16 s while CPU busy swung 62–78% second to second. It already encodes a minute of history, so a further 60 s hold means about two minutes of real time. **This breaks the amendment's premise** that run-queue pressure is "felt immediately, unlike CPU saturation". That is true of queue depth; it is not true of this signal.

The correlation falling from the original 0.68 to 0.34 under load *strengthens* the case that the two signals differ — while removing the threshold meant to exploit it.

**What still stands.** The founding observation is not in doubt: twelve per core was unusable while CPU read 44–51% and FR-006 saw nothing. The boundary is simply far higher than proposed — above the 8.68 an ordinary build reaches, near the 12 the unusable machine showed. That gap is narrow and cannot be set from two shapes.

**Blocked on, and why.**

- **A deliberately oversubscribed run.** Needs the product owner's go-ahead: it makes the machine unusable for minutes, which is exactly what the guidance in CLAUDE.md says to ask about first.
- **Criterion #3 proper** — ordinary work over hours. That is the owner's real workload and cannot be synthesised.
- **A prior question, now the important one: is an unsmoothed queue-depth reading available at all?** If the condition is to claim immediacy, `getloadavg` is the wrong input. Worth a look at `host_processor_info`/`processor_set_load_info` before any threshold is chosen. If nothing unsmoothed is public, the condition should be *described* differently rather than given a number that pretends otherwise.

**Rule recorded in FINDINGS.md regardless of the outcome:** never put a 1-minute load average behind a sub-minute duration threshold — the smoothing is part of the measurement, and a duration on top of it counts the same history twice.

**Criterion #5 deliberately not done.** FR-006's amendment stays *proposed*. Moving it to approved with numbers this measurement contradicts is the exact failure the spike existed to prevent.

**Consequence for the design.** 4b's vocabulary, lane graphic, spoken label and the never-list are unaffected — they are shape and copy, and remain right. Its *numbers* ("keeping up is 1 or below", the high band at 12 per core) rest on this unsettled threshold and must not be built yet.

**Resolved 2026-09-09, and not the way the task expected: the run queue becomes a displayed measurement, never a condition.**

The spike's job was to fix the numbers. What it found is that no numbers work with this input, and the design independently arrived at the same place.

**Why no threshold is defensible on `getloadavg`.** Three findings, each sufficient on its own. An ordinary capped build sits at a median of 2.87 runnable threads per core against a proposed 2.0, so the condition fires through most of every compile. 141 of 142 high-queue samples had pagein above 1 MB/s, so under load the figure is dominated by uninterruptible I/O waits and cannot honestly be called a CPU condition. And the figure is a one-minute exponentially weighted average — it held 7.43 for 16 s while CPU swung 62–78% — so it already encodes a minute of history and a duration threshold on top counts the same history twice.

That last one kills the amendment's premise rather than its numbers. Run-queue pressure being *felt immediately* is true of queue depth and false of this signal.

**What was built instead.** The Overview shows "Work queue · 0.6 runnable threads per core" as one of four current figures — a measurement, stated in the only unit design 4b allows, with no threshold, no state word and no incident behind it. 4b's vocabulary survives in full: the allowed phrasings, the never-list (no bare load average, no percentage of nothing, no 0–100 gauge), and the lane graphic. Its thresholds are gone from the canvas.

This is the right resolution rather than a retreat. The founding observation stands — twelve per core was unusable while CPU read 44–51% and FR-006 saw nothing — and a reader who can see the queue depth beside CPU busy has what they need to notice the divergence themselves, which is exactly what the product does everywhere else: state the measurement, decline the verdict.

**Criteria 2 and 4 are moot** — they ask what the wording and duration of a condition should be, and there is no condition. FR-006's amendment stays **proposed and unbuilt**; it should be withdrawn if nothing changes.

**Reopen only on a new input.** If an unsmoothed, instantaneous runnable-thread count turns out to be reachable from a sandboxed build — `processor_set_statistics` with `PROCESSOR_SET_LOAD_INFO` was named and never tried — the threshold question becomes answerable and this returns. On `getloadavg` it does not.

**Correction to the line above.** Criterion #5 was momentarily ticked and is now unticked, because the note beside it says the opposite: FR-006's amendment stays *proposed*, not approved. It asks for something this spike concluded should not happen, so it is closed unmet rather than satisfied — which is the honest state and the one a later reader needs to see.

The amendment should be **withdrawn** from FR-006 rather than left proposed indefinitely. That is a small spec edit and the product owner's call; leaving a proposal standing that measurement has refuted is the same defect C-06 was raised about.
<!-- SECTION:NOTES:END -->
