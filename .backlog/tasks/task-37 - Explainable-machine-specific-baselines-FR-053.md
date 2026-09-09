---
id: TASK-37
title: Explainable machine-specific baselines (FR-053)
status: Parked
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-09-09 19:36'
labels:
  - core
milestone: m-4
dependencies: []
priority: low
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cold-start behavior defined; user can inspect and reset learned state
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Not started, and deliberately: this is m-4 (Phase 4) work.** CLAUDE.md's phasing rule is explicit — "Don't build Phase N+1 infrastructure during Phase N" — and Phases 1–3 still carry open on-screen verification. Excluded on that basis, not on difficulty.

Two things a future session should settle before starting, because neither is inferable from the repo: the task has one vague acceptance criterion and no description, and FR-053's "explainable" is doing a lot of work — a learned baseline the user cannot interrogate would breach FR-038's labelling rule, so the shape of the explanation is part of the design, not a follow-up to it. Reviewed 2026-08-09.

**Deferred 2026-09-09 (challenge C-05, spec v1.6).** Returns only on user evidence.

What makes this a firm deferral rather than a shrug: the design reached for baselines independently, in 5g, wrote out the case for them, and then **argued itself out of it**. The case was real — a fixed threshold cannot distinguish a machine that has always run at 85% from one that never did until this week, and "it was slow earlier" usually means "slower than it normally is". The rebuttal is better:

- **A learned normal is a second, invisible line.** A condition that crossed it but not the fixed one is a condition the settings screen cannot explain — FR-060's failure arriving through a threshold rather than through copy.
- **It breaks the coverage promise.** Fourteen days of learning is fourteen days when the line is provisional, and the coverage strip has no vocabulary for "watching, but not yet calibrated". Coverage is now built (TASK-113) and this is a real conflict, not a hypothetical one.

If it returns, it should return as **its own idea** — a "this is unusual for your Mac" statement inside a condition, with the comparison shown — never as a switch that quietly moves the line.
<!-- SECTION:NOTES:END -->
