---
id: TASK-65.7
title: 'Screen 1g — Notification, mute sheet, and first run'
status: To Do
assignee: []
created_date: '2026-08-09 02:23'
labels:
  - ui
milestone: m-2
dependencies: []
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
- [ ] #1 The notification body states what is not wrong alongside what is, and offers both a details action and a mute action
- [ ] #2 The mute sheet offers durations including an indefinite option, and states that recording continues while muted
- [ ] #3 Muting suppresses interruption only -- incidents raised while muted still appear in history, marked as not alerted
- [ ] #4 A first-run experience requests notification and login-item permission in context, with the local-only guarantee stated
- [ ] #5 First run sets the expectation that a share of system activity cannot be attributed, before the user encounters it
- [ ] #6 Verified on screen against design/screens/1g.png, including seeing an actual banner rather than trusting that the API returned without error
<!-- AC:END -->
