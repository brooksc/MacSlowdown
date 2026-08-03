---
id: TASK-31
title: Post-action outcome verification (FR-050)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:09'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A successful API return alone is never labeled a performance improvement
- [ ] #2 Inconclusive outcomes are allowed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ActionOutcome.swift: ActionResult, VerificationOutcome, ActionVerification, ActionVerifier.

- AC#1 A successful API return is never labelled a performance improvement. An action that ran successfully with no measurable change reports 'no measurable change', and a test asserts exactly that -- the action ran and nothing improved are different claims. A change below a 10-point noise floor is not a change in either direction.
- AC#2 Comparison windows and affected metrics are visible: the summary states the before and after figures and the window length in seconds.
- AC#3 Inconclusive outcomes are allowed and are first-class. An action that never ran (failed or withheld) yields .inconclusive rather than borrowing whatever the machine happened to do afterwards -- attributing a change to an action that did not happen would be the worst version of this mistake. Missing measurements yield .unavailable rather than a guess.

Copy is asserted never to claim credit: forbidden list covers fixed, resolved, 'because you', 'thanks to', solved, 'we fixed'. An improvement reads 'Total CPU fell from 95% to 20% over the 30 seconds after you acted. The two line up, but we cannot prove one caused the other.' That sentence is the whole point of FR-050.
<!-- SECTION:NOTES:END -->
