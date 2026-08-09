---
id: TASK-65.5
title: 'Screen 1e — Incident detail: the evidence room'
status: In Progress
assignee: []
created_date: '2026-08-09 02:22'
updated_date: '2026-08-09 03:24'
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
- [x] #2 The detail opens with a plain-language verdict and a visible legend distinguishing measured, calculated and likely (FR-038)
- [ ] #3 A timeline shows the incident window with the relevant series and the trigger and recovery points marked
- [x] #4 A 'Ruled out' section states what the evidence excludes, not only what it suggests
- [x] #5 Post-action outcome is reported as correlation with an explicit disclaimer, never as proven causation (FR-050)
- [ ] #6 The event list includes our own sampling-cadence changes alongside system events
- [ ] #7 Machine, power, thermal, storage, profile and build/schema context are recorded with the incident (FR-049)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Gap analysis — from code, NOT from a running app

Criterion #1 asks for a capture against a real incident. **Not done, and not
doable here**: this agent was forbidden the screen, so the app was never
launched and no incident was observed. The comparison below is a reading of
`IncidentDetailView.swift` at commit `a6046ba` against `design/screens/1e.png`.
It should be redone by eye once a real incident is open.

| 1e specifies | Before this task |
|---|---|
| Plain-language verdict + severity chip + paragraph | `summary.headline` only — "Memory pressure for 11 minutes", the metric's name not the experience. No severity chip. Subtitle was "Still going"/"Recovered". No paragraph. |
| Confidence legend up front (Measured / Calculated / Likely) | Absent. Evidence classes appeared only as per-statement badges. |
| Timeline: window shaded, trigger and recovery marked, three series | Absent entirely. No chart of any kind. |
| "What we found" as four labelled paragraphs ending in **Ruled out** | Closest match: "What we found" listed the conclusions with badges, and "Ruled out" was a separate sibling section with no explanation of what it is for. |
| "What happened after you acted" (FR-050) | Absent from the view. `ActionVerification` exists in `Metrics` and is used by `ActionPerformer`, but nothing surfaced it on this screen. |
| Events, including our own behaviour | Absent. No event-log type exists anywhere in the project. |
| Conditions at the time + build/schema footer | Absent. `MachineContext` carries app version, build and schema and was never rendered here. |
| Title bar with Export… / Delete | Not addressable from this file: the detail is embedded as an `.inspector` inside `IncidentsView`, which another agent owns. |

Two sections that exist today are **not** in 1e and were kept: "The measurements"
(FR-054 raw evidence, TASK-52 AC#3) and "Working through it" (the guided
investigation, FR-054). Removing either would silently contradict TASK-52.

## What the design needs that we do not store — the main finding

Checked before rendering anything. Each of these is reported on screen as a
named absence rather than filled in.

1. **`MetricsHistory` retains CPU only.** `HistorySample` holds total /
   attributed / unattributed percent-of-one-core plus the top five contributors
   (command, CPU, resident bytes). There is **no per-sample memory pressure and
   no per-sample swap figure**, so two of the design's three timeline series have
   no stored values behind them. The third, memory-by-app, is retained only for
   whichever processes led each sample, so a continuous stacked series would
   have gaps we would have to invent values to fill.
2. **The view cannot reach history at all.** `MonitorStore.history` is `private`
   and I may not edit that file, so even the CPU series has no route to this
   screen today. `IncidentDetailView` now takes `samples: [HistorySample] = []`;
   wiring it is a one-line change for whoever owns the store.
3. **Nothing about the machine's surroundings is stored with an incident.**
   `Incident` carries times, conditions, severity, peak CPU and peak pressure —
   and nothing else. Power, Low Power Mode, thermal state and free storage are
   live readings on the store. For a **closed** incident this screen therefore
   shows none of them and says so; showing today's battery level under
   "Conditions at the time" would attribute a reading to a moment we never took
   it. This is why AC#7 is unchecked.
4. **No event log exists.** The lifecycle entries this screen shows are derived
   from timestamps the detector genuinely recorded (`beganAt`, `triggeredAt`,
   `recoveryStartedAt`, `closedAt`), so they are measured facts. **Cadence
   changes are not recorded anywhere.** `CadenceController` would have raised the
   rate when the condition first breached, but "would have" is not a
   measurement, so it is never inferred: our own behaviour appears only when
   `store.cadence` can be read live, i.e. while the incident is open. When the
   list carries none, it says why.
5. **No action verification is kept with an incident.** `ActionVerification` is
   built and discarded at the point of acting. The view takes
   `verification: ActionVerification? = nil`; with nothing supplied the section
   states there is nothing to compare rather than implying no action was taken.
6. **Profiles do not exist in this build** (Phase 4). The design's "Profile
   active" row is rendered as an explicit unavailability line, not omitted.
