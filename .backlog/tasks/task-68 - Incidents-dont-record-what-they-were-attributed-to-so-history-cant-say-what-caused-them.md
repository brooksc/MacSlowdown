---
id: TASK-68
title: >-
  Incidents don't record what they were attributed to, so history can't say what
  caused them
status: In Progress
assignee: []
created_date: '2026-08-09 05:01'
updated_date: '2026-08-09 06:32'
labels:
  - core
milestone: m-2
dependencies: []
modified_files:
  - Metrics/Sources/IncidentAttribution.swift
  - Metrics/Sources/Incident.swift
  - Metrics/Sources/IncidentSummary.swift
  - Metrics/Sources/ActionOutcome.swift
  - Metrics/Sources/ApplicationPolicy.swift
  - Metrics/Tests/IncidentAttributionTests.swift
  - MacSlowdown/Sources/MonitorStore.swift
  - MacSlowdown/Sources/IncidentsView.swift
  - MacSlowdown/Sources/IncidentDetailView.swift
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
- [x] #1 An incident retains the attribution it was judged on, so a closed incident can state which application it was attributed to without re-reading live state
- [ ] #2 Any application named on a historical incident carries the confidence label it was recorded with, and is never presented as a proven cause (FR-013, FR-038)
- [x] #3 Recurrence across incidents can be computed by application, not only by condition, so the history screen can state that one app appears in several
- [x] #4 A user action taken during an incident is linked to it, so 'recovered after you acted' is stated only when an action was actually recorded -- never inferred from timing (FR-050)
- [x] #5 A detection suppressed by a user policy is linked to the incident it suppressed, so history can say why it was not alerted (FR-016)
- [ ] #6 The real retention behaviour and the interface's description of it agree, whatever the persistence decision turns out to be
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built (branch worktree-agent-a10bdc2858b48e69c, commit eba642e)

**Governing FR confirmed before building.** FR-011's expected behavior is literally "Create one incident with start time, active conditions, severity **and leading contributors**". Contributors were the missing half, so this is a gap against FR-011 as written, not only an implication of FR-013/FR-049. FR-049's machine context is already satisfied at export (`DiagnosticExport` carries `MachineContext`); the incident additionally keeps `logicalCoreCount`, without which a percentage of one core is uninterpretable later (FR-004).

### New: `Metrics/Sources/IncidentAttribution.swift`

- `IncidentContributor` — one application, keyed on `bundlePath` or `name:<displayName>`. **Never the family id**, which for the ~85% of the table that is standalone contains a PID; PIDs recycle, so that key would make the same daemon look like a different application in every incident.
- `AttributionSample` — one sample's roll-up, built by `AttributionSample.from(attribution:families:)`. Per-application, not per-process: "Chrome" is an answer a user can act on where forty renderer helpers are not, and recurrence is only meaningful per application.
- `IncidentAttribution` — what the incident keeps. **Two aggregations on purpose:** `applications` are per-application maxima across the incident; the three totals and the confidence come from the *single busiest sample*, kept as one coherent set. Taking each total's maximum independently produces a triple that never existed and does not sum (FR-055). Bounded to 5 applications (FR-005/FR-012).
- `IncidentRecurrence.leadingApplications(in:)` + `ApplicationRecurrence` — gated at >=3 attributable incidents with an app leading >=3 of them. The denominator is incidents that recorded *something*, not all incidents: one with nothing attributable is not evidence either way. Carries the **weakest** confidence of the incidents it counts — averaging would let two low-confidence records combine into a confident-looking pattern.

### Changed

- `SystemObservation` gains an optional `attribution: AttributionSample?`. `IncidentDetector` records it on open (including the merge-window rejoin) and merges it on **every** path while open, including the recovery clock. Merging deliberately does **not** count as a change, so it never emits `.updated` — otherwise every sample would re-notify (FR-014). `MonitorStore` therefore reads `openIncident` back from `detectorState.current` each sweep rather than only from events.
- `MonitorStore` builds the sample only when a condition is breaching or an incident is open. A breach always precedes an incident by the sustained duration, so the snapshot is always present before the detector needs it, and the idle path is untouched.
- `IncidentSummarizer.summarize` now prefers `incident.attribution` over the live `CPUAttribution` and does not consult the live one for anything causal when a recording exists. `IncidentDetailView` did the same thing wrong more visibly: it showed live figures under "The measurements" for a closed incident. Fixed — live is used only while an incident recorded nothing of its own.
- `Incident` gains `attribution`, `actions`, `suppressions`, `covers(_:)`, two `record(_:)` linkers, and `outcome: IncidentOutcome`.

