---
id: TASK-100
title: >-
  The status word flickers, and the incident never opens: both judge instants
  where they should judge intervals
status: In Progress
assignee: []
created_date: '2026-08-31 19:36'
updated_date: '2026-08-31 19:36'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed on screen by the product owner, 2026-08-31, with an a third-party menu bar monitor reading alongside as the control.

**What they saw.** The popover's headline cycling between "Your Mac is running normally", "working hard" and "heavily loaded" while the machine's load was in fact steady — iStat showing 53% user, 33% system, 14% idle, held over minutes. Their words: it "reduces confidence".

**And, in the same screenshot, worse.** The popover read *"Your Mac is heavily loaded"* — CPU 792% of one core, 99% of an 8-core machine — directly above *"No slowdowns since 11:22 AM, when monitoring started"*, taken at 12:18. Nearly an hour of heavy load and not one incident.

Two symptoms, one disease: **the app judges instants where the requirement is about intervals.**

### 1. The verdict read a single sample

`MonitorStore.severity` was computed from `attribution.totalBusyPercentOfOneCore` — the newest reading alone — and mapped straight onto three bands. At a one-second cadence, a machine anywhere near a boundary changes word every second. It drives the Now headline, the CPU card, the menu bar glyph and its spoken label, so all four flickered together.

Fixed by making it a **trailing mean over 30 s** with a **deadband on the way down** (`Severity.settled`). Escalation stays immediate — a machine getting worse is news — but a step down requires clearing the band being left by a margin.

### 2. The sustained-duration clock reset on every dip

`IncidentDetector.observe` cleared `state.breachStart[condition]` on **any** sample that did not breach. Real load does not sit still: a machine steady at 86% crosses an 85% threshold several times a minute, so the three-minute clock restarted constantly and the incident never opened.

The FR-031 cadence amendment made this worse rather than causing it — at one second instead of two there are twice as many chances to sample a dip.

Fixed with `IncidentPolicy.breachDipTolerance` (15 s): a gap longer than that still throws the clock away, a briefer one does not. The condition must still be breaching *now* to count as sustained, so a genuinely intermittent spike accumulates nothing.

**This is a behaviour change to a documented rule and may want the product owner's eye.** FR-006 requires detection to be sustained rather than transient, and the argument is that an interval with brief dips in it is still that interval — the old reading of "sustained" was "uninterrupted at every sample", which no real workload satisfies. If that reading is wanted instead, the tolerance goes to zero and this defect returns.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The status word holds steady while a reading hovers on a band boundary
- [x] #2 Escalation is still immediate; only de-escalation waits for the margin
- [x] #3 A machine that goes quiet always reaches normal, so the deadband cannot strand a word
- [x] #4 A slowdown with brief dips in it opens one incident
- [x] #5 A run genuinely broken by a quiet spell still opens none
- [ ] #6 Verified on screen: the headline does not change word while the machine's load is steady
- [ ] #7 Verified on screen: sustained heavy load opens an incident within about the sustained duration
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The verdict

`MonitorStore.severity` becomes a stored property updated on the sampling pass, from `trailingBusyShare(window:)` — the mean share of machine capacity over the last 30 s, nil rather than zero when nothing is retained. `Severity.settled(_:previous:breachingAt:margin:)` adds the deadband: up immediately, down only once clear of the band being left by 0.05.

Making it stored rather than computed also stops it being recalculated on every `body` evaluation, which it was.

Five tests in `SettledSeverityTests`, including the two that matter: a reading hovering across the line holds its word through six samples, and a machine that goes quiet always reaches normal, so the deadband cannot strand a word.

## The clock

`IncidentPolicy.breachDipTolerance`, 15 s, and `State.lastBreachAt` to measure the gap. `observe` now `continue`s past a dip inside the tolerance rather than clearing `breachStart`.

`IncidentTests.brokenRunResets` asserted the old rule — one dip at 10 s spacing resets everything — so it was rewritten around a genuine quiet spell (a full minute), which still accumulates nothing. Its counterpart, `briefDipsSurvive`, dips every fortieth second across 220 s and expects exactly one incident. The original intent is preserved and the boundary is now asserted from both sides.

## Test state

1134 passing. `CPUWorkloadTests` and `EndToEndIncidentTests` failed on the full run and passed in isolation — the product owner's machine was at 792% of one core at the time, which is exactly what those tests report honestly rather than a regression.

## Not verified

Both on-screen criteria. The flicker is the whole complaint and only a person watching the headline can say it has stopped; likewise whether sustained load now opens an incident on the real machine within about three minutes.
<!-- SECTION:NOTES:END -->
