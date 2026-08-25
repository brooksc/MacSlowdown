---
id: TASK-92
title: >-
  MemoryPressureMonitor seeds from the live machine, so three tests fail
  whenever the Mac is under real pressure
status: To Do
assignee: []
created_date: '2026-08-25 17:44'
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
- [ ] #1 The three tests pass on a machine already at warning or critical memory pressure
- [ ] #2 The product still seeds from the live level at construction, so a monitor started under pressure does not misreport its first transition
- [ ] #3 The seam is a parameter rather than a test-only branch inside the type
- [ ] #4 CLAUDE.md's list of machine-sensitive tests is updated, or these are removed from it because they are no longer machine-sensitive
<!-- AC:END -->
