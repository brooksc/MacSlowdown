---
id: TASK-25
title: 'Notification policy (FR-014, FR-015)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:57'
labels:
  - ui
milestone: m-2
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No more than one notification per incident unless severity materially increases
- [ ] #2 Focus and user settings respected
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
NotificationPolicy.swift: NotificationDecision, MuteState, InterruptionContext, NotificationSettings, NotificationGate.

- AC#1 One notification per incident unless severity materially increases. Tested by evaluating one ongoing incident 20 times and asserting exactly one send, with every subsequent decision reporting 'already announced'. Escalation from high to severe announces once more and then falls silent again; a DROP in severity does not re-announce, which would otherwise let an incident oscillating around a boundary alert repeatedly. Separate incidents announce separately.
- AC#2 Focus and user settings are respected, and every suppression states its reason rather than silently dropping the alert. Focus suppression explicitly says the finding is waiting in Incidents, so the user knows nothing was lost -- a test asserts that, since a silent suppression would be indistinguishable from a missed detection.

FR-019 is now wired in for real rather than deferred: TASK-28 measured per-application audio activity as available with no microphone permission, so an alert defers while audio is playing or the microphone is in use, and the reason names the application ('audio is playing or the microphone is in use (Zoom)'). Configurable off.

FR-016 expected-application suppression names the application in the reason, so the rule is discoverable rather than mysterious.

FR-015 muting suppresses interruption only -- monitoring continues, so history is intact when the mute expires. The remaining time is reported, and expiry is automatic rather than needing a reset.

Notification copy is asserted to name the resource and the largest MEASURABLE contributor, never a cause: forbidden list covers caused, because, fix, free up, wasted, hung, frozen, unresponsive.

Delivery through UNUserNotificationCenter is not implemented here -- this is the policy layer, which is the part with rules worth testing. Wiring the actual notification and its authorisation prompt belongs with the app integration, and the prompt is a permission I should not trigger unattended.
<!-- SECTION:NOTES:END -->
