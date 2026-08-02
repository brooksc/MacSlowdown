---
id: TASK-53
title: >-
  Storage surface and system signals on Now (FR-041, FR-007, FR-008, FR-010,
  FR-047)
status: To Do
assignee: []
created_date: '2026-08-02 18:15'
labels:
  - ui
  - phase1-catchup
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 1 of m-3. Memory pressure, swap, thermal, power and storage are all measured and tested, and none of them appear anywhere in the app.

Design reference: 1l for storage; the Now screen's signal tiles for the rest.

Two things this must get right, both already enforced in the model layer and easy to lose at the presentation layer: purgeable space is an estimate and not free space, and cached memory is not waste.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Memory pressure, swap activity, thermal state and power context appear on Now
- [ ] #2 Storage shows capacity, available and purgeable, with purgeable labelled an estimate
- [ ] #3 Volumes that cannot be read are listed with a reason rather than hidden
- [ ] #4 No copy describes cached memory as wasted or implies memory can be freed
<!-- AC:END -->
