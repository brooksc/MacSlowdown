---
id: TASK-11.1
title: Hiding the menu bar item strands the app with no reachable window (FR-001)
status: In Progress
assignee: []
created_date: '2026-08-09 02:13'
updated_date: '2026-08-09 03:03'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
modified_files:
  - MacSlowdown/Sources/AppDelegate.swift
  - MacSlowdown/Sources/MacSlowdownApp.swift
  - MacSlowdown/Sources/ActivationPolicy.swift
  - MacSlowdown/Tests/ReopenTests.swift
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
- [x] #4 The comments in AppDelegate.swift and MacSlowdownApp.swift describe what the code actually does
- [x] #5 A test covers the reopen path to the extent it is reachable, and anything only verifiable on screen is stated as such
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision: open the main window explicitly on reopen; do NOT open it at launch; do NOT refuse to hide the item.

Justification against FR-001. The acceptance criterion is that the status surface "can be hidden", so refusing to hide the menu bar item unless another surface exists fails the requirement outright. The stated objective is to "let the user notice degradation without opening a full window", which argues just as directly against opening the window at every launch: with Start at Login on, that would put a 900x600 window on screen at every boot, which is the opposite of what FR-001 asks the product to be. What remains is the route the code already claimed to have — the Dock icon — made real. That also matches how a regular macOS app behaves: a Dock click on a running app with no windows opens one.

Implementation. `openWindow` exists only in the SwiftUI environment and `AppDelegate` has none, which is the actual cause of the defect: returning true from `applicationShouldHandleReopen` only permits AppKit's default reopen, which restores windows that already exist, and with the menu bar item hidden the `Window` scene may never have been created in this launch. `MacSlowdownApp` now captures `@Environment(\.openWindow)` and registers `{ open(id: MainWindow.id) }` into a new `MainWindowOpener` (in ActivationPolicy.swift) during scene evaluation, which happens whether or not the MenuBarExtra is inserted and whether or not a window is ever opened. `applicationShouldHandleReopen` calls `MainWindowOpener.open()` when `hasVisibleWindows` is false and returns true. `MainWindowOpener` deliberately makes no NSApp call of its own — activation stays with the registered action and `MainWindowView.onAppear` — so the reopen path is reachable from a test without putting a Dock icon on the developer's screen or stealing focus. `open()` returns false when nothing is registered, so "no route to the window" is a distinguishable state rather than a silent no-op.

Both misleading comments rewritten to describe what the code does (AC #4).

Tests (AC #5): new MacSlowdown/Tests/ReopenTests.swift, 4 tests — reopen with no visible windows asks for the window exactly once; reopen with a window visible asks for nothing; an unregistered opener reports failure; and the running host app has in fact registered an opener (this last one is the check that the SwiftUI-side registration executes at all, since it runs inside the real launched app). Full suite: 392 passing, 0 failing (388 pre-existing on this branch + 4 new). Two Metrics tests (CPUWorkloadTests.workloadIsAttributed, EndToEndIncidentTests.realSlowdownProducesOneIncident) failed on two intermediate runs while machine load average was ~12 from concurrent agents, and passed in isolation and on the final full run; they are load-sensitive and live in MetricsTests, which does not link the app target, so they cannot be affected by this change.

NOT VERIFIED — needs a human at the screen (AC #1, #2, #3 left unchecked). This agent was instructed not to use the screen, so nothing here was seen running. Specifically unverified: (a) that `@Environment(\.openWindow)` resolved in an `App` scope actually opens the window at runtime rather than logging a no-op warning — the test proves a closure was registered, not that invoking it produces a window; (b) that a cold launch with "Show in menu bar" off followed by a Dock click brings up the main window, frontmost; (c) that the window is raised above other apps (this relies on MainWindowView.onAppear calling ActivationPolicy.mainWindowOpened, unchanged by this task); (d) that a second Dock click with the window already open does not create or disturb anything.

If (a) turns out not to work, the fallback is to move the registration into a `Scene`-level `.onChange`/hidden scene, or to register from `MainWindowView.onAppear` plus retaining the NSWindow — but that second option does not fix the cold-launch case, which is the whole defect.
<!-- SECTION:NOTES:END -->
