---
id: TASK-76
title: >-
  Suppressed detections are never recorded, so the FR-016 audit trail is
  permanently empty
status: In Progress
assignee: []
created_date: '2026-08-09 18:51'
updated_date: '2026-08-09 20:22'
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
- [x] #1 When NotificationGate returns .suppress for a policy reason, a SuppressedDetection is recorded via PolicyStore.recordSuppression and linked to the open or covering incident through MonitorStore.record(suppression:)
- [x] #2 A suppression caused by muting or by audio deferral is distinguishable from one caused by a per-application policy, and the sheet does not misattribute one as the other
- [ ] #3 The suppressed-detections sheet shows a real recorded suppression after a policy withholds an alert
- [x] #4 The empty state is only shown when nothing was in fact suppressed, so its copy is true
- [x] #5 probe/seam-reachability.sh no longer reports recordSuppression
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Fixed — the decision is now recorded (2026-08-09)

**What changed.** `NotificationGate.decide` gained a structured `SuppressionCause` alongside its reason string (`Metrics/Sources/NotificationPolicy.swift`); `NotificationDecision.suppress` now carries `(reason:cause:)`. The reason string was never safe to parse back into a cause, and criterion #2 turns entirely on telling a rule from a mute.

`MonitorStore.announce(incident:leadingContributor:context:at:)` is new — the notification step lifted out of `run()` as a drivable seam, the same move TASK-71 made for `currentObservation`. It decides, and when the cause is `.applicationPolicy` calls `recordPolicySuppression`, which writes a `SuppressedDetection` to `PolicyStore.recordSuppression` **and** links it to the incident through `MonitorStore.record(suppression:)`. Both previously had zero callers.

The classification comes from the rule that actually matched; if the store holds no matching rule nothing is recorded, because writing `.expected` by default would be inventing the user's decision in the one place that exists to report it.

`MonitorStore.notifications` became injectable (defaulting to the real delivery) purely so a test can drive `announce` without putting a banner on the user's screen.

**Criteria.** #1, #2, #4, #5 checked. **#3 is not checked**: nobody has opened the Apps tab, clicked "Review what these rules hid…" and seen a row. The precise check that would settle it: mark a busy application expected, let a slowdown open an incident for it, then open that sheet and confirm one row naming the application, its classification and the time. Everything up to what is drawn is asserted — `policies.suppressedDetections` is non-empty and the incident's own `outcome` is `.notAlerted`.

**Copy.** The empty state now also names muting and audio deferral as reasons that are *not* listed here, so a reader cannot take "nothing was suppressed by a rule" as "nothing was withheld".

**Tests.** `MacSlowdown/Tests/SuppressionAndPathRecordingTests.swift`, suite "A rule that withholds an alert writes down that it did" — 5 tests, all driving `MonitorStore.announce`: a policy suppression reaching the trail and the incident; a mute suppressing without entering the trail; an audio deferral likewise; an announced incident writing nothing; an unmatched rule recording nothing rather than guessing.

Full suite on the rebased branch: **963 passing, 0 failing** (`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .build`). Main at fded4a3 was 954.

`probe/seam-reachability.sh`: **16 unexplained before, 15 after**; `recordSuppression` is gone from the list.

**Still open, deliberately.** `PolicyStore.suppressedDetections(forIncident:)` still has no caller — the incident carries its own `suppressions` array, which is what the outcome reads, so the query is redundant rather than missing. The seam script does not flag it. Separately, `IncidentHistory.Entry.init` never passes a suppression, so the Incidents list will not print "Not alerted — you marked X as expected" even though the incident now holds the evidence; `IncidentHistory.swift` is owned elsewhere and the one-line diff is in the agent report.

Commit: `2a0eb18` on `worktree-agent-a09f64177e86529db`.
<!-- SECTION:NOTES:END -->
