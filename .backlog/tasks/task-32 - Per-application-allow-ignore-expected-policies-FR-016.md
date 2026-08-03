---
id: TASK-32
title: Per-application allow/ignore/expected policies (FR-016)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:13'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ApplicationPolicy.swift: PolicyClassification, ApplicationPolicy, SuppressedDetection, PolicyStore.

- AC#1 An ignored or expected application does not trigger its alert, and the user can review and revoke. Removing a policy restores default behaviour completely with nothing lingering -- tested.

Policies key on the identity TASK-3 established as stable: signed bundleID first (survives app updates AND path changes -- tested by matching an app moved to a different volume), falling back to bundle path when no signature exists, falling back to display name only when neither is available.

The audit trail is the part that matters and is easy to get wrong. FR-016 requires suppressed detections remain reviewable, so PolicyStore records every suppression with the application, classification, severity and time. Without it a policy becomes a way to hide evidence from yourself, which is the opposite of the intent. Bounded at 200 entries, most recent first.

The separation the whole design rests on: a policy changes what INTERRUPTS, never what is RECORDED. PolicyClassification.suppressesNotification is the only behavioural hook, and nothing in the store touches history.
<!-- SECTION:NOTES:END -->
