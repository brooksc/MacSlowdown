---
id: TASK-121
title: >-
  First run comes to the front without becoming active, so the first keypress
  goes elsewhere
status: To Do
assignee: []
created_date: '2026-09-17 18:53'
labels:
  - ui
milestone: m-2
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Seen on screen 2026-09-17**, in the running app on macOS 26.6.2 in a VM, on a cold launch with no arguments — the shipping path. Screenshots `design/verified/2026-09-17/07-first-run-cold.png` and `06-first-run.png`.

The first-run window is visible and frontmost over the Terminal, which is what TASK-65.20 asked for and got. But **the menu bar still reads "Terminal"**: the window came to the front without the *application* becoming active.

**TASK-65.20 predicted this exact outcome and said what to look for.** Its notes record that `orderFrontRegardless()` was added as a fallback "so that even if that inference is wrong the window is still seen — but then it would be seen *without* keyboard focus, and ⏎ would not press 'Start watching'. That is the specific thing to look for." It is what happened. The inference that `activate(ignoringOtherApps: true)` succeeds where `activate()` was declined is **not borne out** under `LSUIElement`.

Both capture paths show it, which is the useful part: `07-first-run-cold.png` is the shipping path and `06-first-run.png` goes through `UIVerificationLaunch`, which calls `activate(ignoringOtherApps:)` explicitly. Neither makes the app active, so the launch seam is not masking a difference — the activation call simply is not doing what it appears to promise for an accessory-policy app launched into the background.

**Why it matters more than it looks.** First run is the one screen that sets expectations before the user meets unattributable system activity, and it carries the notification-permission request. A window that is in front but not focused costs the user a click they will not know they need: the first click activates the app rather than pressing anything, so "Start watching" appears not to respond the first time it is pressed.

**What was measured and is not in doubt:** the window is drawn, correct, frontmost, and leaves no Dock icon behind. This is about focus only.

**The likely lever**, untested: `NSApp.setActivationPolicy(.regular)` before the window opens. `ActivationPolicy.mainWindowOpened()` already does that for the *main* window and evidently not for this one, which would also explain why the main window does take focus when opened from the popover. The cost is a Dock icon for the duration, which TASK-65.20 #2 was careful to avoid — so this is a genuine trade, not an oversight to correct. Decide which is worse: a transient Dock icon, or a first click that does nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On a cold launch with first-run state unset, the application becomes active — the menu bar names MacSlowdown — not merely frontmost
- [ ] #2 Pressing Return without clicking first presses 'Start watching'
- [ ] #3 Whatever the fix costs in Dock-icon visibility is stated and accepted, rather than discovered later
- [ ] #4 Verified on screen from a cold launch with no launch arguments, not through UIVerificationLaunch
- [ ] #5 The same check is applied to the main window opened from a notification action, which TASK-65.20 fixed blind and nobody has looked at
<!-- AC:END -->
