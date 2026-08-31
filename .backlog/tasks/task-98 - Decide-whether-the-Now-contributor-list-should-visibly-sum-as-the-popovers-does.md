---
id: TASK-98
title: >-
  Decide whether the Now contributor list should visibly sum, as the popover's
  does
status: To Do
assignee: []
created_date: '2026-08-31 16:46'
labels:
  - ui
  - decision
milestone: m-3
dependencies: []
priority: low
type: spike
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review finding 27 of TASK-96. Filed as a decision rather than a bug because it is one, and because it was the one finding the reviewer explicitly flagged for consistency rather than as a violation.

The **popover** carries an "Other applications" residual row precisely so its contributor list adds up to 100%, and says so in the section header. The **Now** table takes the top five plus the system row and states the shortfall only in prose: "The largest few, plus everything we may not measure."

Both are defensible under FR-055, whose design freedom says presentation is open provided the remainder is not de-emphasised into insignificance — and the Now table does show the unattributable row, so nothing is hidden. But the two surfaces answer the same question with different rigour, and on the Now table the arithmetic is not checkable by a reader who wants to check it.

Note this is the same *class* the review kept finding — two surfaces treating one fact differently — but not the same defect: neither is wrong, they are merely unequal. That is why it needs a decision rather than a fix.

**The options.**

1. Give the Now table the popover's residual row, so both lists sum and one rule covers both. Costs a row on a screen the design deliberately keeps sparse.
2. Leave it, and record here that the difference is intended — the Now table is a summary, the popover is the triage surface, and only the latter promises arithmetic.
3. Something between: keep the prose but make it quantitative — "the largest few, which are 62% of what we measured".

Design references 1c (Now) and 1a/1b (popover) are the inputs. No code changes until the product owner picks one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The product owner picks one of the three options, or states a fourth
- [ ] #2 If the difference is intended, the reason is recorded where the two lists are built, so nobody 'fixes' it later
- [ ] #3 If the lists are to match, the Now table sums to 100 with largest-remainder rounding exactly as the popover does
- [ ] #4 FR-055's rule that the remainder is not de-emphasised into insignificance holds in whichever is chosen
<!-- AC:END -->
