---
id: TASK-53
title: >-
  Storage surface and system signals on Now (FR-041, FR-007, FR-008, FR-010,
  FR-047)
status: Done
assignee: []
created_date: '2026-08-02 18:15'
updated_date: '2026-08-08 15:23'
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
- [x] #1 Memory pressure, swap activity, thermal state and power context appear on Now
- [x] #2 Storage shows capacity, available and purgeable, with purgeable labelled an estimate
- [x] #3 Volumes that cannot be read are listed with a reason rather than hidden
- [x] #4 No copy describes cached memory as wasted or implies memory can be freed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified visually on macOS 27.0 (26A5388g), Mac14,15, 8 cores / 24 GB.

Storage pane renders the startup volume with a capacity bar and four figures, each carrying its evidence class: Available 29.95 GB (Measured), In use 964.71 GB (Calculated), Capacity 994.66 GB (Measured), Purgeable 18.72 GB (Estimate). Available + In use = Capacity exactly, so the breakdown accounts for the whole volume.

Cross-checked against `df -g`: capacity 926 GiB = 994.7 GB decimal, matches. Available reads 29.95 GB against df's 27 GiB (29.0 GB) because the app uses volumeAvailableCapacityForImportantUsage, which counts purgeable space macOS would reclaim under pressure. That is the honest figure for 'space you can actually use', and purgeable is shown separately with the caveat 'Purgeable space is an estimate of what macOS thinks it could reclaim. It is not space you have, and macOS may not release it.'

The Now pane's system signals also verified in the same session: memory pressure Normal, thermal state Nominal, power 'On external power - battery 99% - charging', disk 127.3 MB/s read / 3.6 MB/s write (a rate from counter deltas, not a cumulative total).

Criterion #3 is implemented and unit-tested but not visually exercised: this machine mounts only Macintosh HD, so the 'Not measured' section had nothing to render. StorageView calls unreadableSection whenever StorageSnapshot.unreadable is non-empty, showing each volume's name and its explanation rather than dropping it. Worth re-checking on a machine with a network or unmounted volume.

Criterion #4 checked by grep across MacSlowdown/Sources and Metrics/Sources for 'free up', 'freed', 'wasted', 'clean', 'optimise', 'boost': the only hits are comments explaining why that language is avoided. No user-facing string uses any of it.
<!-- SECTION:NOTES:END -->
