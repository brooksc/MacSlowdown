---
id: TASK-55.1
title: >-
  Our own resident memory reads 3-22x the FR-030 budget, and two surfaces
  disagree
status: To Do
assignee: []
created_date: '2026-08-09 02:14'
labels:
  - core
milestone: m-3
dependencies: []
parent_task_id: TASK-55
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed while screenshotting the running Debug app on macOS 27. Not measured rigorously — that is the work.

TASK-55 measured the real app at **92 MB** against FR-030's 100 MB budget and closed on that. What the app displayed during this session:

- Now screen, `MacSlowdown itself:` line — **418.4 MB**, and **307.4 MB** in a sample a few minutes later.
- Apps & Processes, the `MacSlowdown` row — **2.26 GB**, with a process count of 1.

Two problems, and they should be separated:

1. **The absolute figure.** Even the smallest of these is over three times the 100 MB budget; the largest is 22x. Either something regressed since TASK-55, or 92 MB was measured under conditions the app does not normally run in. A tool that must not become part of the slowdown cannot hold 2 GB.

2. **The two surfaces disagree.** Both paths read `residentBytes` — `Presentation.selfCost` (via `MonitorStore.ownResidentBytes`) for the Now line, and `InventoryRow`'s family sum for the table row. For a family with one process those should be the same number. The samples were minutes apart so the gap is not proven to be a code difference, but a 5x spread between two readings of the same quantity needs explaining before either is trusted.

Note this was a Debug build with SwiftUI previews linked; measure Release before drawing conclusions. Do not "fix" this by changing which number is displayed — establish what the real figure is first.

Related: `MonitorStore.swift:86-101` carries the reasoning behind measuring from the app rather than the headless harness, and `isWithinMemoryBudget` compares against `FR030Budget.residentBytes`. Nothing currently surfaces when that check fails.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Resident memory of the running Release app is measured over a sustained run of at least 300 s and the figure recorded, including whether it is steady or climbing
- [ ] #2 The Now screen's self-report and the Apps & Processes row for MacSlowdown show the same value at the same moment, or the interface explains why they differ
- [ ] #3 If the measured figure exceeds FR-030's 100 MB budget, either the cause is found and fixed, or requirements.md is amended with the measured figure and a stated reason -- the budget is not left silently breached
- [ ] #4 A sustained run distinguishes a fixed cost from growth over time, so this is not reported as a leak without evidence (FR-044)
- [ ] #5 The result is recorded where the next person will find it, including whether TASK-55's 92 MB figure still reproduces and under what conditions
<!-- AC:END -->
