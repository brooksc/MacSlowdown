---
id: TASK-69
title: >-
  Alert settings are saved but never applied — and changing a threshold
  mid-breach postpones the incident
status: To Do
assignee: []
created_date: '2026-08-09 05:17'
labels:
  - core
milestone: m-3
dependencies: []
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
- [ ] #1 Changing alert sensitivity or an exact threshold changes detection behaviour in the running app, verified end to end rather than by asserting the stored value
- [ ] #2 The 'Saved, but not yet in effect' notice retires by calling markAppliedToMonitoring(), with no change to its copy
- [ ] #3 Notification settings from the Alerts tab reach the notification gate, including the audio and Focus deferrals to whatever extent each is actually implementable
- [ ] #4 Changing a threshold while a condition is already breaching does not restart the sustained-duration clock
- [ ] #5 Tightening a threshold onto a condition already present is handled deliberately -- either by evaluating the duration backwards over retained samples, or by a documented decision to start from the change, with a test either way
- [ ] #6 Whichever behaviour is chosen, an incident dated earlier than the settings change is either impossible or explained in the interface
<!-- AC:END -->
