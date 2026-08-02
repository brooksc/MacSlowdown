---
id: TASK-24
title: Adaptive sampling cadence (FR-031)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:51'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cadence transition does not lose samples
- [ ] #2 User can inspect current cadence
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SamplingCadence.swift: SamplingMode, SamplingCadence, CadenceController.

- AC#1 No sample is lost across a transition. The controller only ever chooses the NEXT interval -- it never cancels an in-flight sample or resets a schedule mid-flight -- so a mode change cannot create a gap. The test drives 41 observations through a quiet/breach/recovery/quiet sequence and asserts every one was counted, with at least one rise and one fall in between. A separate test asserts steady state produces zero mode changes, so there is no churn.
- AC#2 The cadence describes itself: interval, mode, and a plain-language reason. 'Sampling every 1 s - investigation - an incident is open'. The pre-trigger reason is distinct from the open-incident one, so a user inspecting it learns why rather than just how fast.

Two judgements worth noting:
- Resolution rises on a SUSPECTED incident, not only a confirmed one. FR-031 asks for higher resolution on a suspected incident, and waiting for the trigger would miss the 3 minutes of evidence leading up to it -- exactly the window FR-012 wants retained.
- Elevated sampling lingers 60s after conditions clear, so the recovery window is captured at full resolution rather than dropping to normal the instant things improve. FR-012 wants post-recovery evidence, and it would be self-defeating to reduce resolution precisely when verifying recovery.

Normal (2s) is deliberately slower than investigation (1s), which is what keeps the FR-030 idle budget met; a test asserts the ordering so it cannot be inverted by a careless edit.

Not yet wired into MonitorStore's loop -- the store currently samples at a fixed cadence. Wiring belongs with the incident integration.
<!-- SECTION:NOTES:END -->
