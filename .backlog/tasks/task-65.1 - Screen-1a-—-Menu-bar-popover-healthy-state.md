---
id: TASK-65.1
title: 'Screen 1a — Menu bar popover, healthy state'
status: In Progress
assignee: []
created_date: '2026-08-09 02:21'
updated_date: '2026-08-09 04:43'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1a.png`. Current state: `screenshots/01-menubar-popover.png`. Existing implementation: `MenuBarContentView.swift` (TASK-11).

**What the design specifies**

A reassurance-first popover, not a dashboard. Top line is a plain-language verdict — "Your Mac is running normally" — under it "No slowdowns in the last 24 hours. Watching since 8:02 AM." That second line does two jobs: it says nothing is wrong *and* proves monitoring is actually running, which "no incidents" alone does not.

Then a four-up strip of headline figures: CPU, Memory pressure, Disk, Storage free. Then "Using the most CPU now" — a short contributor list with app icon, name, process count ("Safari · 9 processes"), and percentage. Unattributed system activity sits in that list as a peer row with an info affordance, not as a footnote. Spotlight indexing is marked "(partial)". A footer states the percentage convention. One button: "Open MacSlowdown".

**Gap against what we render today**

The current popover opens with the severity word "Normal" and goes straight to numbers: Total CPU, three contributor rows, Other applications, Unattributed system activity, the percentage note, then Open and Quit buttons. Missing: the plain-language verdict sentence, the "watching since" line, the four-up metric strip (memory pressure, disk and storage free appear nowhere in the popover), app icons and process counts on contributor rows, and the "(partial)" qualifier. Present but not in the design: a "Quit MacSlowdown" button.

Also note the contributor names in our build are wrong in a way the design assumes solved — `2.1.220`, `com.apple.Safari…` — tracked separately as TASK-57.1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The popover leads with a plain-language verdict sentence and a line stating how long monitoring has been running, not with a bare severity word
- [ ] #2 Headline figures cover CPU, memory pressure, disk and storage free
- [ ] #3 Contributor rows carry an icon, the application name, the process count where the family has more than one, and the percentage
- [ ] #4 Unattributed system activity appears as a peer row with an explanation affordance, and partial attribution is marked as partial
- [ ] #5 Verified on screen against design/screens/1a.png, with any deliberate divergence recorded and justified
<!-- AC:END -->
