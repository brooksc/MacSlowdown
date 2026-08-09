---
id: TASK-83
title: The Incidents sidebar row is spoken as "1" — the badge has replaced its name
status: To Do
assignee: []
created_date: '2026-08-09 22:54'
labels:
  - ui
milestone: m-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on screen 2026-08-09 by reading the accessibility tree of the running app, not by looking at pixels.

The sidebar's four rows report these accessibility labels:

| Row | Label |
|---|---|
| 1 | `Now` |
| 2 | `Apps & Processes` |
| 3 | **`1`** |
| 4 | `Storage` |

Row 3 is Incidents. When `store.openIncident != nil` the `.badge(1)` modifier in `MainWindowView`'s sidebar `List` replaces the row's label with the badge value, so VoiceOver announces the navigation destination as "1". With no open incident the badge is `0` and the name presumably returns — which means **the label breaks exactly when there is an incident to go and look at**, and reads correctly the rest of the time. That is the worst possible failure schedule for it, and it is why nobody caught it by using the app casually.

FR-034 requires full keyboard operation and VoiceOver labels; a primary navigation control with no name is a straightforward breach. TASK-15 (accessibility baseline, parked) would have caught this, but it does not need to wait for TASK-15 — the defect is identified and the fix is local.

Worth checking while fixing: whether the badge count should be spoken at all, and if so as what. "Incidents, 1 incident" is the obvious reading; "Incidents, 1" is ambiguous about what the 1 counts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Incidents sidebar row is announced with its name whether or not an incident is open
- [ ] #2 The badge count is spoken as a counted noun rather than a bare number, or is hidden from VoiceOver if the name alone is sufficient
- [ ] #3 A test reads the accessibility label back for both the badged and unbadged states, so this cannot silently return
- [ ] #4 The other three sidebar rows are confirmed unaffected
<!-- AC:END -->
