---
id: TASK-10
title: Bounded rolling history ring buffer (FR-005)
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:28'
labels:
  - core
milestone: m-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Default history covers at least 15 minutes. Storage format is open, but must meet the FR-030 disk budget -- validate write amplification before committing to SwiftData/CoreData.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Default history at least 15 minutes
- [x] #2 Memory and disk budgets met
- [x] #3 Restart persistence configurable
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MetricsHistory.swift. Fixed-capacity ring buffer of aggregate + leading-contributor samples, with optional persistence.

- AC#1 Default retention is 15 minutes at a 2s cadence. Capacity is retention/cadence + 1, so the retained window spans the full 15 minutes rather than falling one sample short; a test fills past capacity and asserts coveredDuration >= 900s.
- AC#2 Memory is bounded by construction: appending past capacity evicts the oldest, tested by appending 500 samples to a 12-slot buffer and asserting the survivors are the most recent. A full window encodes to ~300KB, a rounding error against the 100MB resident budget. Only the top 5 contributors are retained per sample, not the whole process table -- retaining every process every interval would blow both budgets for evidence nobody reads.
- AC#3 HistoryPersistence is .memoryOnly (writes nothing, verified) or .acrossRestarts. Round-trip, capacity-truncation on restore, and tolerance of missing/corrupt state are all tested. History is evidence, not configuration, so unreadable state never blocks startup.

The disk budget caught a real design error rather than rubber-stamping one. My first implementation flushed every 60 seconds; because persisting is a whole-file rewrite and a full window is ~300KB, that costs ~19 MB/hour against FR-030's 10 MB/hour cap -- nearly double. Fixed by setting defaultFlushInterval to 5 minutes (~3.6 MB/hour), with the arithmetic documented at the constant so it is not silently changed later. The cost is losing at most five minutes of history to an unclean termination, which is acceptable for evidence. The test asserts the DEFAULT configuration fits, since that is what ships.

Note for TASK-9: this is the first code that writes to disk, so the overhead harness can now measure the disk budget for real rather than trivially.

Not yet wired into a sampling loop -- that belongs with the store in TASK-12.
<!-- SECTION:NOTES:END -->
