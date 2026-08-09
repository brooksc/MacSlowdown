---
id: TASK-69
title: >-
  Alert settings are saved but never applied — and changing a threshold
  mid-breach postpones the incident
status: Done
assignee: []
created_date: '2026-08-09 05:17'
updated_date: '2026-08-09 07:18'
labels:
  - core
milestone: m-3
dependencies: []
modified_files:
  - Metrics/Sources/Incident.swift
  - Metrics/Sources/NotificationPolicy.swift
  - Metrics/Tests/ThresholdChangeTests.swift
  - MacSlowdown/Sources/MonitorStore.swift
  - MacSlowdown/Sources/AlertSettings.swift
  - MacSlowdown/Sources/SettingsView.swift
  - MacSlowdown/Tests/AlertSettingsWiringTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two halves of one problem, found while building the Settings surface (TASK-65.9) and confirmed by TASK-66.

## 1. Nothing consumes the settings

`MonitorStore`'s `detector` and `notificationGate` are `private let`s built from `.default`. `AlertSettings.shared` now exposes `incidentPolicy`, `notificationSettings` and `privacySettings` ready to assign, but nothing reads them — so every control on the Alerts tab currently changes a stored value and no behaviour.

The two sessions blocked each other into this: 65.9 could not edit `MonitorStore`, and TASK-66 could not see `AlertSettings.swift` because it was on an unmerged branch. Both are merged now, so the circular block is gone.

Rather than ship inert toggles, 65.9 made the gap visible: `AlertSettings.isAppliedToMonitoring` drives a "Saved, but not yet in effect" notice. **Whoever wires this calls `markAppliedToMonitoring()` and the notice disappears with no copy change** — the design is already shaped for the handover, so do not rebuild it.

## 2. Changing a threshold mid-breach silently postpones the incident

Raised independently by both sessions, and it is the subtler half.

When a threshold changes while a condition is already breaching, the accumulated `breachStart` must be kept rather than reset — resetting restarts the sustained-duration clock and delays an incident that was already building.

But TASK-66 identified a second path to the same failure that keeping `breachStart` does not fix: **`breachStart` is only ever set while `breaches()` is true.** So *tightening* a threshold finds it nil for a condition that was sitting below the old line, and the clock starts from the next observation. A user tightens sensitivity precisely because something is bothering them right now, and the effect is to delay the incident by the full sustained duration — three minutes by default — for a condition that was present the whole time.

This is newly fixable because TASK-66 landed `retainedSamples`: 15 minutes of measured aggregate CPU means the sustained duration can be evaluated backwards over readings that actually happened, rather than only forwards from the change. **CPU only** — memory pressure and thermal state are not in the retained series — which is also the threshold most likely to be tightened.

TASK-66's recommendation, which I endorse: ship the simple version first (keep `breachStart`), and make "an incident opened dated three minutes before you changed a setting" a deliberate decision with its own test, rather than something discovered later by a confused user.