### The four outcome phrases

All four are now derivable from recorded data: `.open`, `.recovered` ("no action was recorded"), `.recoveredAfterRecordedAction`, `.notAlerted`. Each carries a `Conclusion` with its evidence class — the suppression one is `.userProvided`, the rest `.measured`. There is deliberately **no** case for "recovered *because* you acted".

### The two rules that were not weakened

- **Actions (FR-050):** `Incident.record(_ verification:)` requires the action to have *actually run* (`result.didRun`) **and** to have been requested inside the incident window. Neither condition is "the machine got better". Tested from both directions: an action 10s before the incident began and one long after it closed are both refused, and withheld/failed actions are refused inside the window.
- **Suppressions (FR-016):** `SuppressedDetection` gains `incidentID` (optional — a policy is consulted at detection, which precedes the episode) plus `linked(to:)`, and `PolicyStore.suppressedDetections(forIncident:)`. Keyed both ways: the incident carries the suppression for its own account of itself, the suppression carries the id so the audit trail joins back. `MonitorStore.record(suppression:)` stamps the id.

### Confidence into history

`IncidentAttribution.evidence` is `.heuristic` by construction and no initialiser can make it anything else. `confidence` is **stored at the busiest observed moment, not recomputed** — tested: a later calm, fully-attributed sample does not raise the confidence of an incident that was 90% unattributable. It reaches the UI through `Conclusion` (which already refuses a heuristic without a confidence) and through the row's own caption.

### Retention — NOT decided

Unchanged: 20 incidents, in memory, not persisted. `MonitorStore.retainedIncidents` untouched, `requirements.md` untouched. The incidents footer now states that behaviour and interpolates the constant, so the copy cannot drift from it. Whether incidents should persist remains the product owner's call.

### Tests

31 new in `Metrics/Tests/IncidentAttributionTests.swift`. Full `AllTests` run: **412 passing, 2 failing** — both are the documented busy-machine guard (`EndToEndIncidentTests.swift:72`, `Issue.record("Skipped: baseline CPU is ...")`); several agents were building. Re-run in isolation: all `CPUWorkloadTests` pass, `EndToEndIncidentTests` still hits the baseline guard. Not a regression. Base for this worktree was main @ a6046ba (~383 tests), not the 670 the brief quoted — that count includes concurrent work not yet merged here.

### Not verified — needs the screen

Criteria #2 and #6 left unchecked. Both are about what a person sees, and nothing was put on screen (per CLAUDE.md, a passing unit test does not meet a UI criterion). Specifically unverified: that the row's heuristic/confidence caption reads clearly beside the application name and is not truncated; that the outcome line and the subtitle no longer duplicate "recovered"; that the "What keeps coming up" section and the retention footer render as list sections rather than as selectable rows.

### For whoever lands TASK-65.6

`IncidentHistory.swift` and `IncidentEvidence.swift` do not exist on main — that work is still in another worktree, so its footer copy and its `leadingContributor` workaround could not be revised here. The data they were waiting on now exists: `incident.attribution`, `incident.outcome`, `MonitorStore.recurringApplications`, and `MonitorStore.record(action:)` / `record(suppression:)`. `IncidentsView.swift` will conflict on merge; the framework side will not.

### Still inert, deliberately

Nothing yet *calls* `MonitorStore.record(action:)` or `record(suppression:)` — `ActionPerformer` returns an `ActionResult` and no caller runs `ActionVerifier.verify`, and `PolicyStore` is not wired into `MonitorStore` at all. That is TASK-66's app-layer wiring and its files were out of bounds here. The link points are in place and tested; until they are called, `outcome` correctly reports `.recovered` ("no action was recorded") rather than guessing.
<!-- SECTION:NOTES:END -->
