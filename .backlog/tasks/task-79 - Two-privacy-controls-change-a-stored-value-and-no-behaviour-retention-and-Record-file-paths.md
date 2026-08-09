---
id: TASK-79
title: >-
  Two privacy controls change a stored value and no behaviour: retention and
  'Record file paths'
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-09 19:57'
labels:
  - core
  - ui
milestone: m-3
dependencies:
  - TASK-72
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`). Same class as TASK-70's `hideFilePaths` and TASK-69's alert settings: a control the user changes that changes nothing.

`AlertSettings.privacySettings` (`MacSlowdown/Sources/AlertSettings.swift:219`) gathers both settings into a `PrivacySettings`. That property is referenced by exactly one test (`MacSlowdown/Tests/SettingsSurfaceTests.swift:142`) and by no app code. Both controls therefore write to `UserDefaults` and are never read back.

**"Keep incident history for" (7 / 30 / 90 days)** — `SettingsView.swift:494`, persisted at `AlertSettings.swift:179`. `RetentionPolicy.retained` and `.expired` (`Metrics/Sources/PrivacySettings.swift:80, 90`) have no caller anywhere. Worse, the explanation next to it comes from `IncidentHistory.retentionFooter(limit: MonitorStore.retainedIncidents)` (`IncidentsView.swift:201`) — a **count** cap, so the visible explanation does not describe the same mechanism as the control above it.

**"Record file paths"** — `SettingsView.swift:506`, persisted at `AlertSettings.swift:175`. Paths are resolved and retained regardless of the setting.

The fix depends on TASK-72 (persist incident history / enforce retention) for the retention half: while history is memory-only and discarded at quit there is genuinely nothing to age out, and a time-based picker over a count-capped in-memory list would still be a lie. Either wire both once TASK-72 lands, or do what `SettingsView.swift:512` already does well for "Keep history across restarts" — remove the control and state plainly what the app does. That third row is the model: it is not a control, and it says so.

FR-029's acceptance criteria include that retention controls exist and take effect. Today the first half is true and the second is not.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The retention setting either takes effect -- RetentionPolicy.expired is applied to stored incidents on a schedule -- or is replaced by a statement of what the app actually keeps, in the manner of the 'Keep history across restarts' row
- [ ] #2 The retention explanation and the retention control describe the same mechanism; a count cap is not explained as a time window
- [ ] #3 'Record file paths' either changes whether executable paths are recorded and retained, or is removed
- [ ] #4 AlertSettings.privacySettings has a real reader in app code, or is deleted
- [ ] #5 probe/seam-reachability.sh no longer reports RetentionPolicy or expired, and the allowlist entries for them are removed
<!-- AC:END -->
