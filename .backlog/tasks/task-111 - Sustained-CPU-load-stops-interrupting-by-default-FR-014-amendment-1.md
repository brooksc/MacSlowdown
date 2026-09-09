---
id: TASK-111
title: Sustained CPU load stops interrupting by default (FR-014 amendment 1)
status: In Progress
assignee: []
created_date: '2026-09-06 16:53'
updated_date: '2026-09-09 17:40'
labels:
  - core
milestone: m-2
dependencies:
  - TASK-109
priority: high
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follows from FR-063. On a developer's machine the most common cause of sustained high CPU is work the user started deliberately, so announcing it is usually telling someone their intended work is a problem.

**The new default policy:**

| Condition | Default |
|---|---|
| Sustained CPU load | **Recorded, not announced.** User may opt in. |
| Sustained memory pressure | **Announced** — a decision plausibly attaches; something can be closed. |
| Low storage | **Announced** — actionable and unambiguous. |
| Thermal pressure | **Recorded, not announced**; the machine already signals it. |

**The test is not severity, it is whether a decision plausibly attaches.** A condition the user can do nothing about, or caused on purpose, is recorded.

**This is a bet with a known risk, and it should be recorded as one.** A product that rarely interrupts may rarely be opened, and in practice "opt-in" and "off" are close to the same thing. The counter-argument is that a noisy product is uninstalled while a quiet one is merely underused, and that FR-064's reports are what will settle whether this default is right. Revisit after the field trial (TASK-111), not before.

**Also in scope:** the sensitivity options are mislabelled in their effect. They do not only change which severities announce — they also move the CPU threshold (92% / 85% / 75%), so "Tell me early" changes what *counts* as a condition, not merely what is said about it. The user-facing restatement must say so.

Depends on TASK-109 for the wording it announces with.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A sustained CPU condition is recorded and visible but sends no notification by default
- [x] #2 Memory pressure and low storage still announce
- [x] #3 CPU announcements can be enabled by the user, and the control says what it does
- [x] #4 The sensitivity restatement discloses that the options move the detection threshold, not only the announcement rule
- [x] #5 The bet and its risk are recorded so the default is revisited on evidence rather than drifting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Detection policy done 2026-09-08**, commit 2c65415. One criterion outstanding — see below.

**The rule lives on the condition.** `IncidentCondition.announcesByDefault`, written as a switch rather than a set so a new condition cannot be added without someone answering the question:

| Condition | Announces | Why |
|---|---|---|
| Memory pressure | yes | Something can be closed; the machine's behaviour will change |
| Low storage | yes | Actionable and unambiguous |
| CPU saturation | no | Usually work the user started; recorded and visible |
| Thermal pressure | no | The machine already signals it and nothing can be done |
| Repeated quits | no | Already demoted entirely; belt and braces |

`NotificationSettings.announcedConditions` is the opt-in, empty by default.

**Placed after the severity check on purpose**, so a *severe* CPU episode is still silent. That ordering is the point of the whole change: severity orders the measurement, it does not make the load actionable, and this product had been using it as though it did.

**Suppression here is about interrupting and never about recording.** The incident still opens, is still stored, is still on every live surface and in history. A test asserts it.

**The fixture problem, worth recording because it will recur.** Most notification tests used a CPU incident, so after this change they passed for the wrong reason — suppressed as unannounceable rather than by the muting, Focus, audio or escalation rule each was actually about. They moved to memory pressure. The one genuine end-to-end mute test opts CPU *in* instead, so the mute is still the operative rule; changing its condition would have hollowed out the test.

**Criterion #4 is not done** — the sensitivity restatement still describes the three options as changing which severities announce, when they also move the CPU threshold (92% / 85% / 75%). That is a Settings copy change and it belongs with the Settings design pass; it is the reason this task is In Progress rather than Done.

1151 passing.

**Criterion 4 done 2026-09-09** (worktree branch, not merged). `AlertSensitivity.restatement` now reads, for each option, "a condition starts once total CPU stays above N% of this Mac's capacity for D, and you hear about the ones rated X or worse" followed by `AlertSensitivity.thresholdCaveat` — "This moves the line itself, not just what gets said about it — a lower line records more conditions and shows more of them in the overview." Both halves are derived from `policy` and `minimumSeverity` rather than written out, so the sentence cannot drift from the thresholds; a test walks all three options and asserts each quotes its own CPU figure and carries the caveat.

Design 5g's other half is built with it: an Alerts-tab section, **Which of these should interrupt you?**, with a switch per resource condition, ordered defaults-first, each carrying `IncidentCondition.interruptionRationale` — including CPU's "usually it's work you started on purpose, and there's nothing for us to suggest. Still recorded, and in the overview." The rationale lives beside `announcesByDefault` in `NotificationPolicy.swift` so copy and behaviour cannot separate.

**Not seen on screen.** The strings are asserted by test; the Alerts tab itself is still on TASK-65.24's never-looked-at list.
<!-- SECTION:NOTES:END -->
