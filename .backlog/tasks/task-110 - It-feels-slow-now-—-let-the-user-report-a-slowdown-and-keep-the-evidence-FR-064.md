---
id: TASK-110
title: >-
  "It feels slow now" — let the user report a slowdown, and keep the evidence
  (FR-064)
status: To Do
assignee: []
created_date: '2026-09-06 16:53'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
type: feature
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**The single most valuable thing in either review, and the only instrument that can tell us what we miss.**

The product cannot distinguish a busy machine from a slow one and has no way to learn. A verdict on our own alerts ("was this useful?") can only ever measure the events we detected — it is precision with no recall, and it is blind to the afternoons someone lost while we recorded nothing unusual. Those are the failures that lose a user permanently.

A user-initiated report samples the population that matters.

**What it is.** One gesture, from a persistently reachable place — the menu bar is the obvious candidate — that says *it's slow now*. No form, no category, no severity. A second affordance offers "a few minutes ago" for the case where they only think to tell us afterwards.

**What happens.** The surrounding evidence is preserved on the same footing as an incident, marked user-provided (FR-038), kept under the same retention and privacy rules (FR-029), and never transmitted. **A report that matches no detected condition is a first-class result, not an error** — it is in fact the most informative kind, because it is a slowdown we missed.

**What it must not do.** Ask the user to describe or classify it; they are trying to get back to work. Respond by insisting nothing was wrong — everything we measured may well have looked normal, and that is a fact about our instruments, not about their afternoon. Take the report and never refer to it again, which makes the gesture extractive.

**Why this and not the verdict tap first.** They answer different questions and both may eventually be wanted, but this one is strictly more informative: it captures misses as well as hits, and it does not depend on us having interrupted in the first place. Keep "was this a slowdown?" separate from "was this alert useful?" — a real slowdown can still produce a late or unhelpful alert.

Blocks TASK-111 (the field trial), which has nothing to measure without it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A slowdown can be reported in one gesture from a persistently reachable surface, with no form and no required classification
- [ ] #2 A retrospective report covering the recent past is possible
- [ ] #3 Evidence around a report is retained under the same retention and privacy rules as an incident
- [ ] #4 A report matching no detected condition is preserved and shown as a result in its own right
- [ ] #5 Nothing about a report leaves the machine
- [ ] #6 Reports are visible afterwards, so the gesture returns something to the user
<!-- AC:END -->
