---
id: TASK-68
title: >-
  Incidents don't record what they were attributed to, so history can't say what
  caused them
status: To Do
assignee: []
created_date: '2026-08-09 05:01'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-65.6 while building the incidents history screen. Distinct from TASK-66: that is app-layer wiring of capabilities the framework already has, this is data the framework never captures in the first place.

`Incident` carries id, times, conditions, severity and two peaks. **It records no attribution.** `MonitorStore.attribution` is a *live* reading of what is busy now, not a snapshot of what was busy during the incident. Four consequences, each of which forced an honest omission in the UI rather than a guess:

**1. A closed incident cannot name an application.** The design's row title is "CPU maxed out — Xcode". That is not reconstructible after the fact. TASK-65.6 names an app only on an *open* incident, with the caveat "largest contributor we can measure right now — heuristic, not a cause", and names none on closed rows, with a footer explaining why.

**2. Application recurrence is uncomputable** — so "Chrome appears in 5 of them", the pattern summary that is the whole point of design 1f, cannot be built. TASK-65.6 substituted recurrence of the *condition* ("CPU saturation in 3 of them"), gated at >=3 incidents with >=3 sharing it. Useful, but much weaker: a user wants to know which app keeps doing this.

**3. "Recovered after you acted" is not derivable.** `ActionVerification` exists but is never linked to an incident and `MonitorStore` never stores one. TASK-65.6 accepts one (requiring it to have run and to fall inside the incident window) and the app passes nil. It refused to infer user action from timing, so the row reads "recovered — no action was recorded" rather than the design's wording. That distinction matters: FR-050 forbids treating correlation as outcome.

**4. "Not alerted — you marked X as expected" is not derivable.** `SuppressedDetection` exists but is not keyed to an incident. Same treatment.

Both undelivered branches are already unit-tested in `IncidentHistory`, so wiring them later is a data change rather than a UI change.

**Also found: retention is not what the design says.** History is **20 incidents, in memory, not persisted** — not 30 days. TASK-65.6's footer states the real behaviour and a test asserts the string does *not* claim "30 days". Whether that should change is part of the still-undecided persistence/retention question (see `CLAUDE.md`, "Undecided — ask, don't assume"), which is the product owner's call and must not be settled by an implementer.

The right fix is probably to capture an attribution snapshot when an incident opens and update it while open, so a closed incident carries the evidence it was judged on — which is also what FR-013's "evidence-based summary" and FR-049's machine context imply. Confirm the shape against the spec before building.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An incident retains the attribution it was judged on, so a closed incident can state which application it was attributed to without re-reading live state
- [ ] #2 Any application named on a historical incident carries the confidence label it was recorded with, and is never presented as a proven cause (FR-013, FR-038)
- [ ] #3 Recurrence across incidents can be computed by application, not only by condition, so the history screen can state that one app appears in several
- [ ] #4 A user action taken during an incident is linked to it, so 'recovered after you acted' is stated only when an action was actually recorded -- never inferred from timing (FR-050)
- [ ] #5 A detection suppressed by a user policy is linked to the incident it suppressed, so history can say why it was not alerted (FR-016)
- [ ] #6 The real retention behaviour and the interface's description of it agree, whatever the persistence decision turns out to be
<!-- AC:END -->
