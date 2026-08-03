---
id: TASK-35
title: User correction of attribution (FR-039)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:13'
labels:
  - core
milestone: m-3
dependencies: []
priority: low
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
GroupingCorrection in ApplicationPolicy.swift, applied through the existing GroupingOverrides.

- AC#1 Corrections are reversible: removing one restores the inferred grouping exactly, tested end to end against FamilyGrouper.
- AC#2 Raw PID samples remain intact. A correction only changes placement -- nothing in the snapshot, history or attribution is rewritten.
- AC#3 No correction uploads anything; the store is local and the app makes no network calls at all.

One design decision worth recording: corrections are keyed on the COMMAND NAME rather than on process identity. A correction must outlive the process it was made about -- the user is saying 'this kind of process does not belong here', and PIDs do not survive a relaunch. Tested by applying a correction to a process that reappears under a different PID.

That does mean a correction applies to every process sharing a truncated p_comm, which is the same 16-byte collision risk TASK-48 flagged. Acceptable here because a correction is user intent rather than a measurement, and it is reversible -- but worth remembering if corrections ever start driving anything automatic.
<!-- SECTION:NOTES:END -->
