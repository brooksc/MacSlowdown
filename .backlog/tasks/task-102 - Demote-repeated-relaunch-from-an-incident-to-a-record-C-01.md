---
id: TASK-102
title: Demote repeated relaunch from an incident to a record (C-01)
status: Done
assignee: []
created_date: '2026-08-31 20:42'
updated_date: '2026-09-03 18:36'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product owner, 2026-08-31, on challenge C-01: **agree, demote.** Recorded as FR-046 amendment 5.

Repeated relaunch stops opening an incident and stops notifying. It remains a **lifecycle record**: visible in the process inspector, and carried as evidence on an incident that exists for another reason.

Nine days produced ten repeated-quit incidents and no incidents of any other kind, all ten false, across four narrowings (TASK-71, TASK-84, TASK-86, TASK-99). What survives is "an application you were using disappeared and came back three times in fifteen minutes" — which the user generally watched happen — while amendment 1 forbids saying why it went and `p_comm` leaves the subject ambiguous to 16 bytes.

**Retain the detection code.** Amendments 3 and 4 stay in force because they govern what is *recorded*, not only what opened an incident, and a second machine producing a genuine crash-loop makes this decision cheap to revisit.

Scope — `repeatedApplicationQuits` reaches a lot of surfaces, and each needs a decision rather than a deletion:

- `IncidentDetector` must no longer open or escalate on it. Decide whether `IncidentCondition` keeps the case at all or it becomes a lifecycle-only concept — the case is in the persisted schema, so removing it is a migration.
- `NotificationDelivery` must not announce it.
- The Now banner, the popover headline and `IncidentHistory.Entry.subject` narrate it as an incident subject (TASK-82, TASK-87). Those paths become unreachable for this condition; confirm they degrade rather than break.
- `IncidentSummarizer`'s lifecycle sentence stays, for an incident carrying lifecycle findings as evidence.
- The 30-day store can hold incidents whose only condition is this one. Decide whether they are migrated, hidden, or left with an explanation — the product owner's own file held ten before it was cleared.
- Design 1o (the repeated-quit incident screen) becomes unreachable. Record that against TASK-65 rather than leaving a design reference pointing at nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A repeated relaunch pattern opens no incident and sends no notification
- [x] #2 The pattern is still recorded and still visible in the process inspector
- [x] #3 An incident opened for another reason still carries lifecycle findings as evidence, with its heuristic label
- [x] #4 Persisted incidents whose only condition was repeated quits are handled deliberately, not left rendering half a screen
- [x] #5 Surfaces that narrated it as a subject degrade cleanly, with tests covering the now-unreachable paths
- [x] #6 Design 1o's unreachability is recorded against TASK-65 with the reason
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Done 2026-09-03.** The demotion is one property and three call sites, deliberately — the detection code is retained in full.

**What changed.** `IncidentCondition.opensAnIncident` says which conditions may open an incident; `repeatedApplicationQuits` is the only one that may not. `IncidentCondition.opening` is the filtered set, and the three sites that asked "is something wrong now" now use it instead of `allCases`: the detector's condition loop and its `stillBreaching` check (`Incident.swift`), and `MonitorStore`'s `breaching` guard.

Written as a switch rather than a filter, so adding a condition forces someone to decide this question about it.

**The case is kept, not deleted.** It is in the persisted schema (removing it is a migration); amendments 3 and 4 still govern what is *recorded*; and a second machine producing a genuine crash-loop makes this cheap to revisit. That reversibility is the point of spending a property here.

**Criteria.**

1. A calm machine with a 30-exit pattern now produces no event at all — asserted through the detector, not by reading the flag.
2. Still visible in the process inspector: `FamilyInspectorView` shows "Relaunches, by name" with `Evidence.heuristic`, the confidence, and the caveat that the count is matched by command across the whole process table. Unchanged by this work.
3. `recordLifecycleFindings` runs on open and on update, independent of `sustained`, so an incident opened for a resource reason still carries the pattern. Tested with a CPU incident carrying a 4-exit finding.
4 and 5. **Handled by construction rather than by migration.** Only the *opening* was removed; every narration path — `IncidentNarrative.applicationLifecycle`, `RepeatedQuitIncident`'s detail section, `IncidentHistory.Entry.subject`, the menu bar and popover wording — is untouched and still tested. So a persisted lifecycle-only incident from an earlier build loads and renders exactly as it did. Nothing renders half a screen; the paths are unreachable for *new* incidents only.
6. Recorded against TASK-65.15, now Out of Scope: 1o is deleted from Claude Design's canvas outright, replaced by 4c.

**Notification:** there is no separate suppression, and that is the right shape — the alert path is only ever reached by an incident event, so no incident is no notification. A test asserts it end to end rather than trusting the reasoning.

**Tests.** `RepeatedQuitConditionTests` rewritten from "opens an incident of its own" to "is a record, and opens no incident", keeping every merge/confidence/quiet-period assertion by moving them onto a busy-machine policy. `MonitorStoreWiringTests.patternsReachTheDetector` keeps its real value — the hand-over from tracker to observation — and now asserts the detector opens nothing on it.

1134 passing. `EndToEndIncidentTests.realSlowdownProducesOneIncident` failed in the full run and passes in isolation: machine-sensitive, as CLAUDE.md documents, and several builds had just run back to back.

**Not done, and not claimed:** 4c's richer inspector treatment — the per-generation timeline, the "what this does and doesn't say" panel, the Copy lifecycle record action. That is open design work.
<!-- SECTION:NOTES:END -->
