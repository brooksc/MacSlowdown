---
id: TASK-65.7
title: 'Screen 1g — Notification, mute sheet, and first run'
status: In Progress
assignee: []
created_date: '2026-08-09 02:23'
updated_date: '2026-08-09 06:34'
labels:
  - ui
milestone: m-2
dependencies: []
modified_files:
  - MacSlowdown/Sources/NotificationDelivery.swift
  - MacSlowdown/Sources/MacSlowdownApp.swift
  - MacSlowdown/Sources/MuteAlerts.swift
  - MacSlowdown/Sources/MuteAlertsView.swift
  - MacSlowdown/Sources/FirstRun.swift
  - MacSlowdown/Sources/FirstRunView.swift
  - MacSlowdown/Tests/NotificationDeliveryTests.swift
  - MacSlowdown/Tests/MuteAlertsTests.swift
  - MacSlowdown/Tests/FirstRunTests.swift
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1g.png`. Three related surfaces on one board. Existing implementation: `NotificationDelivery` (TASK-54, TASK-25) for the banner; the mute sheet and first-run experience do not exist.

**1. The notification banner.** Title "CPU maxed out for 6 minutes", body "Xcode is using about 4 of your 10 cores. Memory looks fine." — note it states what is *not* wrong as well as what is. Two actions: "Show details" and "Mute 1 hour".

**2. The mute sheet.** "Mute alerts for" with 30 minutes / 1 hour (ticked) / Until 6:00 PM / Until I turn it back on. Footer: "Monitoring keeps running while muted, so you'll still have the history afterwards." Mute suppresses interruption, never recording — that distinction is the point of the sheet.

**3. First run.** "Two things before we start", under the standing promise "Everything MacSlowdown records stays on this Mac."
- "Send notifications — Only for slowdowns that last long enough to matter."
- "Start watching at login — Needed to catch slowdowns you didn't see coming."
- A paragraph setting expectations about unattributable system activity *before* the user ever sees it: "Some system activity — backups, indexing, the window server — can't be broken down by App Store apps. We'll always show you how much of the load that is, and what was running."
- "You can change both later in Settings. Nothing is uploaded anywhere — there's no account and no server."
- One button: "Start watching".

**Why first run matters more than it looks**

It is where the ~40% unattributable figure stops being a disappointment and becomes an expectation the app set honestly. It is also where notification permission is requested in context rather than as a bare system prompt — and CLAUDE.md records that a notification macOS accepts is not one the user saw, so the permission moment deserves care.

"Start watching at login" depends on TASK-16 (SMAppService login item), currently parked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The notification body states what is not wrong alongside what is, and offers both a details action and a mute action
- [x] #2 The mute sheet offers durations including an indefinite option, and states that recording continues while muted
- [ ] #3 Muting suppresses interruption only -- incidents raised while muted still appear in history, marked as not alerted
- [x] #4 A first-run experience requests notification and login-item permission in context, with the local-only guarantee stated
- [x] #5 First run sets the expectation that a share of system activity cannot be attributed, before the user encounters it
- [ ] #6 Verified on screen against design/screens/1g.png, including seeing an actual banner rather than trusting that the API returned without error
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built (TASK-65.7)

**1. Banner** (`NotificationDelivery.swift`). `NotificationDelivery.message(...)` wraps `NotificationGate.message` and appends a clause saying what is *not* wrong. The clause is a measurement, not politeness: drawn only from conditions the detector watched throughout the incident and never saw breach. The memory claim requires **two** pieces of evidence — `.memoryPressure` absent from `conditions` *and* `peakMemoryPressure == .normal` — because memory is the resource users most often assume is at fault. A `.warning` peak withholds it and falls through to thermal. An incident breaching everything claims nothing is fine. One clause only; a banner is two lines.

Two actions via `UNNotificationCategory`: "Show details" and "Mute 1 hour". `perform(actionIdentifier:)` carries the behaviour, separated from the delegate callback because `UNNotificationResponse` cannot be constructed in a test — the same seam reason as `foregroundPresentationOptions`. Wired in `MacSlowdownApp` to `MainWindowOpener.open()` and `store.mute(forMinutes:)`.

**2. Mute sheet** (`MuteAlerts.swift`, `MuteAlertsView.swift`). 30 minutes / 1 hour / Until <end of day> / Until I turn it back on, with the footer. Reached by ⌥⌘M (a `CommandGroup` on the main window), hosted as a sheet there.
  - Indefinite is `indefiniteMinutes` (100 years) because `MonitorStore.mute(forMinutes:)` is the only vocabulary available and `MonitorStore` was off-limits. A real date, so nothing downstream handles an infinity; `isIndefinite` reads it back as indefinite rather than as a long count of minutes.
  - "Until 6:00 PM" is withheld inside 10 minutes of the hour and after it. A control that appears to act and does not is worse than an absent one, and rolling to tomorrow would mean something other than what it says.
  - Selection shown by checkmark **and** fill, never colour alone (FR-034).

**3. First run** (`FirstRun.swift`, `FirstRunView.swift`). A `Window` scene, not a sheet: at first launch this menu bar utility has no window for a sheet to attach to. Opened once from scene evaluation via `FirstRunWindowOpener.presentOnceAfterLaunch()`, deferred through a `Task` because a window cannot be opened while the scene graph is being built, and skipped under XCTest.
  - Copy lives in `FirstRunCopy` so the two clauses that are requirements rather than decoration can be asserted: the local-only guarantee (A-05/FR-029) and the unattributable paragraph (FR-013/FR-038).
  - Notification permission is requested by the toggle, in context, reusing `NotificationDelivery.requestAuthorisation()`. A denial reads as a denial rather than the screen claiming a permission it does not hold.
  - Start-at-login uses the existing `LoginItem`, disabled with the real `unavailableFromThisLocation` sentence outside Applications. TASK-16 stays parked; no toggle is presented as working when it cannot.
  - Two permissions only. Tested that it does not restate sensitivity, thresholds, retention or the menu bar item, all of which `SettingsView` owns.

**How a test reaches first run.** `FirstRunState` takes its `UserDefaults`. Without that seam the only machine able to test a first launch would be one that had never had a first launch. Tests hand in a throwaway `UserDefaults(suiteName:)` and get a genuine fresh install. Key `firstRun.completed`; only "Start watching" sets it, so a window closed without a decision leaves the screen still owed.

## Criterion 3 — deliberately left unchecked

The behavioural half is done and tested: the gate suppresses while the detector, which knows nothing about muting, still produces the incident. `NotificationDelivery` now records an `AlertOutcome` per incident id — `.alerted` / `.notAlerted(reason:)`, bounded to 200 — populated by the **existing production path**, because `MonitorStore` already calls `deliver` for suppressed decisions too. No `MonitorStore` edit was needed. `outcome(for:)` returns nil when no decision was recorded, and nil is not "not alerted" (FR-002).

What is missing is the display. The note ("Not alerted — … It was still recorded.") is rendered nowhere: `IncidentsView`, `IncidentHistory` and `IncidentDetailView` were off-limits (TASK-65.6 / TASK-65.5 running concurrently). **Follow-up for whoever owns the Incidents list: read `MonitorStore.shared.notifications.outcome(for: incident.id)?.note`.** Marking this done on a passing unit test would break the project's own rule.

## Not verified — needs a human at the screen

- **Criterion 6.** No screen use and no TCC prompt were permitted, so no real banner was raised. `center.add` returning without error is not a banner anyone saw. Nothing here was compared against `design/screens/1g.png` on screen.
- **First-run window visibility under `LSUIElement`.** The app is accessory-policy, so a window it opens is not guaranteed to come forward. `presentIfNeeded` calls `NSApp.activate()` (skipped under XCTest), but whether an accessory application can raise this window without also taking a Dock icon is untested. Highest-risk unknown in the change: if it fails, first run is invisible.
- **Whether the action buttons appear.** The category is registered and the content carries its identifier, but macOS shows action buttons only on an expanded banner, and that was not seen.

## Known rough edge

`PopoverPresentation.muteStatus` (off-limits) formats a mute as raw minutes, so an indefinite mute chosen in the sheet reads in the popover as roughly 52,560,000 minutes. `MuteAlerts.status(for:now:)` is the corrected version and handles both forms; the popover should be pointed at it.

## Tests

688 passing, from a measured baseline of 648 on this branch (+40). One failure, `EndToEndIncidentTests.realSlowdownProducesOneIncident` — confirmed pre-existing by re-running it with these changes stashed, where it fails identically. It synthesises real CPU load and five agents were running concurrently.

Committed on worktree branch `worktree-agent-a2db59ae52bef18f8` as `fe4e218`, rebased onto `5e83393`. Left **In Progress**: criteria #3 and #6 are genuinely outstanding, and #6 needs a person at the screen.
<!-- SECTION:NOTES:END -->
