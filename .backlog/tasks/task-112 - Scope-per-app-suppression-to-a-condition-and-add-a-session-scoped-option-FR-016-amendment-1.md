---
id: TASK-112
title: >-
  Scope per-app suppression to a condition, and add a session-scoped option
  (FR-016 amendment 1)
status: To Do
assignee: []
created_date: '2026-09-06 16:53'
labels:
  - core
  - ui
milestone: m-3
dependencies:
  - TASK-111
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
"This application's heavy load is expected" is not "this application can never cause a problem", and the product currently treats the first as the second. An app marked expected for CPU load must still be able to appear in a memory-pressure finding.

**Two problems with the current shape.**

1. **Suppression is application-wide.** Learning that compiles are normal should not silently disable a warning about running out of memory. An application is not a specific enough description of the nuisance.
2. **Keying on "the leading measurable contributor" is unstable.** That ranking is incomplete by construction (FR-055) — a large share of activity is unattributable — so a small ranking change could decide whether otherwise identical conditions announce. The rule must name what it suppresses rather than inferring it.

**What to build.** A rule reads as "mute CPU-load alerts from Xcode": one application, one condition type, visible and reversible from a single place. Plus a **session-scoped** option — "quiet for this work session" — which covers the common case of someone doing something heavy *now* rather than always, and expires without them having to remember it.

**Placement matters as much as scope.** The rule has to be offerable at the moment of annoyance, not only from Settings. Nobody opens a preferences window to fix a notification; they turn notifications off. That part of the earlier analysis (TASK-108) stands.

Note this is partly superseded in urgency by TASK-111: if sustained CPU no longer announces by default, the most common false-positive class disappears and this becomes less pressing. Do TASK-111 first and re-judge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A rule names the condition it suppresses, and suppressing one condition never suppresses another
- [ ] #2 A session-scoped rule exists and expires without user action
- [ ] #3 Every rule is visible and reversible from one place
- [ ] #4 A rule can be created from the notification, not only from Settings
- [ ] #5 Suppression does not depend on which contributor happened to rank first
<!-- AC:END -->
