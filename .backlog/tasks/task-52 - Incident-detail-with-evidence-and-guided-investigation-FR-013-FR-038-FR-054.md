---
id: TASK-52
title: >-
  Incident detail with evidence and guided investigation (FR-013, FR-038,
  FR-054)
status: Done
assignee: []
created_date: '2026-08-02 18:14'
updated_date: '2026-08-03 05:55'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IncidentDetailView.swift. Verified against a real incident in the running app.

- AC#1/#2 Every statement shows its evidence class as a badge, and a hypothesis carries its confidence in the same badge so the caveat cannot be separated from the claim: 'Likely - moderate confidence: yes was the largest measurable contributor, at 77% of one core.'
- AC#3 'The measurements' section shows the raw figures with their evidence classes, plus the unattributed explanation naming the protected processes observed running.
- AC#5 Figures summed exactly on screen: 764% attributed + 36% unattributed = 800% total.

Two defects found by looking at the running app rather than the build:

1. 'Working through it' repeated 'What we found' verbatim, because the guided investigation's first stage restates the summary. Reads as a bug when both are on screen. The detail view now skips that stage, since the remaining four are what add something.

2. FR-055's sum invariant BROKE under saturation. The host aggregate and the per-process counters are read at slightly different instants, so under heavy load the attributed sum can exceed the host total; clamping the remainder at zero left attributed + unattributed > total. This failed precisely when the machine was in the state the product exists to explain. Both figures are measurements, so the sum of parts is a lower bound on the whole -- the total is now max(hostTotal, attributed) and the remainder is the difference, which keeps every measurement and makes the invariant hold by construction. Regression tests added for both directions.

The second was caught by the saturation test, not by review, and would have shipped as a contributor list that quietly stopped adding up under load.
<!-- SECTION:NOTES:END -->
