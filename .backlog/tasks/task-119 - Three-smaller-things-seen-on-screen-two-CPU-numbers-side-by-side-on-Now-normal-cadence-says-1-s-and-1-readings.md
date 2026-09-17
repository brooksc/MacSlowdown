---
id: TASK-119
title: >-
  Three smaller things seen on screen: two CPU numbers side by side on Now,
  "normal cadence" says 1 s, and "1 readings"
status: Done
assignee: []
created_date: '2026-09-17 02:30'
updated_date: '2026-09-17 18:16'
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
- [x] #1 Now carries one CPU figure per row, or the settled note in CLAUDE.md records why Now is a deliberate exception to the one-figure rule
- [x] #2 The footer's cadence label agrees with what the sampler is actually doing, and with FR-031's definition of normal versus investigation
- [x] #3 Our own CPU cost is re-measured on a real machine rather than in the VM, and the figure recorded — no budget gate, just a known number
- [x] #4 "1 readings" agrees in number, and the same is checked for the other counted nouns on that screen
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**All four settled 2026-09-17.**

**#1 — Now carries one CPU figure.** The rule was applied rather than excepted: the 2026-09-03 reasoning (two adjacent, differently-sampled figures invite a subtraction that means nothing) does not change with the screen, and nothing about Now makes it a special case. The "Now" column is gone; the heading is "CPU, 60 s mean", matching Apps & Processes word for word. The instant survives exactly where the settled note says it should — as the sparkline's live end in "Retained history", and in the row's accessibility label with "now" attached. Seen: `design/verified/2026-09-17/previews/now-table-900.png`.

**#2 — the footer label was already right, and so was the spec.** The task assumed FR-031 still said 2–5 s. It does not: FR-031 carries an **amendment dated 2026-08-25** moving normal cadence to 1 s and investigation to 0.5 s, approved in v1.3, with the reason recorded and the cost measured. So "Sampling every 1 s (normal cadence)" agrees with the sampler *and* with the specification, and there was nothing to fix. What was stale was `CLAUDE.md`, which still quoted the pre-amendment figures under Performance budget; corrected.

**#3 — re-measured on the real machine, not the VM.** `probe/overhead/run.sh 300`, M2 MacBook Air, 2026-09-17, on a quiet machine (no build running):

```
sweeps: 281 over 300.4s
cpu:    2.066% of one core steady state (budget 1.0%) OVER
memory: 20.8 MB resident, +12.9 MB growth (budget 100 MB) OK
disk:   0.00 MB/hour projected (budget 10 MB/hour) OK
sweep:  10.09 ms median
whole:  2.195% over the whole run, including 446 ms of startup
```

Against FR-031's recorded 2026-08-25 measurement of **1.760% and a 6.22 ms sweep median**, both have risen — CPU by ~17%, the sweep median by ~62%. **Recorded, not acted on**: the numeric budget is deferred and does not gate work (product owner, 2026-08-08), and this task's own criterion asks for a known number rather than a fix. Two caveats that must travel with the figure: the harness is headless and runs no SwiftUI, so it under-reads the shipping app; and the VM's 8–12.6% is not comparable at all, being 4 vCPU carved out of this same fanless host.

The sweep-median rise is the part worth a later look, since it is the half of the cost that scales with what the app does rather than with cadence.

**#4 — "1 readings" agrees in number.** `StorageTrend.insufficientHistory` now pluralises. The other counted nouns on that screen were checked at the same time: `StorageTrendAnalysis.describe(_:)` already agrees its own days/hours/minutes, with singular cases for each.
<!-- SECTION:NOTES:END -->
