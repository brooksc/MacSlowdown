---
id: TASK-47
title: Stay responsive and honest under severe load (FR-032)
status: Done
assignee: []
created_date: '2026-08-02 02:28'
updated_date: '2026-08-02 03:58'
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
- [x] #1 Under a controlled saturation test, status updates continue
- [x] #2 Sampling cadence degrades gracefully rather than dropping samples silently
- [x] #3 Stale readings are visibly labeled with their age, never shown as current
- [x] #4 Monitoring components recover automatically after load clears, no reinstall prompt
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Both halves done: the sampling behaviour and the UI states it implies.

Verified by a saturation test that runs one spinner per logical core plus two, so nothing is left idle for us:
- AC#1 All four sampling rounds completed under full saturation and produced usable attribution. Status updates continue during exactly the condition the product exists to diagnose.
- AC#2 The slowest sweep under saturation stayed under 1s, and no sample was silently dropped -- MonitorStore measures the actual interval and marks the reading stale when it runs materially long, rather than presenting a late sample as current.
- AC#4 After terminating the load, sampling resumed with no restart or intervention and sweep duration returned under 100ms.

Readings stay coherent under load: attributed + unattributed still equals the measured total to within 0.001 points in every round, and total busy exceeded 50% per core, confirming the machine really was saturated rather than the test passing vacuously.

- AC#3 Stale readings are labeled with their age in both surfaces. NowView shows a banner reading "These readings are catching up... this is the last reading we trust, from N seconds ago -- not a guess at what is happening now", and the menu bar header shows "Last complete reading, Ns ago". Nothing is estimated forward, per FR-038.

The Freshness type is part of the store's state rather than a view concern, so a stale reading cannot be rendered as current by a view that forgets to check.
<!-- SECTION:NOTES:END -->
