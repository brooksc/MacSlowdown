---
id: TASK-92
title: >-
  MemoryPressureMonitor seeds from the live machine, so three tests fail
  whenever the Mac is under real pressure
status: Done
assignee: []
created_date: '2026-08-25 17:44'
updated_date: '2026-08-26 18:35'
labels:
  - infra
milestone: m-3
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second instance of the class TASK-91 records, found 2026-08-25 on a machine running LM Studio, Xcode and a build (29% memory free, live pressure `warning`).

`MemoryPressureMonitor.init` seeds its level from `MemorySignals.currentPressureLevel()` — a `sysctl` read of the real machine (`MemorySignals.swift:130-134`). Three tests in `MemoryPressureMonitorTests` construct a monitor and then record `.warning`, assuming the starting level is `.normal`:

- `transitionRecorded` — `#require(monitor.record(.warning))` returns nil, because recording the level it is already at is not a transition
- `repeatsAreNotTransitions`
- `everyChangeIsRecorded`

All three pass on an idle Mac and fail on a busy one, which makes them look flaky when they are in fact reporting the machine honestly — the same shape as the three CPU tests CLAUDE.md already warns about, except that these have no guard and no explanatory message.

Seeding from the live level is right for the product: a monitor that started at `.normal` on a machine already under pressure would misreport the first transition. So the fix belongs in the tests, not the behaviour — an injectable initial level, or a construction path that takes the starting level as a parameter and defaults to the sysctl read.

Related: TASK-91 (app-hosted tests read the real container). Same root cause, different mechanism: a test asserting on the developer's live world.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The three tests pass on a machine already at warning or critical memory pressure
- [x] #2 The product still seeds from the live level at construction, so a monitor started under pressure does not misreport its first transition
- [x] #3 The seam is a parameter rather than a test-only branch inside the type
- [ ] #4 CLAUDE.md's list of machine-sensitive tests is updated, or these are removed from it because they are no longer machine-sensitive
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`MemoryPressureMonitor.init` takes an `initialLevel` defaulting to `MemorySignals.currentPressureLevel()`, so the product behaviour is unchanged — a monitor built with no argument still seeds from the live machine, which it must, or one started on a Mac already under pressure would report a recovery that never happened.

The four tests that assumed a starting level now say so. Two new tests in `MemoryPressureMonitorSeedTests` hold the product side in place: the default really is the live level, and an explicit level is honoured. Without the first of those, someone could "fix" a future failure by changing the default and nothing would object.

AC #4 (updating CLAUDE.md's machine-sensitive list) is left for the CLAUDE.md pass — these tests are no longer machine-sensitive, so the entry to make is a removal rather than an addition, and there is no entry today because they were never listed.
<!-- SECTION:NOTES:END -->
