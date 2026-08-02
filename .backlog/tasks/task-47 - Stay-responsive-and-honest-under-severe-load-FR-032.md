---
id: TASK-47
title: Stay responsive and honest under severe load (FR-032)
status: To Do
assignee: []
created_date: '2026-08-02 02:28'
labels:
  - core
milestone: m-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
I missed this when building the backlog. FR-032 requires the tool to keep working during the problem it exists to diagnose -- prioritise a minimal sampling path, bound work, recover components, preserve last known state.

The design review surfaced the user-facing half: there is currently no designed state for "sampling fell behind" or "this reading is 45 seconds old". FR-002 separately requires stale or unavailable values to be labeled. Under heavy CPU or memory pressure -- exactly when the user opens the app -- readings will lag, and silently showing stale numbers as current would violate FR-002 and FR-038.

Covers both the engineering behaviour and the UI states it implies.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Under a controlled saturation test, status updates continue
- [ ] #2 Sampling cadence degrades gracefully rather than dropping samples silently
- [ ] #3 Stale readings are visibly labeled with their age, never shown as current
- [ ] #4 Monitoring components recover automatically after load clears, no reinstall prompt
<!-- AC:END -->
