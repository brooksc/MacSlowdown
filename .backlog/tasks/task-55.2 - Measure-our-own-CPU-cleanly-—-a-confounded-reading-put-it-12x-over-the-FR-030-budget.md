---
id: TASK-55.2
title: >-
  Measure our own CPU cleanly — a confounded reading put it 12x over the FR-030
  budget
status: Parked
assignee: []
created_date: '2026-08-09 03:12'
updated_date: '2026-08-09 03:18'
labels:
  - core
milestone: m-3
dependencies: []
parent_task_id: TASK-55
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recorded so it is not lost. **This is not a finding yet — it is a reading that needs redoing properly.**

While measuring memory for TASK-55.1, the running Debug app averaged **12.2% of one core over 755 s**, against FR-030's budget of a 1% idle median. That is 12x over. But the measurement is heavily confounded and must not be quoted as a result:

- Builds were running throughout, on several concurrent agents.
- The app raises its sampling cadence under load by design (FR-031), so a busy machine makes us sample harder — the load partly caused the number.
- The window state was not observable, so it is unknown whether the inventory was open and refreshing.
- It was a Debug build.

Against that, the headless `OverheadHarness` on the same day reported `0.830% CPU steady state OK` over 302 s — inside budget. So the harness and the running app disagree by roughly 15x, which is the same class of problem TASK-55 was created to solve for memory: the harness does not run SwiftUI, and the figure the budget applies to has to come from the app.

What is needed is a clean measurement: Release build, quiet machine, no concurrent builds, a stated window state, over at least 300 s, reported as a median rather than a mean so a startup burst does not dominate (TASK-62 established that the same distinction matters for identity resolution).

Note the outcome may be the same as TASK-55.1's: that the budget as written is not testable as stated, and needs rewording rather than the code needing a fix. Decide that from the measurement, not before it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CPU cost of the running Release app is measured on a quiet machine over at least 300 s, with no builds or other agents running, and the figure recorded as a median
- [ ] #2 The window state during measurement is stated -- which surface was open and whether it was refreshing
- [ ] #3 The measurement distinguishes normal cadence from investigation cadence, so a figure inflated by our own adaptive sampling is not read as steady-state cost (FR-031)
- [ ] #4 The gap between the headless harness figure and the running-app figure is explained, or the harness is stated as not representative for CPU as it already is for memory
- [ ] #5 If the measured figure exceeds FR-030's budget, either the cause is found and fixed, or an amendment to requirements.md is proposed for the user to approve -- the budget is not left silently breached
- [ ] #6 The confounded 12.2% reading is explicitly superseded in the notes so nobody quotes it later
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Parked 2026-08-08. The product owner deferred FR-030's numeric budget so functionality and UX are not blocked on optimisation; `requirements.md` and `CLAUDE.md` now record the deferral. A clean CPU measurement is still worth having before release, but it gates nothing now.

The confounded 12.2% reading remains superseded and must not be quoted. Revisit alongside TASK-55.1 when optimisation work resumes.
<!-- SECTION:NOTES:END -->
