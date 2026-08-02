---
id: TASK-23
title: 'Evidence-based incident summary (FR-013, FR-038)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:47'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every causal phrase labeled by confidence
- [ ] #2 Conclusions classified: measured fact, derived, heuristic, user-provided
- [ ] #3 No unsupported claims present
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IncidentSummary.swift, plus Evidence extended to FR-038's four classes (measured / calculated / heuristic / userProvided) and a Confidence type.

- AC#1 Every causal phrase carries a confidence, enforced by the type rather than by discipline: Conclusion's initialiser attaches a confidence if and only if the evidence is .heuristic, defaulting to .low when none is supplied. An unlabelled causal claim is therefore unrepresentable. Tested both directions -- a heuristic without a stated confidence still gets one, and a measured fact given a confidence has it stripped, since a measurement is not more or less likely.
- AC#2 All four FR-038 classes exist and the summary uses three of them distinctly: measured facts (durations, peaks), the calculated unattributed share, and exactly one heuristic. Naming a contributor is the only causal move the summary makes and is always a hypothesis -- a test asserts any statement mentioning the contributor is .heuristic, because calling it measured fact would overstate causation.
- AC#3 No unsupported claims, asserted across several incident shapes against a forbidden list: 'caused by', 'will fix', 'freed', 'free up', 'wasted', 'memory leak', 'optimi', 'clean up', 'guaranteed', 'frozen', 'hung', 'unresponsive'. The last three matter because TASK-27 established hangs are undetectable, so the summary must never imply one.

The judgement I am most pleased with, and the one worth reviewing: confidence FALLS as the unattributable share rises. If 60% of activity is unattributable, the largest contributor we can see may only be the largest thing we are permitted to see, not the largest thing running. Above 30% unattributable the hypothesis text says so outright -- 'it may not be the largest contributor overall, only the largest we can see' -- and above 50% confidence drops to low. This is the honest consequence of the ~40pp blind spot showing up in the reasoning rather than only in a figure.

Ruled-out statements are measured facts rather than hedges, so 'not a memory problem' carries the same weight as the positive findings.

A summary built without attribution still states what was measured and emits no hypothesis, since there is no basis for one.
<!-- SECTION:NOTES:END -->
