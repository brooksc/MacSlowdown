---
id: TASK-64
title: >-
  Settings window: misaligned Notifications row and a login-item message that
  reads as a fault
status: In Progress
assignee: []
created_date: '2026-08-09 02:14'
updated_date: '2026-08-09 05:08'
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
- [x] #2 The login-item unavailable message distinguishes 'not registered because of where this build is running from' from a genuine failure, or is deferred with a note explaining why it cannot be told apart
- [ ] #3 Verified on screen in the running app
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed alongside TASK-65.9/65.10, commit 5cc1a3b, since all three touch the same surface.

**Item 1 — alignment.** The cause was mixing row constructs: two `Toggle`s with bare `Text` captions as sibling rows, then a `LabeledContent` with another bare `Text` caption. A bare `Text` in a `Form` is a full-width row, so its leading edge is the form's, not the control column's. Every General row is now either a `Toggle` or a `LabeledContent` whose *label* carries both the title and the caption (the two-`Text` label form), inside one `.formStyle(.grouped)` form. That is the idiomatic macOS settings construction and gives all three rows the same leading edge by construction rather than by padding.

**Item 2 — the login-item message.** `LoginItem.State` gained `.unavailableFromThisLocation(directory:)`. On `SMAppService` returning `.notFound`, `LoginItem.unregisterableLocation(bundleURL:home:)` checks whether the bundle sits under `/Applications` or `~/Applications`; if it does not, the state is the location case and the copy reads: "Start at login needs MacSlowdown to be in your Applications folder. This copy is running from <dir>, and macOS will not register a login item from there. Nothing is wrong with the app — move it to Applications and open it again." A `.notFound` from a properly installed copy still falls through to the original `.unavailable(reason)` wording, so a genuine failure keeps reading like one. Also added `LoginItem.isAdjustable`, so the toggle is inert in every state the system will refuse rather than looking operable.

**Criteria.** #2 met and tested (four tests, including that an installed path is *not* excused as a location problem). #1 **not verified**: the fix is structural and the reasoning is sound, but the criterion is visual and the screen was off limits for this run — per the project rule, a passing unit test does not meet a UI criterion. #3 not verified for the same reason. Both need one look at the running app's Settings › General.

Tests: `MacSlowdown/Tests/SettingsSurfaceTests.swift` › "Login item wording distinguishes a location from a fault".

**Rebase note.** Rebased onto `main` at f1d4ff8 after the fact (the branch was cut from a6046ba, before eight merges). The rebase was clean. `MacSlowdownApp.swift`'s TASK-11.1 wiring — `MainWindowOpener.action` registration and the `@SceneBuilder private var scenes` — is intact; my only change to that file is removing the old `SettingsView` struct (now in `SettingsView.swift`) and the import it needed. Commit is fe52c60. Build succeeds and 561 tests pass after the rebase.
<!-- SECTION:NOTES:END -->
