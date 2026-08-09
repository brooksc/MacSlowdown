---
id: TASK-65.6
title: 'Screen 1f — Incidents: history and patterns'
status: To Do
assignee: []
created_date: '2026-08-09 02:23'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1f.png`. Current state: `screenshots/04-incidents.png` (currently renders blank — see TASK-51.1). Existing implementation: `IncidentsView` (TASK-51).

**What the design specifies**

More than a list. Top of the pane carries a range selector (7 days / 30 days) and a **pattern summary**: "9 incidents this week / Chrome appears in 5 of them", above a Mon–Sun strip showing when they fell. That summary is the feature — a single incident is an event, five with the same app in them is a finding.

Each row states condition and attributed app together ("CPU maxed out — Xcode", "Memory pressure — Chrome"), then a subtitle carrying date, duration, severity, and **outcome**, where outcome is a distinct vocabulary:
- "still going"
- "recovered after you acted"
- "resolved on its own"
- "Not alerted — you marked Handbrake as expected"

Row four is a repeated-crash incident ("Final Cut Pro quit unexpectedly — 3 times in 12 minutes … CPU and memory were both normal"), which is screen 1o's incident appearing in the list — so the list must carry lifecycle incidents, not only resource ones.

Footer: "Incidents are kept for 30 days on this Mac and never leave it unless you export one."

**Gap against what we render today**

Our rows carry condition, severity, start time, duration and recovered/still-going, which covers part of it. Missing: the range selector, the pattern summary and week strip, the app name in the row title, the richer outcome vocabulary (particularly "recovered after you acted" and "not alerted because you marked it expected"), and the retention footer. The empty state is currently broken (TASK-51.1) and must be fixed for this screen to be assessable at all.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The list is scoped by a selectable time range
- [ ] #2 A summary states how many incidents fell in the range and names any application recurring across several of them
- [ ] #3 Each row states the condition together with the attributed application, and its outcome using a vocabulary that distinguishes recovered-on-its-own, recovered-after-user-action, still-open, and suppressed-by-a-user-rule
- [ ] #4 Lifecycle incidents such as repeated unexpected quits appear in the same list as resource incidents
- [ ] #5 Retention and the local-only guarantee are stated on the screen (FR-029)
- [ ] #6 Verified on screen against design/screens/1f.png with several incidents of differing outcomes present
<!-- AC:END -->
