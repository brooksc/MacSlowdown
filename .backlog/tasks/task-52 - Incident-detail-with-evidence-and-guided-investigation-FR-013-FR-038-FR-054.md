---
id: TASK-52
title: >-
  Incident detail with evidence and guided investigation (FR-013, FR-038,
  FR-054)
status: In Progress
assignee: []
created_date: '2026-08-02 18:14'
updated_date: '2026-08-02 18:15'
labels:
  - ui
  - phase1-catchup
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 1 of m-3. IncidentSummary and GuidedInvestigation are built and tested but never displayed, so the evidence discipline they enforce is invisible.

Design reference: 1e (evidence room), 1h (unattributable case), 1o (repeated crash).

Must carry the evidence classes through to the screen: measured facts, calculated values, and hypotheses with their confidence. The unattributable case is not an error state -- it is roughly 40% of real incidents and needs to read as a useful answer.</description>
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every displayed statement shows its evidence class
- [ ] #2 Every hypothesis shows its confidence level
- [ ] #3 Raw measurements are reachable from the detail view
- [ ] #4 The unattributable case reads as a finding, not a failure
- [ ] #5 Contributor figures visibly sum to the total (FR-055)
<!-- AC:END -->
