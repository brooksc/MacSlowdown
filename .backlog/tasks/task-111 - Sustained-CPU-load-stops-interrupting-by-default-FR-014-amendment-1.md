---
id: TASK-111
title: Sustained CPU load stops interrupting by default (FR-014 amendment 1)
status: To Do
assignee: []
created_date: '2026-09-06 16:53'
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
- [ ] #1 A sustained CPU condition is recorded and visible but sends no notification by default
- [ ] #2 Memory pressure and low storage still announce
- [ ] #3 CPU announcements can be enabled by the user, and the control says what it does
- [ ] #4 The sensitivity restatement discloses that the options move the detection threshold, not only the announcement rule
- [ ] #5 The bet and its risk are recorded so the default is revisited on evidence rather than drifting
<!-- AC:END -->
