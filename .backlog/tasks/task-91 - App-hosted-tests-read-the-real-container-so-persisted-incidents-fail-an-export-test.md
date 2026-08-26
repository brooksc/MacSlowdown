---
id: TASK-91
title: >-
  App-hosted tests read the real container, so persisted incidents fail an
  export test
status: Done
assignee: []
created_date: '2026-08-24 04:15'
updated_date: '2026-08-26 18:35'
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
- [x] #1 The app-hosted tests pass on a machine whose container already holds incidents
- [x] #2 No test asserts on the state of the developer's real container
- [x] #3 The fix does not require clearing any file before a test run
- [x] #4 statusBeforeFirstReading is audited for the same assumption
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
New `MonitorStore.storageURL(named:)` is the single place a persistent file's location is decided. Under `AppDelegate.isHostingTests` it returns a path in a per-launch temporary directory; otherwise the app's Application Support directory as before. Both `persistentIncidentHistory` and `defaultPolicies` go through it — the policy store had the same exposure and nothing had tripped over it yet.

Per-launch rather than a fixed temporary path, so two runs cannot leak state into each other either.

The fix is isolation, not deletion: clearing `incidents.json` would have made the test pass and left the defect for whoever recorded the next incident.

`StorageIsolationTests`, 2 tests: the redirected path is under the temporary directory, is not in Application Support, and carries the process id; and the shared store genuinely starts a test run empty — which is the assumption `exportWithNoIncidents` was making silently.

Full suite now 1096 passing. The only remaining failure is `EndToEndIncidentTests.realSlowdownProducesOneIncident`, which recorded its own "baseline CPU too high" skip on a machine running Xcode, LM Studio and this app.
<!-- SECTION:NOTES:END -->
