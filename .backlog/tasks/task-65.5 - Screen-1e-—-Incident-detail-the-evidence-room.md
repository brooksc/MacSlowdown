---
id: TASK-65.5
title: 'Screen 1e — Incident detail: the evidence room'
status: To Do
assignee: []
created_date: '2026-08-09 02:22'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1e.png`. Existing implementation: `IncidentDetailView` (TASK-52, TASK-23, TASK-26). Not compared against a current screenshot — no incident was open during the capture session, so the gap is unmeasured. Establish that first.

**What the design specifies**

Title bar: "Incident · Memory pressure, Thursday 3:12 PM" with Export… and Delete.

1. **Verdict in plain language**: "Your Mac ran out of comfortable memory for 11 minutes", severity chip, then a paragraph tying together the window, the swap written, the largest contributor, its trend, and how it ended.
2. **A confidence key stated up front** — Measured (pressure level, swap bytes, per-process resident memory) / Calculated (growth rate, contributor share) / Likely ("Chrome was the main cause"). This is FR-038 made visible as a legend rather than as scattered labels.
3. **Timeline**: "3:10 PM – 3:26 PM · 1-second samples" with the incident window shaded, three stacked series — memory pressure (peak: critical), swap written (4.1 GB total), memory by app (stacked resident memory) — and axis markers for trigger and recovery.
4. **What we found**, as four labelled paragraphs: Measured, Calculated, "Likely, moderate confidence", and **Ruled out** ("CPU averaged 22% and thermal state stayed nominal, so this wasn't a CPU or heat problem").
5. **What happened after you acted** — the FR-050 section. States what the user did, what changed over the next 3 minutes, a before/after pair (11.4 GB → 5.2 GB), and the disclaimer "We can't prove your tab closing caused the recovery, but the two line up."
6. **Events** — a timestamped list including our own behaviour ("3:14 Sampling raised to 1 s", "3:12 Pressure crossed warning for 90 s — incident opened").
7. **Conditions at the time** — power, low power mode, thermal state, free storage, profile active, and a build/schema footer ("App 1.0 (14) · rules r7 · schema 3") for FR-049.

**Why this one is the anchor**

Every rule in CLAUDE.md about not overstating causation is expressed concretely here: the confidence legend, the "Ruled out" paragraph, the refusal to claim the user's action caused recovery, and the recording of our own sampling changes as events in the same timeline as the incident.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The current IncidentDetailView is captured against a real incident and the gap against design/screens/1e.png is recorded before any work starts
- [ ] #2 The detail opens with a plain-language verdict and a visible legend distinguishing measured, calculated and likely (FR-038)
- [ ] #3 A timeline shows the incident window with the relevant series and the trigger and recovery points marked
- [ ] #4 A 'Ruled out' section states what the evidence excludes, not only what it suggests
- [ ] #5 Post-action outcome is reported as correlation with an explicit disclaimer, never as proven causation (FR-050)
- [ ] #6 The event list includes our own sampling-cadence changes alongside system events
- [ ] #7 Machine, power, thermal, storage, profile and build/schema context are recorded with the incident (FR-049)
<!-- AC:END -->
