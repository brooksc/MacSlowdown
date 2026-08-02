---
id: TASK-16
title: Login item via SMAppService (FR-033)
status: Parked
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:56'
labels:
  - core
milestone: m-1
dependencies: []
priority: low
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No silent registration
- [ ] #2 System Settings state matches app state
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in LoginItem.swift with a toggle in Settings, but PARKED because AC#2 cannot be honestly verified from this environment.

AC#1 (no silent registration) is met and verifiable by construction: nothing on any launch path calls register(). LoginItem.init only calls refresh(), which reads SMAppService.mainApp.status and never mutates it. Registration happens solely from the Settings toggle.

AC#2 (System Settings state matches app state) is NOT VERIFIED. The implementation reads SMAppService.mainApp.status live on every appearance rather than caching what it last set, and handles .requiresApproval by explaining that macOS needs the user to re-enable it in System Settings and offering a button that opens that pane. But I did not exercise the round trip, for two reasons:
1. SMAppService registration from a DerivedData build path is not representative -- macOS expects a stable install location, so a pass or fail there would not predict shipped behaviour.
2. Actually registering would leave a login item on the user's machine as a side effect of a test.

To finish this: install a release build into /Applications, toggle Start at login, confirm it appears in System Settings > General > Login Items, disable it there, reopen the app's Settings and confirm the toggle reflects the system state rather than what the app last set.

Nothing else depends on this task, so it does not block m-1's other work.
<!-- SECTION:NOTES:END -->
