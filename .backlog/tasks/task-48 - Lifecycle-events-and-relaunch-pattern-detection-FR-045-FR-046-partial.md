---
id: TASK-48
title: 'Lifecycle events and relaunch-pattern detection (FR-045, FR-046 partial)'
status: To Do
assignee: []
created_date: '2026-08-02 04:17'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replaces the unresponsiveness half of FR-046, which TASK-27 measured as unavailable: no public API exposes hang state, and the system's hang reports are unreadable from the sandbox.

What IS deliverable, and fully: process lifecycle. sysctl gives name, pid, ppid and start time for every process including ones whose CPU we cannot read, so launches, exits, PID replacement and repeated relaunch are all observable.

Scope:
- Record lifecycle events by diffing consecutive snapshots on (pid, start time).
- Detect a relaunch pattern: the same executable identity exiting and restarting repeatedly within a window.
- Attach these to incidents so a contributor that vanished before the user looked is still explained (FR-045).

Do NOT claim hang detection. An app that freezes without exiting is invisible to us, and saying otherwise would be an unsupported claim under FR-038.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Launches, exits and PID replacements are recorded with timestamps
- [ ] #2 A relaunch loop in a test fixture appears as related events, not unrelated incidents
- [ ] #3 Uncertain attribution is labeled
- [ ] #4 No UI or copy anywhere claims an app was unresponsive or hung
<!-- AC:END -->
