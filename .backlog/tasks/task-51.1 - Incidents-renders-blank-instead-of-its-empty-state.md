---
id: TASK-51.1
title: Incidents renders blank instead of its empty state
status: To Do
assignee: []
created_date: '2026-08-09 02:14'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-51
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression against TASK-51's acceptance criterion #4, which was implemented and verified on screen.

Observed on macOS 27 in the built Debug app with no incidents recorded: selecting Incidents in the sidebar shows the navigation title "Incidents" and **nothing else** — an entirely blank detail pane. Captured twice, in separate runs, roughly two seconds after selection, so it is not a transition artefact. Screenshot: `screenshots/04-incidents.png`.

The code looks correct. `MacSlowdown/Sources/IncidentsView.swift:36-45` defines a `ContentUnavailableView` reading "No slowdowns recorded" plus copy that distinguishes monitoring-running from monitoring-stopped, and `body` selects it whenever `all.isEmpty`. So the branch is being taken and the view is not appearing, rather than the copy being missing. Suspects worth checking first: the `Group` wrapper combined with `.navigationTitle` and the always-attached `.inspector(isPresented:)` at lines 26-31, and whether `ContentUnavailableView` renders inside a `NavigationSplitView` detail column on this OS version.

Why it matters beyond cosmetics: a blank pane is exactly the failure mode TASK-51's criterion was written to prevent. "Nothing here" reads as "the app is broken" — and the user cannot tell the difference between no incidents and no monitoring.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With no incidents recorded, the Incidents pane shows the empty-state heading and description on screen in the running app
- [ ] #2 The empty state still distinguishes monitoring-running from monitoring-stopped, as TASK-51 criterion #4 requires
- [ ] #3 The pane is checked both with and without an open incident, so the fix does not break the populated list
- [ ] #4 The cause is recorded in the task notes, so the next person does not re-derive why a correct-looking view rendered nothing
- [ ] #5 A test covers the empty branch to whatever extent SwiftUI allows, with anything only verifiable on screen stated as such
<!-- AC:END -->
