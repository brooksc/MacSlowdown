---
id: TASK-119
title: >-
  Three smaller things seen on screen: two CPU numbers side by side on Now,
  "normal cadence" says 1 s, and "1 readings"
status: To Do
assignee: []
created_date: '2026-09-17 02:30'
labels:
  - ui
milestone: m-1
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All three seen 2026-09-16 in the running app on macOS 26.6.2 in a VM. Grouped because each is small; the first is the one that matters.

### 1. The Now table shows two CPU numbers side by side

Its columns are **App · Now · Last minute · Resident memory · Retained history · Age**, and the first two are both CPU percentages, read at 9.0% and 9.0% for MacSlowdown and 4.9% / 5.6% for System processes.

This is the arrangement the 2026-09-03 decision explicitly ruled out. From `CLAUDE.md`: the Apps table carries one CPU figure, the 60 s mean, and "the instantaneous reading survives as the sparkline's live end and in the accessibility label — **never as a second number beside the first, which invites a meaningless subtraction**."

That decision was applied to Apps & Processes, which now reads "CPU, 60 s mean" with a sparkline — correct, and confirmed on screen. **Now was not brought with it.** Either the reasoning applies here too and this table should lose one of the two, or Now is a deliberate exception and the settled note should say so. It cannot be both.

### 2. The footer calls 1 s the normal cadence

Every screen's footer reads **"Sampling every 1 s (normal cadence)"**. FR-031 sets normal cadence at roughly 2–5 s and reserves ~1 s for investigation. So either the app is sampling faster than the spec's normal rate, or it is in investigation cadence and calling it normal — and the label is wrong either way.

Not cosmetic: FR-030's overhead is a direct function of cadence, and the same footer reported MacSlowdown itself at **8–12.6% of one core** across the captures. That is well above the ≤1% reference figure. The budget is deferred and does not gate work, so this is not a failure — but a 1 s cadence is the obvious first explanation and it is worth knowing which of the two facts is the bug. Measure on a real machine before concluding: the VM has 4 vCPU on a fanless host and is not representative.

### 3. "1 readings over 1 minute"

On Storage: *"Not enough history for a trend — 1 readings over 1 minute."* Singular/plural is not agreed. The surrounding copy is careful, which makes this stand out more than it otherwise would.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Now carries one CPU figure per row, or the settled note in CLAUDE.md records why Now is a deliberate exception to the one-figure rule
- [ ] #2 The footer's cadence label agrees with what the sampler is actually doing, and with FR-031's definition of normal versus investigation
- [ ] #3 Our own CPU cost is re-measured on a real machine rather than in the VM, and the figure recorded — no budget gate, just a known number
- [ ] #4 "1 readings" agrees in number, and the same is checked for the other counted nouns on that screen
<!-- AC:END -->
