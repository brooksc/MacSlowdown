---
id: TASK-11.1
title: Hiding the menu bar item strands the app with no reachable window (FR-001)
status: To Do
assignee: []
created_date: '2026-08-09 02:13'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
parent_task_id: TASK-11
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by driving the built Debug app on macOS 27, not by a test.

Reproduction: set `showMenuBarItem` to false (Settings > "Show in menu bar", or the container preference directly), quit, and cold-launch the app. Measured result: the app runs, `AppDelegate` switches to `.regular` so a Dock icon appears, and there are **zero windows**. Clicking the Dock icon leaves it at zero. There is no menu route either — the app's "Window" menu lists no main-window item, and the only affordance that opens it is the "Open MacSlowdown" button inside the MenuBarExtra popover, which is exactly what has been hidden.

So the app is running, monitoring, and unreachable.

Two comments in the code assert the opposite and are wrong as written:
- `MacSlowdown/Sources/AppDelegate.swift:35-38` — "Clicking the Dock icon reopens the window rather than doing nothing." `applicationShouldHandleReopen` returns `true`, but returning true only lets AppKit do its default thing, and with a SwiftUI `Window` scene that has never opened in this launch there is nothing to restore.
- `MacSlowdown/Sources/MacSlowdownApp.swift:10-13` — "hiding the only visible surface would strand a running app with no way back", describing the Dock icon as the way back. It is not one today.

This matters because FR-001 requires the status surface be hideable. Hideable currently means unreachable.

Scope note: the fix is a product decision, not just a code change. Options include opening the window explicitly on reopen, opening it at launch when the menu bar item is hidden, or refusing to hide the item unless another surface exists. Pick one against FR-001 and record why.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With "Show in menu bar" off, a cold launch of the built app leaves the user a working way to open the main window, verified on screen in the running app rather than by unit test
- [ ] #2 Clicking the Dock icon opens the main window when the app is running with no window open
- [ ] #3 The behaviour is verified from a cold launch, not only by toggling the preference while a window happens to already be open
- [ ] #4 The comments in AppDelegate.swift and MacSlowdownApp.swift describe what the code actually does
- [ ] #5 A test covers the reopen path to the extent it is reachable, and anything only verifiable on screen is stated as such
<!-- AC:END -->
