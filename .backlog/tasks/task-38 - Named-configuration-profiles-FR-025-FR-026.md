---
id: TASK-38
title: 'Named configuration profiles (FR-025, FR-026)'
status: Out of Scope
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-09-09 19:36'
labels:
  - core
milestone: m-4
dependencies: []
priority: low
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Not started, and deliberately: this is m-4 (Phase 4) work**, excluded by CLAUDE.md's "Don't build Phase N+1 infrastructure during Phase N" while Phases 1–3 still carry open on-screen verification.

Also underspecified: no description and **no acceptance criteria at all**, so there is nothing to build against. FR-025/FR-026 would need reading and turning into criteria before this is startable by anyone. Reviewed 2026-08-09.

**Closed 2026-09-09 (challenge C-05, spec v1.6).** FR-025 and FR-026 are deferred; this task closes with them.

The argument that settled it was not ours. Design 4a reached the same conclusion independently and put it better than the challenge did: **a profile puts a mode switch in the same list as navigation**, so a mis-click silently changes what counts as a condition — a setting disguised as a place. That is exactly the class of defect FR-060 exists to prevent, arriving through the navigation model rather than through two surfaces disagreeing.

Per-application rules (FR-016, now condition-scoped) already cover the case profiles were invented for, and unlike a profile they say what they do.

The build never had profiles, so nothing is being removed — only the backlog's implication that they were planned. Returns only on user evidence.
<!-- SECTION:NOTES:END -->
