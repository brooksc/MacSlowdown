---
id: TASK-64
title: >-
  Settings window: misaligned Notifications row and a login-item message that
  reads as a fault
status: To Do
assignee: []
created_date: '2026-08-09 02:14'
labels:
  - ui
milestone: m-3
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cosmetic, found while screenshotting the built Debug app on macOS 27. Screenshot: `screenshots/05-settings.png`.

Two things in the Settings window (`SettingsView` in `MacSlowdown/Sources/MacSlowdownApp.swift`):

1. The "Notifications / Allowed" row's label sits hard against the left edge of the window, outside the alignment the two toggles above it establish. The toggles and their caption text share one leading edge; the Notifications label does not, so the form reads as two unrelated halves.

2. The login-item row reads "Start at login is unavailable: The app could not be found by the system." This is the expected `SMAppService` result for a binary run out of `.build` rather than a registered location, but the copy states it as a fault in the app. A user running an installed copy should never see it; a developer sees it constantly and cannot tell it apart from a real failure.

Low priority — nothing here is wrong in behaviour, and TASK-16 (login item via SMAppService) is parked, so item 2 may resolve itself once the app is installed properly. Worth a look next time Settings is open for another reason.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Notifications row shares the same leading alignment as the toggles above it
- [ ] #2 The login-item unavailable message distinguishes 'not registered because of where this build is running from' from a genuine failure, or is deferred with a note explaining why it cannot be told apart
- [ ] #3 Verified on screen in the running app
<!-- AC:END -->
