---
id: TASK-54
title: Notification delivery through UNUserNotificationCenter (FR-014)
status: Done
assignee: []
created_date: '2026-08-02 18:15'
updated_date: '2026-08-08 15:23'
labels:
  - core
  - phase1-catchup
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 1 of m-3. NotificationGate decides correctly and is tested, but nothing is ever delivered.

BLOCKED ON A PERMISSION PROMPT: requesting notification authorisation shows a system dialog on the user's machine and is a one-shot decision. Must stop and ask before triggering it.

Everything up to the prompt can be built and tested: the delivery adapter, the request content, and the wiring from detector to gate to centre. Authorisation state must be read back rather than assumed, in the same way FR-033's login item does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Delivery is wired from detector through the existing policy gate
- [x] #2 Authorisation state is read from the system, never cached from what we last requested
- [x] #3 A denied or undetermined authorisation degrades honestly and says so in settings
- [x] #4 No notification is delivered that the policy gate suppressed
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified end to end on macOS 27.0 (26A5388g) with a real sustained load, not a synthetic incident.

What was built:
- NotificationDelivery (MacSlowdown/Sources/NotificationDelivery.swift) wrapping UNUserNotificationCenter.
- MonitorStore calls NotificationGate.decide on every .opened/.updated event and passes the resulting NotificationDecision to delivery. Delivery takes the decision, never the incident, so there is no second code path that could re-decide and let a muted, Focus-suppressed or already-announced alert through.
- AudioSignals (Metrics/Sources/ThermalPowerSignals.swift) so the gate's InterruptionContext carries real audio state instead of a hardcoded false. FR-019's defer-during-playback rule now actually fires.
- A Notifications row in Settings that requests authorisation from an explicit user action. Never at launch: a monitor that interrupts you before it has measured anything has nothing to say yet.

What was measured:
1. Prompt triggered from Settings, allowed. The Settings row updated live from 'MacSlowdown has not asked to send notifications yet' to 'Allowed / Notifications are allowed'.
2. Seven niced busy loops for ~4 minutes. An incident opened ('CPU saturation, still going, 4 minutes 26 seconds so far, High') and a notification was delivered: 'CPU saturation for 3 minutes - Severity high. bash is the largest measurable contributor.'
3. Exactly one notification for the incident across its whole life, which is the property the gate exists to guarantee.

Bug found and fixed during verification. The first delivery succeeded but showed nothing on screen, because MacSlowdown was frontmost and macOS suppresses banners for the active application unless a UNUserNotificationCenterDelegate asks for them. Added registerForForegroundPresentation() plus a willPresent returning [.banner, .list], called once from AppDelegate. Re-ran the same load and captured the live banner. Without this the alert was reachable only by opening Notification Center, which defeats the point of FR-014.

Not covered by automated tests: NotificationDelivery lives in the app target, which has no test bundle (only MetricsTests exists). The gate logic it depends on is covered by NotificationPolicyTests; the adapter itself rests on the manual verification above.
<!-- SECTION:NOTES:END -->
