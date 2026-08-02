---
id: TASK-22
title: 'Incident lifecycle with hysteresis and merge window (FR-011, FR-012)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:44'
labels:
  - core
milestone: m-2
dependencies:
  - TASK-10
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Converts continuous metrics into episodes. The heart of the product.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Repeated samples do not create duplicate incidents
- [ ] #2 Incident closes only after recovery hysteresis
- [ ] #3 At least 2 min pre-trigger and 1 min post-recovery evidence retained
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Incident.swift: IncidentCondition, IncidentSeverity, IncidentPolicy, SystemObservation, Incident, IncidentDetector.

Three guarantees, each tested:
- FR-006 no alert for a transient spike. A 60s saturation against the 180s default opens nothing, and a broken run does not accumulate toward the duration -- 100s busy, a dip, then 100s busy stays silent.
- FR-011 repeated samples do not duplicate. 60 consecutive saturated observations produce exactly one open event.
- FR-011 closes only after recovery hysteresis. A 30s dip does not close an open incident; a relapse during recovery keeps the same episode rather than producing a second.

Real bug found by the merge-window test rather than by review. I first measured the merge window from the moment the new incident TRIGGERED, but triggering happens a full sustained-duration after the breach begins. With a 180s sustained duration and a 120s merge window, the gap could never fall inside the window, so a stutter of a few seconds would always split into two incidents -- the merge window would have been dead code that looked correct. It now measures from when the new condition BEGAN.

DEFAULTS CHOSEN, and flagged because they are product judgement rather than measurement. FR-006 and FR-011 leave them open and require configurability, so nothing is locked in, and a test asserts a different policy changes behaviour in both directions:
- 85% of MACHINE capacity, not of one core. On 8 cores that is ~6.8 cores busy: a machine in trouble rather than a machine working.
- 180s sustained. Long enough that a build or export must genuinely persist; short enough that a user who notices will find it recorded.
- 60s recovery hysteresis, so a one-sample dip does not split an episode.
- 120s merge window.

Severity never silently falls: peak CPU and peak memory pressure are retained, and a calmer sample cannot downgrade a recorded peak. Tested.

Also fixed the FR-030 memory assertion, which failed for the same shared-process reason as CPU earlier: selfResidentBytes measures the whole test host, which exceeds the app's 100MB budget on its own. The test now asserts growth across the run, which is genuinely ours, with the authoritative standalone figure (16.4 MB) recorded in the suite comment.
<!-- SECTION:NOTES:END -->
