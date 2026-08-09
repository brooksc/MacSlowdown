---
id: TASK-65.20
title: 'First run never comes forward under LSUIElement, so nobody sees it'
status: To Do
assignee: []
created_date: '2026-08-09 18:28'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Verified on screen 2026-08-09, macOS 27, built Debug app, fresh first-run state. This is the exact risk TASK-65.7 flagged as "highest risk" and could not test without the screen.

**What happens:** at launch the first-run window is created — it is in the accessibility tree at 625,275, size 460x592, and `count of windows` is 1. But **nothing is drawn on screen**. A screen capture of precisely that rectangle shows the window behind it. The window exists and is invisible.

Forcing `AXRaise` on it makes it appear immediately, and it then renders correctly — screenshot `screenshots/verify/00-firstrun.png`. So the content and layout are fine; only the presentation fails.

**Why:** the app is `LSUIElement`, an accessory-policy app. Such an app does not become active by opening a window, so the window is ordered in behind everything. TASK-65.7 added `NSApp.activate()` (skipped under XCTest) and noted that whether an accessory app can raise a window *without* also taking a Dock icon was untested. Measured answer: as it stands, it does not.

**Consequence:** first run is the only place the app requests notification permission in context, and the only place it sets expectations about unattributable system activity before the user meets it. If nobody sees it, none of that happens — and `firstRun.completed` is only set by "Start watching", so the screen stays owed and presumably reappears invisibly at every launch.

Worth checking while fixing: whether the window appears but *behind* other apps, or is not ordered in at all — the two have different fixes. And whether a transient activation policy change (accessory → regular for the duration, then back) is acceptable, since it briefly shows a Dock icon; TASK-11.1 chose deliberately not to open windows at launch for a related reason, and its `MainWindowOpener` registration must keep working.

Note the same question applies to any window this app opens without a user gesture. The main window opened via the popover button works, because clicking the status item activates the app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On a cold launch with first-run state unset, the first-run window is visible and frontmost without any external intervention, verified on screen
- [ ] #2 The fix does not leave a permanent Dock icon behind when the menu bar item is shown
- [ ] #3 TASK-11.1's MainWindowOpener registration and the Dock-icon route continue to work
- [ ] #4 The first-run flag is only set by completing the screen, so an unseen or dismissed first run is presented again
- [ ] #5 Any other window the app opens without a user gesture is checked for the same failure
<!-- AC:END -->
