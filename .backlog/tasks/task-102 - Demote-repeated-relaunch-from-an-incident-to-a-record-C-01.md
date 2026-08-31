---
id: TASK-102
title: Demote repeated relaunch from an incident to a record (C-01)
status: To Do
assignee: []
created_date: '2026-08-31 20:42'
updated_date: '2026-08-31 20:42'
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
- [ ] #1 A repeated relaunch pattern opens no incident and sends no notification
- [ ] #2 The pattern is still recorded and still visible in the process inspector
- [ ] #3 An incident opened for another reason still carries lifecycle findings as evidence, with its heuristic label
- [ ] #4 Persisted incidents whose only condition was repeated quits are handled deliberately, not left rendering half a screen
- [ ] #5 Surfaces that narrated it as a subject degrade cleanly, with tests covering the now-unreachable paths
- [ ] #6 Design 1o's unreachability is recorded against TASK-65 with the reason
<!-- AC:END -->
