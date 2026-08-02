---
id: TASK-21
title: 'Storage capacity and low-storage detection (FR-041, FR-042)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:37'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Values agree with a system reference within tolerance
- [ ] #2 Purgeable space not treated as guaranteed free space
- [ ] #3 Transient anomaly does not create an incident
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
StorageSignals.swift: VolumeCapacity, UnreadableVolume, StorageSnapshot, LowStorageDetector.

- AC#1 Capacity agrees with statfs -- the same source df reads -- within 2%, asserted by test. Tolerance rather than equality because APFS containers and the URL resource-value API round differently.
- AC#2 Purgeable space is a separate optional field, never folded into available, and documented in the type as 'an estimate, not space you have'. The caveat string is asserted to contain 'estimate', 'not space you have' and 'may not release'. This is the specific error FR-041 calls out.
- AC#3 Volumes that cannot be read are listed with an explanation rather than hidden, so the picture is visibly incomplete rather than silently wrong. Network volumes get a specific note. Removable volumes are excluded by default and can be included.

FR-042 detection uses BOTH a proportional and an absolute safeguard, which turns out to matter: 10% of a 4 TB disk is 400 GB and not a problem, while 10% of a 128 GB disk is. Tested both directions.

Transient anomalies cannot raise an incident: isSustained requires every reading in the window to be below threshold AND the window to span the required duration. Tested that a single reading, a 10s run against a 60s requirement, and a run with a recovery in the middle all fail to qualify.

Note: the sustained-detection logic lives here but is not yet wired to incident creation -- that belongs with the incident lifecycle in TASK-22.
<!-- SECTION:NOTES:END -->
