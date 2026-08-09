---
id: TASK-77
title: >-
  FR-039 grouping corrections are built, persisted and unreachable — no UI
  creates one and the grouper is never given them
status: To Do
assignee: []
created_date: '2026-08-09 18:51'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`).

FR-039 says the user shall be able to correct process-family attribution — correct, split, merge or mark expected. The "mark expected" half works, through `PolicyStore.setPolicy`. The grouping half exists at every layer and is joined at none:

- `GroupingCorrection` (`Metrics/Sources/ApplicationPolicy.swift:104`) — no app reference. No view creates one.
- `PolicyStore.corrections` / `addCorrection` / `removeCorrection` (`:204, :206, :214`) — zero callers; `addCorrection` has 6 test references.
- `PolicyStore.overrides(for:)` (`:223`), which turns corrections into a `GroupingOverrides` explicitly "for FamilyGrouper" — zero callers.
- `FamilyGrouper.group` accepts `overrides:` and defaults it to `.none`. The single app call site, `MacSlowdown/Sources/MonitorStore.swift:488`, does not pass it.

So even if a correction could be made, it could not take effect. Both ends need connecting, not just one.

FR-039's acceptance criteria are "corrections are reversible; raw PID samples remain intact; no correction uploads by default". `removeCorrection` gives reversibility and the persistence is already local-only, so the framework side of those criteria is satisfied — it is the reachability that is missing.

Design input: the Claude Design screens under `design/` should be checked for whether a correction affordance was drawn before inventing one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A user can detach a process from a family or attach it to another from the family inspector or the inventory, and the action creates a GroupingCorrection
- [ ] #2 MonitorStore passes PolicyStore.overrides(for:) into FamilyGrouper.group on every sweep, so a correction changes the next grouping
- [ ] #3 A correction is reversible from the interface and removing it restores the heuristic grouping
- [ ] #4 Raw per-PID samples are unchanged by a correction -- history is not rewritten (FR-039)
- [ ] #5 probe/seam-reachability.sh no longer reports addCorrection or removeCorrection
<!-- AC:END -->
