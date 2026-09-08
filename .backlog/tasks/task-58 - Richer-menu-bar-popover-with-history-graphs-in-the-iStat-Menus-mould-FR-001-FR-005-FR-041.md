---
id: TASK-58
title: >-
  Richer menu bar popover with history graphs, in the a third-party menu bar monitor mould (FR-001,
  FR-005, FR-041)
status: To Do
assignee: []
created_date: '2026-08-08 19:37'
updated_date: '2026-08-09 21:32'
labels:
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: a third-party menu bar monitor' dropdown — CPU graph with recent history and per-core bars, load average, uptime, memory pressure and composition bars, per-disk free space, network graph with peaks and current rates, sensors.

Today our popover is a static list: severity, total CPU, three contributors, other applications, unattributed. It answers "what is busy now" and nothing about "what has been happening", even though FR-005 already retains at least 15 minutes of bounded history that nothing currently displays.

**In scope, and buildable on what exists:**
- CPU over time from the FR-005 ring buffer, with the unattributed share visible in the same chart rather than as a separate number — otherwise the graph would imply we can see more than we can.
- Memory pressure over time. Pressure, never percent-RAM-used, and never cached memory shown as waste (FR-007, DR-08).
- Aggregate disk read/write rates over time (FR-008, FR-009 — aggregate only; per-process I/O is blocked under the sandbox).
- Storage free space per volume, which the Storage pane already computes.
- Thermal state over time as a stepped band, since it is a state and not a scalar (FR-010).

**Out of scope, and why — do not build these by copying the reference:**
- **Sensors and temperatures.** Excluded by A-03 and FR-010: raw sensor values need undocumented SMC keys. a third-party menu bar monitor can show them; we cannot, and must not fabricate them. Note the reference screenshot itself reads "No Sensors Found".
- **Network graph.** FR-051 is Phase 4 and still unproven under the sandbox. Aggregate network is not specified at all. Needs a spike before it can be designed, not a chart borrowed from the reference.
- **Load average and uptime.** In no requirement. Load average in particular is widely misread — it is a run-queue length, not a percentage, and a figure of 18.45 on an 8-core machine invites exactly the wrong conclusion. Adding either needs a spec amendment first.

**Constraints that will shape this more than the visual reference does:**
- FR-030's budget. A popover redrawing charts at sampling cadence is a plausible way to become part of the slowdown. Refresh rate must be separated from sampling rate (DR-03), and the FR-030 harness must be re-run against the real app afterwards, as TASK-55 established.
- FR-034. A chart cannot be the only carrier of a value; every series needs a text reading, and severity must not be conveyed by colour alone. Charts need VoiceOver descriptions, not just labels.
- FR-002. A gap in history is a gap, drawn as one. Interpolating across a period when sampling fell behind would fabricate measurements.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The popover shows CPU, memory pressure and disk rates over the retained history window
- [ ] #2 Unattributed activity is visible in the CPU history rather than implied away by a chart of only what we can see
- [ ] #3 Every series carries a current text reading, so no value exists only as a shape
- [ ] #4 Charts have VoiceOver descriptions conveying trend and current value
- [ ] #5 Periods with no samples render as gaps, never interpolated across
- [ ] #6 Popover refresh is decoupled from sampling cadence, and FR-030 overhead is re-measured against the real app with the popover open
- [ ] #7 No temperature, load average, uptime or network series appears without a prior spec amendment
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Not started, at the product owner's explicit instruction:** they want to scope this in conversation first. Untouched on 2026-08-09 for that reason and no other — it is large, and the FR-005 history it would draw from is now materially better provisioned than when the task was written (incidents persist for 30 days, `retainedSamples` is reachable, `SparklinePresentation` exists), so the scoping conversation should start from what is now available rather than from the task's original assumptions.
<!-- SECTION:NOTES:END -->
