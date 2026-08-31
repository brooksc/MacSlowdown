---
id: TASK-101
title: 'Six challenges to the specification, raised from two weeks of real use'
status: To Do
assignee: []
created_date: '2026-08-31 20:17'
labels:
  - decision
dependencies: []
priority: high
type: spike
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`requirements.md` re-reviewed 2026-08-31 against everything measured since it was written. Factual corrections were applied directly (v1.3). Six things that change the product's *shape* were not, and are written up as §10.1 of the spec for the product owner. Each needs a decision; none should be acted on unilaterally.

**C-01 — FR-046 (repeated application failure) may not be shippable.** Nine days, ten incidents, all false, no other kind of incident at all. Four successive narrowings, each closing one cause and revealing another. What survives is "an app you were using vanished and came back three times in fifteen minutes" — which the user watched happen — while we cannot say why it went and the subject is ambiguous to 16 bytes. *Recommendation: reduce it to a lifecycle record in the inspector, with no incident and no notification.*

**C-02 — the CPU threshold may sit above where slowness is felt.** 85% of machine capacity for three minutes is ~6.8 of eight cores. The owner's machine at 86% with a load average of 26 barely qualified. Contention predicts perceived slowness better than busy-time does, and run queue appears nowhere in this spec — previously rejected as a *displayed* figure, which is an argument about presentation rather than detection. *Recommendation: a spike comparing run-queue depth against busy-time before the default is settled.*

**C-03 — the spec centres incidents; observed use is entirely live.** Every piece of product feedback in two weeks concerned the popover, the trend columns, the status word's steadiness, the table's ordering. None concerned an incident report, and there was no legitimate incident to read. The live surfaces are governed only by FR-002's general "never fabricate" rule and have no acceptance criteria of their own. *Recommendation: give them first-class requirements, or state that they are secondary and accept the consequence.*

**C-04 — §1.2's success definition sets a bar the sandbox forbids clearing.** It promises the user will understand which applications were associated with a condition; ~40 percentage points of busy CPU is unattributable by uid, not by sandbox. FR-055 handles this honestly on screen; the success definition never caught up. *Recommendation: reword so success includes stating what could not be attributed.*

**C-05 — FR-053, FR-025 and FR-026 have no evidence of need.** Baselines and profiles, all written before anything existed, all substantial, none requested by two weeks of use. *Recommendation: move to Deferred pending user evidence.*

**C-06 — FR-051 commits to per-application network attribution that no public API provides.** Measured 2026-08-09; narrowing proposed the same day and deferred once. The promise is still in the document.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of C-01 to C-06 gets a decision: accept, reject, or amend
- [ ] #2 Any accepted change is written into requirements.md as a dated amendment, not just agreed in conversation
- [ ] #3 C-01's decision covers what happens to the code already built, since FR-046 is implemented and shipping in the current build
- [ ] #4 C-02's spike is either scheduled or explicitly declined, so the default threshold stops being unexamined
<!-- AC:END -->
