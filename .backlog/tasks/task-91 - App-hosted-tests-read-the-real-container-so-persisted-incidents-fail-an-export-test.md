---
id: TASK-91
title: >-
  App-hosted tests read the real container, so persisted incidents fail an
  export test
status: To Do
assignee: []
created_date: '2026-08-24 04:15'
labels:
  - infra
milestone: m-3
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Surfaced on 2026-08-23 while verifying TASK-86, and **not caused by that change**.

`SettingsAndIntentsTests.exportWithNoIncidents` (`MacSlowdown/Tests/SettingsAndIntentsTests.swift:96`) requires `store.openIncident == nil && store.recentIncidents.isEmpty` against `MonitorStore.shared`. The app-hosted bundle runs inside the real application container, so `MonitorStore.shared` loads `incidents.json` from `~/Library/Containers/com.brooksc.MacSlowdown/…/Application Support/MacSlowdown/`. Today that file held two incidents for the first time, and the requirement failed.

It is latent rather than new: TASK-72 made incidents persist, and until a real one was recorded on this machine the file was always empty, so the assumption held by accident. Any developer who has ever had an incident will now see this fail, and `statusBeforeFirstReading` immediately above it makes the same shape of assumption about `store.attribution`.

The fix is isolation, not deletion — clearing the file makes the test pass again and leaves the defect in place for the next person. Options: give the app-hosted tests their own store over a temporary directory, or have `AppDelegate.isHostingTests` also redirect the history store's location, which is the existing seam for "do not touch the user's world during a test run".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app-hosted tests pass on a machine whose container already holds incidents
- [ ] #2 No test asserts on the state of the developer's real container
- [ ] #3 The fix does not require clearing any file before a test run
- [ ] #4 statusBeforeFirstReading is audited for the same assumption
<!-- AC:END -->
