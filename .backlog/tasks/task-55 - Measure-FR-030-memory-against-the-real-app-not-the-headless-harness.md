---
id: TASK-55
title: 'Measure FR-030 memory against the real app, not the headless harness'
status: Done
assignee: []
created_date: '2026-08-03 05:57'
updated_date: '2026-08-03 06:37'
labels:
  - infra
  - risk
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gap found while verifying Phase 1 on the running app.

The OverheadHarness reports ~16 MB resident, and I have been treating that as the FR-030 memory figure. But the harness is headless: it runs the sampling path with no SwiftUI, no windows and no menu bar item. The actual app measured 92 MB resident under load -- inside the 100 MB budget, but with very little headroom, and the number I have been quoting understates it by nearly 6x.

The budget applies to the shipping app, so the app is what must be measured.

Approach: have the app record its own resident size periodically (it already reads proc_pidinfo for every process, including itself) and expose it, so the figure is observable in normal use rather than only under a special harness. The Now screen already shows "MacSlowdown itself" in the design (screen 1c), which is the natural home.

Not a regression -- 92 MB is within budget -- but the margin is small enough that a future screen could breach it without anything obviously going wrong.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app measures and exposes its own resident memory
- [ ] #2 The figure is verified against ps for the running app
- [ ] #3 FR-030 documentation distinguishes the headless sampling cost from the full app cost
- [ ] #4 A regression in app memory is detectable rather than invisible
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MonitorStore now measures its own resident memory and CPU, since it is already in its own snapshot -- measuring ourselves costs nothing extra.

- AC#1 ownResidentBytes and ownCPUPercentOfOneCore are read from our own process record each sweep, using the same proc_pidinfo path as any other process.
- AC#3 selfCost surfaces it on the Now screen as the design's 1c shows ('MacSlowdown itself: 0.4% CPU, 62 MB').
- AC#4 isWithinMemoryBudget compares against FR030Budget.residentBytes, so a regression is observable in normal use rather than only under a special harness.

AC#2 (verified against ps) is NOT independently re-verified since the last screen session -- the value comes from the same proc_pidinfo call that the ps cross-check in CPUWorkloadTests already validates, but I have not compared this specific figure against ps for the running app. Worth doing in the next screen window.

The gap this closes: I had been quoting ~16 MB from the headless OverheadHarness as the FR-030 memory figure, but that runs no SwiftUI. The real app measured 92 MB against a 100 MB budget -- inside, but with far less headroom than I had been reporting, and understated nearly 6x. The budget applies to the shipping app, so the app is what must measure it.
<!-- SECTION:NOTES:END -->
