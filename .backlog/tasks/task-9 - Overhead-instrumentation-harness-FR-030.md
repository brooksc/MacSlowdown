---
id: TASK-9
title: Overhead instrumentation harness (FR-030)
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:32'
labels:
  - infra
milestone: m-1
dependencies:
  - TASK-4
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FR-030 targets are tests, not aspirations: idle CPU median <=1% of one core, resident memory <=100MB, disk writes <=10MB/hour absent incidents. Reuse the probe measurement code as the permanent harness.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Automated check fails the build when the CPU budget regresses
- [x] #2 Measured on reference hardware with documented conditions
- [x] #3 Resident memory stays under 100MB target
- [x] #4 Disk writes stay under 10MB/hour absent incidents
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OverheadHarness.swift plus FR030Budget, which holds the three limits in one place so code and tests cannot drift apart.

The harness runs the real sampling path -- enumerate, read metrics, attribute, resolve identity through the cache, prune, record history, flush -- so a regression anywhere in that chain surfaces here rather than in production.

Measured on reference hardware (AC#2), 30s run at 2s cadence, release build, Apple M2 (4P+4E, 8 logical), macOS 27:

  sweeps: 15 over 31.5s
  cpu:    0.379% of one core (budget 1.0%)  OK
  memory: 15.4 MB resident (budget 100 MB)  OK
  disk:   0.09 MB/hour projected (budget 10 MB/hour)  OK
  sweep:  3.47 ms median

- AC#1 The budget check is a test, so a regression fails `tuist xcodebuild test` and therefore the build. Budget constants are asserted against the values FR-030 states, so loosening the budget requires editing something that reads as a requirement change.
- AC#3 A separate test asserts resident memory does not grow without bound over a sustained run; history is a fixed-capacity ring and the identity cache is pruned every sweep, so growth stays inside allocator noise.
- AC#4 Disk traffic is measured from real flushes when the run is long enough, and otherwise projected from the encoded size at the configured flush interval.

Honest limitation on the disk figure: a 30s run only accumulates 15 of 451 history samples, so the file is small and 0.09 MB/hour understates steady state. The realistic worst case -- a full 15-minute window rewritten every flush interval -- is ~3.6 MB/hour and is covered by the TASK-10 persistence test, which asserts against the default configuration. Both are inside budget, but the harness number alone should not be read as the steady-state figure.

Test conditions are documented in the suite comment: these run under the test host alongside the rest of the suite, i.e. a busier machine than a shipped app on an idle desktop, making this a conservative check rather than a flattering one.
<!-- SECTION:NOTES:END -->
