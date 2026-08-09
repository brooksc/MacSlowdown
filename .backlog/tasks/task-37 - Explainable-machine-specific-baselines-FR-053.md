---
id: TASK-37
title: Explainable machine-specific baselines (FR-053)
status: To Do
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-09 21:32'
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
<!-- SECTION:NOTES:END -->
