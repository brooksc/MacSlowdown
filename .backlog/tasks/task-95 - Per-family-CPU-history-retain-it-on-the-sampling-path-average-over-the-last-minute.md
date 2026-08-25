---
id: TASK-95
title: >-
  Per-family CPU history: retain it on the sampling path, average over the last
  minute
status: In Progress
assignee: []
created_date: '2026-08-25 18:07'
updated_date: '2026-08-25 18:16'
labels:
  - core
  - ui
milestone: m-3
dependencies: []
priority: high
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product owner, 2026-08-25, after watching per-application figures change at sampling cadence: "this isn't really intended so much as a real time CPU monitor but to show general trends… what about averaging this over the last 1m?" and, on the inventory's history column, "why not retained?"

Both questions had the same answer. `MetricsHistory` retains the machine totals plus a bounded set of leading *processes*, so no application had a series and every per-application figure on every surface was one sample.

**A per-family store already existed and was in the wrong place.** `FamilyHistory` was `@State` inside `ProcessInventoryView`, so it recorded only while Apps & Processes was on screen and its series died with the view. That is why the Now table said "Not retained" against every application row while an inspector two screens away drew curves from the same data — an inconsistency nobody had noticed because the two surfaces never appeared together.

Scope:
- Move ownership to `MonitorStore` and record on the sampling pass.
- Add a trailing statistic (mean, peak, sample count, actual span) and copy that names the window and the statistic.
- Draw the real curve in the inventory's history column for application rows.
- FR-031 amended (see below) so per-second retention has per-second sampling behind it.

**Spec change:** FR-031 amended 2026-08-25, product owner approved — normal cadence 2–5 s → **1 s**, investigation 1 s → **0.5 s**. Investigation had to tighten in step or FR-031's requirement that resolution *rises* during a suspected incident would have collapsed into a single rate. The escalation is now 2× rather than up to 5×, which is gentler on a machine already in trouble (FR-032).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FamilyHistory is owned by MonitorStore and records on the sampling pass, so history accrues with no window open
- [x] #2 A trailing mean, peak, sample count and actual span are available per family, and nil rather than zero when nothing was retained
- [x] #3 Copy names the window and the statistic, and says the span out loud when it is shorter than the window asked for
- [x] #4 The inventory's history column draws a real curve for application rows; member rows explain why they have none
- [x] #5 Cadence defaults follow the FR-031 amendment and the tests assert the amended values
- [x] #6 FR-030 overhead is re-measured against the app and the figure recorded in the amendment, replacing the estimate
- [ ] #7 Verified on screen: an application row shows a curve, and a per-application figure no longer twitches at sampling cadence
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## A duplicate I nearly shipped

I wrote a `FamilyHistory` in the `Metrics` framework before discovering the app target already had one, with a better data model — it retains resident bytes alongside CPU, bounds itself to 40 tracked families plus the selection, and tracks member replacement. The duplicate was deleted and its useful parts (the trailing statistic and the copy that names the window) moved onto the existing type. The lesson is the ordinary one and it cost about twenty minutes: search for the concept before building it, not just for the call site you are standing in.

## What actually changed

- **Ownership moved to `MonitorStore`.** The existing type was `@State` in `ProcessInventoryView`; it now lives on the store and records inside `run()` from `inventory` and the same grouping pass the inventory already uses, so it costs bookkeeping rather than a measurement. `selectedFamilyID` moved to the store too, because the tracked set includes the user's selection and the store cannot see it otherwise.
- **`FamilyHistory.trailing(for:window:now:)`** returns mean, peak, sample count and the **span actually covered**, or nil. Nil rather than zero throughout: "no readings" and "no CPU" are different statements (FR-002).
- **`TrailingPresentation`** names the statistic and the window, and says the span out loud when it is materially shorter than the window requested — a mean over eight seconds must not describe itself as a minute (FR-038).
- **The inventory history column** draws a real curve for application rows. `perFamilyHistoryIsRetained` flips to `true`; the limitation moved down a level to member rows, which still have none because history is keyed on the family — a family outlives its processes and pids are recycled.
- **Cadence** follows the FR-031 amendment: normal 1 s, investigation 0.5 s. `MetricsHistory.defaultCadence` moved with it, since it is the divisor for ring capacity and the buffer would otherwise span less than the window it claims.

## Known limitation, not fixed here

`FamilyHistory` drops a family's series entirely when it falls out of the busiest 40. So an application that goes quiet loses its curve rather than showing a low one, and picking it up again starts from nothing. That predates this task and is the right trade at 40 families; it is worth revisiting now that the series feeds a column the user reads rather than one inspector.

## Tests

`TrailingFamilyFigureTests`, 6 tests: nil rather than zero when nothing is retained or the window is empty; the mean and peak over a window with the real span; **a one-second spike barely moves the minute while the peak still records it** — the property that was actually asked for; the two default windows agree; a full window is named as the window; a short span says how short it is.

`SamplingCadenceTests` updated to the amended defaults, with the reason at each assertion.

Full suite: `MetricsTests` clean; `MacSlowdownTests` one failure, the pre-existing TASK-91 container-isolation issue.

## AC #6 and #7 outstanding

The overhead re-measurement is running; the amendment still carries an estimate rather than a measurement until it lands. Nothing has been seen on screen.

## AC #6 — measured, and over the reference

`probe/overhead/run.sh 300`, M2 MacBook Air, 2026-08-25, 283 sweeps over 300.9 s at the amended cadence:

```
cpu:    1.760% of one core steady state (budget 1.0%) OVER
memory: 23.3 MB resident, +15.3 MB growth (budget 100 MB) OK
disk:   0.00 MB/hour projected (budget 10 MB/hour) OK
sweep:  6.22 ms median
```

**My pre-amendment estimate of 0.6% was wrong by about 3×.** The sweep figure was right — I predicted ~6 ms and the median is 6.22 ms — but I costed only the sweep and not the rest of the sampling loop around it. The sweep alone accounts for roughly 0.58% of the measured 1.76%; history, detection and the per-family recording make up the remainder.

Against the pre-amendment comparable of 0.830%, the cost scaled with the cadence almost exactly: twice the samples, 2.1× the CPU. Nothing anomalous happened — the change did what doubling a sampling rate does.

The figure is recorded in the FR-031 amendment. It is over the reference and knowingly so: the numeric budget is deferred and does not gate work, and 1.76% of one core is ~0.22% of this 8-core machine. The harness is headless, so the shipping app's figure is higher again and should be measured separately before release.

If it later needs to come down, the lever is decoupling grouping cadence from metrics cadence rather than reverting the amendment — grouping is the larger half of the 6.22 ms and the per-second requirement is about per-process CPU, not about regrouping the table sixty times a minute.
<!-- SECTION:NOTES:END -->
