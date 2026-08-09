---
id: TASK-76
title: >-
  Suppressed detections are never recorded, so the FR-016 audit trail is
  permanently empty
status: To Do
assignee: []
created_date: '2026-08-09 18:51'
labels:
  - core
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`).

`NotificationGate.decide` returns `.suppress(reason:)` when a per-application policy classifies an app as expected — that part works, and the alert genuinely is withheld. But `MacSlowdown/Sources/MonitorStore.swift:575` takes the decision, hands it to `notifications.deliver` and drops it otherwise. Nothing ever constructs a `SuppressedDetection`.

Consequently:

- `PolicyStore.recordSuppression` (`Metrics/Sources/ApplicationPolicy.swift:192`) has 8 test references and zero callers.
- `PolicyStore.suppressedDetections(forIncident:)` (`:188`) has no caller.
- `MonitorStore.record(suppression:)` (`MacSlowdown/Sources/MonitorStore.swift:179`) is written, documented and never called.
- `SuppressedDetectionsSheet` (`MacSlowdown/Sources/SettingsView.swift:429`) reads `MonitorStore.shared.policies.suppressedDetections`, which is always empty, so the sheet can only ever render its empty state.

The last point is the sharp end. The empty state reads "Nothing has been suppressed by a rule. Every slowdown MacSlowdown [detected was shown]" — which is a false statement whenever a rule did suppress something. FR-016 exists so a user can ask "why was I not told", and today the app answers "you were told about everything" regardless of the truth.

Note the framework is complete: `SuppressedDetection.linked(to:)`, the incident-side `suppressions` array and `Incident.outcome`'s `.notAlerted(suppression)` case are all built and tested. Only the call is missing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When NotificationGate returns .suppress for a policy reason, a SuppressedDetection is recorded via PolicyStore.recordSuppression and linked to the open or covering incident through MonitorStore.record(suppression:)
- [ ] #2 A suppression caused by muting or by audio deferral is distinguishable from one caused by a per-application policy, and the sheet does not misattribute one as the other
- [ ] #3 The suppressed-detections sheet shows a real recorded suppression after a policy withholds an alert
- [ ] #4 The empty state is only shown when nothing was in fact suppressed, so its copy is true
- [ ] #5 probe/seam-reachability.sh no longer reports recordSuppression
<!-- AC:END -->