7. **There is no rules version.** The design's footer reads "App 1.0 (14) ·
   rules r7 · schema 3"; ours reads "App … (…) · schema … · <hw.model>" because
   no rules-version concept exists to report.

If someone wants the 1e timeline for real, the smallest honest change is to add
memory pressure and the paging counters to `HistorySample` (schema bump) and
expose the history to the detail view. That is a `Metrics` + `MonitorStore`
change and belongs to whoever owns those files.

## What was built

`MacSlowdown/Sources/IncidentEvidence.swift` (new) — the presentation model,
pure functions over their inputs so the rules are testable:

- `EvidenceProvenance` — `recordedDuringIncident` / `observedNow` /
  `notRetained(reason:)`. This distinction is what stops a live reading being
  presented as history.
- `EvidenceLegend` — builds the FR-038 legend **from the statements actually on
  screen**. A summary with no hypothesis produces no "Likely" line, because a
  legend that advertises a class the screen does not contain is itself an
  unsupported claim.
- `IncidentVerdict` — plain-language headline per condition ("Your Mac ran short
  of comfortable memory…") and a paragraph built only from measured and
  calculated facts. 1e's opening paragraph reads causally; the honest version of
  that sentence is the labelled hypothesis in "What we found" (FR-013).
- `IncidentTimeline` — window, markers, clamped axis mapping, retained samples,
  and `missingSeries` naming the three traces we do not hold and why.
- `IncidentEventLog` — lifecycle entries plus our own cadence, each with an
  `Origin` so our behaviour is visibly ours.
- `IncidentConditions` — splits on `isOpen`, carries the FR-049 build/schema
  footer, and lists what this build cannot supply.
- `PostActionReport` — the FR-050 section, with the disclaimer as a constant
  shown beside the comparison rather than as a separable footnote.

`MacSlowdown/Sources/IncidentDetailView.swift` (rewritten) — sections in 1e's
order: verdict, legend, timeline, what we found (with **Ruled out** as its
closing part, introduced as "what the measurements exclude, not only what they
suggest"), what happened after you acted, events, conditions, then the two
pre-existing sections. Plus `SeverityChip` (word + shape, never colour alone),
`IncidentTimelineBand` (a `GeometryReader` band with a single accessibility
description, since the picture is evidence), and `EvidenceStyle` giving each
evidence class its own symbol so the legend does not rely on colour either.

## Tests

`MacSlowdown/Tests/IncidentEvidenceTests.swift` — 20 tests. The ones that matter:

- A closed incident never shows current power/thermal/storage as "at the time".
- An open incident does, and says the reading is live.
- The legend omits "Likely" when there is no hypothesis.
- A cadence change we did not observe is never inferred from policy.
- The timeline names its missing series and clamps its axis.
- An improvement is reported as correlation: the whole post-action text is
  checked against a forbidden-phrase list ("caused by", "fixed", "freed",
  "free up", "optimi", "memory leak", "proves", …), as are the headline and the
  verdict paragraph.
- `inconclusive` reads as an answer, not an error.

Full suite: **407 passing, 2 failing**. Both failures are `MetricsTests` that
measure the real machine — `CPUWorkloadTests.workloadIsAttributed()` and
`EndToEndIncidentTests.realSlowdownProducesOneIncident()`. The latter fails at
`EndToEndIncidentTests.swift:72`, which is its own deliberate "baseline CPU is
too high to separate added load" skip, recorded as an issue. The machine is
loaded by concurrent agents. Neither test can be reached by a change confined to
the app target; re-verified with the change stashed, where both passed.

## Criteria

- #1 **unchecked** — requires a capture of the running app against a real
  incident. The screen was off limits for this agent. Gap analysis above is from
  code and says so.
- #2, #4, #5 checked — verdict + legend, "Ruled out" as what the evidence
  excludes, and post-action as correlation with an explicit disclaimer, all
  covered by tests.
- #3 **unchecked** — the window, trigger and recovery are marked, but the
  design's series are not drawn (nothing retains them, and the view cannot reach
  even the CPU series). Judge on screen.
- #6 **unchecked** — the list carries our own cadence only while an incident is
  open, because cadence changes are not retained. Structurally present, not
  satisfiable for a closed incident until an event log exists.
- #7 **unchecked** — context is *displayed* but not *recorded with the
  incident*. Recording it needs `Incident`/`MonitorStore` changes, which are
  owned by other agents.

## Needs on-screen verification with a real incident

Nothing on this screen has been seen. Specifically: that the inspector's ~380pt
width does not mangle the timeline band or the marker labels; that the legend
does not dominate the top of a narrow column; that the "conditions were not
retained" copy reads as an honest limitation rather than as a bug; and that the
whole thing remains readable at increased contrast and with reduced transparency.
<!-- SECTION:NOTES:END -->