Do not implement persistence or retention defaults here — that decision is still with the product owner (TASK-65.10 criterion #6).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Changing alert sensitivity or an exact threshold changes detection behaviour in the running app, verified end to end rather than by asserting the stored value
- [x] #2 The 'Saved, but not yet in effect' notice retires by calling markAppliedToMonitoring(), with no change to its copy
- [x] #3 Notification settings from the Alerts tab reach the notification gate, including the audio and Focus deferrals to whatever extent each is actually implementable
- [x] #4 Changing a threshold while a condition is already breaching does not restart the sustained-duration clock
- [x] #5 Tightening a threshold onto a condition already present is handled deliberately -- either by evaluating the duration backwards over retained samples, or by a documented decision to start from the change, with a test either way
- [x] #6 Whichever behaviour is chosen, an incident dated earlier than the settings change is either impossible or explained in the interface
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was done (commit 40ebeba, worktree agent-a78cde339f8b032aa)

### Part 1 — the settings now reach behaviour

`MonitorStore.detector` and `notificationGate` are `var`, and `applyAlertSettings()` pushes `AlertSettings.incidentPolicy` into the detector and `AlertSettings.notificationSettings` into the gate. Called from `start()` (so the first observation is judged against the user's figures) and once per sample in `run()`, so a change takes effect within one cadence — a few seconds. Polling rather than an observation path: the only thing that machinery would buy is those seconds.

`AlertSettings` is **injected** (`MonitorStore(alertSettings:)`, nil by default; only `.shared` passes it), so every test that drives the detector directly still gets a store that reads no user preferences.

`applyAlertSettings()` calls `markAppliedToMonitoring()`. The "Saved, but not yet in effect" notice retires on its own with **no copy change**, exactly as 65.9 shaped it.

New read-only `MonitorStore.incidentPolicyInForce` / `.notificationSettingsInForce` — "the setting is stored" and "the monitor is using it" were the same claim in this app and were not the same fact, so anything stating what is in force reads it from the detector.

**Defect found and fixed while wiring.** "Tell me about slowdowns" turned off only set `minimumSeverity = .severe`, which *still announced severe incidents* to someone who had asked for silence. Added `NotificationSettings.announcesIncidents` (default true), checked first in `NotificationGate.decide`, mapped from `announceIncidents`. Detection and recording untouched either way.

**What does NOT reach behaviour, deliberately:** `AlertSettings.privacySettings`. `retention` and `recordFilePaths` are consumed by nothing. Retention would be a no-op anyway (history is memory-only, bounded to 20 incidents; retention is 7/30/90 days), and wiring it edges into the persistence decision that is still the product owner's (TASK-65.10 #6). `recordFilePaths` belongs to export redaction, in files another agent owns. The Privacy tab carries no "not yet in effect" notice, so nothing on screen claims otherwise — but this is a real remaining gap.

### Part 2 — changing a threshold mid-breach

`IncidentDetector.adopt(_:state:retainedCPU:maximumSampleGap:)` is now the only way the policy changes.

1. **`breachStart` is kept**, whichever way the threshold moved. A condition already building keeps every second it accumulated.
2. **Tightening is re-decided over retained readings.** `earliestRetainedBreachStart` walks the retained CPU series backwards from the most recent sample and stops at the first reading below the new threshold **and at any gap wider than 30 s**. An unmeasured stretch is never counted as one the condition held; a short retained series yields a *later* start, never an earlier one. Nil when the latest reading is below the threshold, so the claim is always about now — and the next live observation clears it if it disagrees.
3. **CPU only.** Memory pressure and thermal state are not in `retainedSamples`; their clock legitimately starts from the change. Tested.

**The decision taken on criteria #5/#6, and why.** Backwards evaluation, not "start from the change". A user tightens a threshold precisely because something is bothering them *now*; starting from the change delays the incident by the full sustained duration (3 min by default) for a condition present throughout — the failure this task was opened for. The consequence — an incident dated earlier than the settings change — is accepted as **true rather than made impossible**, because the readings are real, and it is made visible in two places:

- `Incident.beganAtEstablishedFromRetainedHistory` (Bool, default false) and `Incident.startProvenance`, a `Conclusion` labelled `.measured` explaining the date. Ordinary incidents carry nil.
- A caption in the Alerts tab's **Exact thresholds** disclosure, at the moment the choice is made: a changed threshold is judged against readings already kept, a slowdown under way is recorded from when it began, nothing is assumed for unmeasured stretches, and memory pressure's clock starts there.

**Handover:** `startProvenance` is not yet rendered by incident detail — `IncidentDetailView.swift` / `IncidentEvidence.swift` are owned by another agent (TASK-65.5). Whoever owns that surface should show it when non-nil. Criterion #6 is met by the Settings caption; the detail view would make it better.

### Files changed

- `Metrics/Sources/Incident.swift` — `IncidentPolicy: Equatable`; `State.breachStartFromRetainedHistory`; `RetainedCPUReading`; `adopt`; `earliestRetainedBreachStart`; `Incident.beganAtEstablishedFromRetainedHistory` + `startProvenance`; `open` stamps the flag, `observe` clears it with the breach.
- `Metrics/Sources/NotificationPolicy.swift` — `NotificationSettings.announcesIncidents` and its check in `decide`.
- `MacSlowdown/Sources/MonitorStore.swift` — injected `alertSettings`; `applyAlertSettings()`; `retainedCPUReadings`; `incidentPolicyInForce`; `notificationSettingsInForce`; `shared` passes `.shared`; `detector`/`notificationGate` are `var`.
- `MacSlowdown/Sources/AlertSettings.swift` — maps `announcesIncidents`; two stale doc comments corrected.
- `MacSlowdown/Sources/SettingsView.swift` — the threshold-change caption. Notice copy untouched.
- New: `Metrics/Tests/ThresholdChangeTests.swift` (12 tests), `MacSlowdown/Tests/AlertSettingsWiringTests.swift` (8 tests).

### Tests

`tuist xcodebuild test -scheme AllTests`: **exit 0, 770 passing, 0 failures**. Unmodified `eadc448` measured the same way is 750 — so +20 and no regression. My count is `✔` lines in the xcodebuild log; it differs from the 771 recorded in CLAUDE.md, which was counted by other means, so treat the *delta* as the reliable figure. CLAUDE.md's number was deliberately left alone because other agents are landing tests concurrently.

`EndToEndIncidentTests.realSlowdownProducesOneIncident` failed twice mid-session — on unmodified HEAD as well as with these changes — at its own "baseline CPU too high" guard, because the machine was busy building. Passes in isolation (23.7 s). Documented behaviour, not a regression.

**Process note worth keeping:** `tuist generate` globs sources, so a new test file added after generation compiles and runs as *nothing at all* — the build and the suite both go green while the new tests silently do not exist. That happened here and was only caught by counting. Always regenerate after adding a file, and check the new suite name appears in the log.

### Not verified

**Nothing was seen on screen** — no permission to use the display. So: the notice actually disappearing in the running app, the new caption's layout inside the Exact thresholds disclosure, and any VoiceOver reading of either are **unverified**. All three rest on code paths and unit tests only.

### Needs a human

- Whether `privacySettings` should reach anything is blocked on the persistence/retention decision (TASK-65.10 #6).
- Confirm the tightening decision above is the product's answer: it makes "an incident dated before a settings change" a normal, expected outcome.
- Look at the Alerts tab.
<!-- SECTION:NOTES:END -->
