---
id: TASK-65.20
title: 'First run never comes forward under LSUIElement, so nobody sees it'
status: Done
assignee: []
created_date: '2026-08-09 18:28'
updated_date: '2026-09-17 18:53'
labels:
  - ui
milestone: m-2
dependencies: []
modified_files:
  - MacSlowdown/Sources/ActivationPolicy.swift
  - MacSlowdown/Sources/FirstRunView.swift
  - MacSlowdown/Tests/WindowRaisingTests.swift
  - MacSlowdown/Tests/FirstRunTests.swift
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
- [x] #1 On a cold launch with first-run state unset, the first-run window is visible and frontmost without any external intervention, verified on screen
- [x] #2 The fix does not leave a permanent Dock icon behind when the menu bar item is shown
- [x] #3 TASK-11.1's MainWindowOpener registration and the Dock-icon route continue to work
- [x] #4 The first-run flag is only set by completing the screen, so an unseen or dismissed first run is presented again
- [x] #5 Any other window the app opens without a user gesture is checked for the same failure
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Which failure mode: ordered in, but behind

Not "never ordered in". Three pieces of evidence, all from the on-screen measurement already recorded in this task:

1. **`AXRaise` fixed it, and it rendered correctly on the instant.** AXRaise is AppKit's accessibility mapping onto `makeKeyAndOrderFront:`. A window that had never been ordered in would have had to be created, laid out and drawn first; this one was already drawn, and only needed to be moved up the order.
2. **It was in the accessibility tree with a real frame** (625,275, 460x592) and `count of windows` was 1. AppKit exposes on-screen windows there. A window held out of the window list is not an `AXWindow` with an `AXRaise` action.
3. **A capture of exactly that rectangle showed another application's window.** Those pixels belonged to somebody; our window was under them.

The AppKit semantics agree. `openWindow` on a `Window` scene creates the `NSWindow` and orders it in — ordering in is not the step that can fail. What an accessory app does not get is *activation*: `.accessory` is documented as "does not appear in the Dock ... but may be activated programmatically or by clicking on one of its windows", and until it is activated its windows are ordered into the global list below the active application's. So the window was on screen, in front of nothing.

**Why the `NSApp.activate()` TASK-65.7 already added did not save it — two independent reasons, both fixed:**

- **It ran before the window existed.** `presentIfNeeded` called `action()` (which is `openWindow`) and then `NSApp.activate()` on the next line. `openWindow` schedules a scene update; it does not create the window synchronously. The activation was spent on an app with no window to bring forward.
- **Cooperative activation (macOS 14+) declines it.** The unparameterised `activate()` respects other applications' activation state and is dropped for an app that was launched into the background holding no activation grant — which is exactly an `LSUIElement` login/launch. `activate(ignoringOtherApps: true)` is the only public call that says "come forward regardless"; it is deprecated and it is the one that works.

## The fix

New `WindowRaiser` in `ActivationPolicy.swift`. `raise(_ window:)` does three things in order: `NSApp.activate(ignoringOtherApps: true)`, `makeKeyAndOrderFront(nil)`, `orderFrontRegardless()`. The third is the belt to the braces — it puts the window in front of other applications whether or not the activation request is honoured, so the worst case degrades to "visible but not key" rather than "invisible".

It is applied to first run twice, deliberately:

- **Deterministically**, from inside the window. `FirstRunView` now carries a `WindowRaiserOnAppearance` (`NSViewRepresentable`) in its background; its `viewDidMoveToWindow` hands the real `NSWindow` to `WindowRaiser.raise` one run-loop turn later. A view knows its own window for certain, where a lookup is a guess about SwiftUI's internals.
- **By lookup**, from `FirstRunWindowOpener.presentIfNeeded`, which now calls `raiseWindow(sceneID:title:)` instead of `NSApp.activate()`. That polls `NSApp.windows` (20 attempts, 50 ms apart, first attempt after a `Task.yield`) because `openWindow` is not synchronous. `WindowRaiser.matches` is the pure matching rule and is unit-tested: scene identifier first (exact or contained, since SwiftUI decorates it), then title — and the title fallback only applies to `.titled` windows, so the borderless MenuBarExtra panel can never be dragged to the front by mistake.

A second raise is free, so having both paths costs nothing and means the fix does not rest on one uncertain assumption.

### Dock icon: none, at any point, for first run

No activation-policy change anywhere on the first-run path — `WindowRaiser` makes no `setActivationPolicy` call at all. `.accessory` apps are activatable; they simply have to ask forcefully. So the Dock icon appears for **zero seconds** during first run, and the transient-`.regular` option was not needed.

The only Dock icon in the app remains the pre-existing, intended one: `ActivationPolicy.mainWindowOpened()` switches to `.regular` while the *main* window is open and back to `.accessory` on close (or stays `.regular` if the menu bar item is hidden — TASK-11.1's route). Unchanged by this task, except that its `NSApp.activate()` now goes through `WindowRaiser.activateApp()` for the same cooperative-activation reason.

## Criterion #5 — every window the app can open, and its verdict

| Surface | Opened by | Verdict |
|---|---|---|
| First-run window (`FirstRunWindowOpener`, at launch) | nothing — the app decides | **AT RISK, this bug. Fixed** (raised from the view and by lookup). |
| Main window from `MainWindowOpener.open()` via `AppDelegate.applicationShouldHandleReopen` | Dock click | Safe — AppKit activates the app for a Dock click, and the policy is `.regular` in that scenario by construction. |
| Main window from `MenuBarContentView` (`openWindow(id: MainWindow.id)`, two call sites) | clicking the status item | Safe — the MenuBarExtra click activates the app. `MainWindowView.onAppear` then switches to `.regular`. |
| Main window from `MainWindowOpener.open()` via `NotificationDelivery.onShowDetails` ("Show details", and the default action of clicking the banner body) | a notification action button | **AT RISK — same failure, undiscovered.** macOS does not activate an accessory app for a custom notification action, so the main window would have opened behind everything just as first run did. **Fixed**: `MainWindowOpener.open()` now raises the window it asked for. Unconditional rather than per-caller, because raising an already-frontmost window is a no-op. No change to `NotificationDelivery` was needed. |
| "Mute 1 hour" notification action | a notification action button | Safe — it calls `store.mute(forMinutes:)` and opens no window. |
| Mute sheet (`MuteSheetPresenter.present()`) | ⌥⌘M, a menu command on the main window | Safe — the command only exists while that window is key, so the app is active. Noted in passing, out of scope: the presenter is a bare flag with no host when the main window is closed, so a future non-gesture caller would set it and nothing would appear. |
| `NSSavePanel` in `ExportReportView` | a button in an open window | Safe. |
| `Settings` scene | ⌘, or the popover's Settings button | Safe. |
| `ActionPerformer` `application.activate(options:)` | a user action on another app (FR-018/019) | Not our window; unaffected. |

Nothing else in `MacSlowdown/Sources` opens a window, panel, sheet or alert (grepped for `openWindow`, `NSApp.`, `makeKeyAndOrderFront`, `orderFront`, `runModal`, `NSAlert`, `NSSavePanel`, `NSOpenPanel`, `beginSheet`, `activate(`).

## Criterion #4 — the flag, tested

`FirstRunState.complete()` is called from exactly one place, the "Start watching" button. New test `unseenFirstRunIsStillOwed` walks the actual failure this bug produced: present, never complete, construct a fresh `FirstRunState` over the same container (a relaunch), and it is owed and presented again. Then completing retires it. So an invisible first run cost nothing permanent — which is why this was survivable rather than fatal.

## Criterion #3 — TASK-11.1 kept intact

`MainWindowOpener.action` registration is untouched; `open()` still runs the registered action and still returns false when nothing is registered. All four `ReopenTests` pass, plus a new `openIsSuppressedUnderTests` asserting that the added raise changes neither the activation policy nor `NSApp.isActive` during a test run, while the registered action still fires exactly once. The Dock-icon route itself has never been verified on screen (TASK-11.1's own criteria #1–#3 are unchecked); nothing here changes that either way.

## The no-screen-during-tests property still holds, and is now asserted

Every new `NSApp` call is inside `WindowRaiser`, which returns immediately when `AppDelegate.isHostingTests`. Two guards were *added* while here, both previously missing: `ActivationPolicy.mainWindowOpened()` and `mainWindowClosed()` set the activation policy unguarded, so any test that rendered `MainWindowView` would have put a Dock icon up. New `WindowRaisingTests` asserts all of it — that a window handed to `raise` stays invisible and non-key, that `NSApp.isActive` and the activation policy are unchanged, and that the host app has no first-run window open.

## Tests

`-only-testing:MacSlowdownTests`: **465 passing, 0 failing** (454 before, +11: 10 in the new `WindowRaisingTests`, 1 in `FirstRunTests`). `MetricsTests` not run — no `Metrics` code was touched, and two other agents were building concurrently, which is the condition under which the load-sensitive CPU tests fail for reasons that have nothing to do with a change.

No diff to `MacSlowdownApp.swift` was needed: `.defaultLaunchBehavior(.presented)` was considered and rejected, because it would present the first-run window on *every* launch rather than when it is owed, and it would not have fixed anything — presentation was never the failing step, activation was.

## NOT VERIFIED — needs the screen (criteria #1 and #2)

Criterion #1 cannot be checked from a terminal, and #2 is contingent on it: the claim that no Dock icon appears rests on `.accessory` being activatable, which is documented and is not the same as observed. If the raise turns out to need a policy switch after all, #2 becomes a live question again. Both left unchecked.

The reasoning is also, honestly, one inference deep in one place: that `activate(ignoringOtherApps: true)` succeeds where `activate()` was declined. `orderFrontRegardless()` is there so that even if that inference is wrong the window is still seen — but then it would be seen *without* keyboard focus, and ⏎ would not press "Start watching". That is the specific thing to look for.

### The exact on-screen check

1. Quit the app.
2. Reset the flag in the sandbox container:
   `defaults delete com.brooksc.MacSlowdown firstRun.completed` (or, if that container path does not answer, delete the key from `~/Library/Containers/<bundle id>/Data/Library/Preferences/<bundle id>.plist`).
3. Put a large window from another application — a browser, a terminal — over the middle of the main display, covering roughly 625,275 to 1085,867. Click it, so that application is genuinely the active one.
4. Cold-launch the built app: `./run-menubar.sh`. Do not click anything afterwards.
5. **Look for:** the "Two things before we start" window on top of that other window, without touching anything. Then check three more things:
   - **No Dock icon.** The Dock must be unchanged for as long as the window is up.
   - **Keyboard focus.** Press ⏎ without clicking first. It should press "Start watching" — that is the test of whether the app actually became active or only pushed a window forward.
   - The menu bar item is present as usual.
6. Then relaunch: the screen must **not** reappear (it was completed). Reset the key and relaunch once more without pressing the button — it must reappear.

Also worth one look while there (criterion #5's second at-risk item, fixed blind): raise a real notification and click **Show details** while another application is frontmost. The main window must come forward, not open behind. That one has never been seen either, before or after this change.

**Verified on the shipping path, 2026-09-17** — `design/verified/2026-09-17/07-first-run-cold.png`.

**#1.** The app was launched in the VM with `open -n -a MacSlowdown.app` and **no launch arguments at all**, with `firstRun.completed` cleared beforehand. Not the `-ui-open first-run` seam, which calls `activate(ignoringOtherApps:)` explicitly and would have assumed the conclusion. The first-run window is visible and frontmost over the Terminal with nothing intervening.

**#2.** No Dock icon is left behind: the VM's Dock in that frame runs Settings → separator → Terminal → Downloads → Trash, with no MacSlowdown tile, while the window is open.

**One residual, and the capture is the only thing that could have shown it.** The menu bar in that frame still reads **Terminal**. The window comes to the *front* without the application becoming *active*, so a first click on it activates rather than acts. `06-first-run.png`, which does go through `activate(ignoringOtherApps:)`, shows exactly the same thing — so the activation call is not doing what it appears to promise under `LSUIElement`, and the seam is not masking a defect in the shipping path either.

I am closing this rather than holding it open: both criteria as written are met, the window is reachable and readable, and the residual is a distinct behaviour (front versus focused) that was never in scope here. It is worth its own task if the owner wants the first click to act rather than activate — the likely lever is `NSApp.setActivationPolicy(.regular)` before the window opens, which `ActivationPolicy.mainWindowOpened()` already does for the *main* window and evidently not for this one.
<!-- SECTION:NOTES:END -->
