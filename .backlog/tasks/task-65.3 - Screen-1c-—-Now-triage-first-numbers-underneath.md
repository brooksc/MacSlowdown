---
id: TASK-65.3
title: 'Screen 1c — Now: triage first, numbers underneath'
status: To Do
assignee: []
created_date: '2026-08-09 02:22'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1c.png`. Current state: `screenshots/02-now.png`. Existing implementation: `NowView` (TASK-53, TASK-13).

**What the design specifies**

The organising idea is in the title: the verdict comes first, the numbers support it. Top to bottom —

1. **Window chrome**: title "Now" beside the machine identity ("MacBook Pro · M4 Pro · macOS 26.1"), a search field, and a "Mute alerts" button in the toolbar.
2. **Sidebar**: Now / Apps & processes / Incidents / Storage, with a count badge on Incidents when one is open. Below a "PROFILE" section listing Everyday / Heavy build / On battery with the active one marked.
3. **Incident banner** (only when one is open): headline "Xcode is using most of the CPU" with a "HIGH · 6 MIN" chip; a paragraph giving total CPU, how long, the contributor's share, the unattributable remainder, and what it rules out ("Memory pressure is still normal, so this looks like a build, not a memory problem"); three actions — Open incident, Bring Xcode forward, "Builds are normal for Xcode".
4. **Four metric cards**: CPU (big number, "% of 10 cores", sparkline), Memory pressure (state word, "22.4 GB of 36 GB in use · swap unchanged for 40 min"), Disk (MB/s write, sparkline), Thermals & power (state word, "On power adapter · no low-power mode"). Each card has a status dot.
5. **Contributor table**: App / CPU / Resident memory / Last 5 min sparkline, with disclosure triangles on families, icons, process counts, and status chips — "Can't be broken down" on unattributed, "Partial · System" on Spotlight, "Expected workload" on Photos.
6. **Two footnotes**: the percentage convention, and per-app disk being unavailable to App Store apps.
7. **Sidebar footer**: "Sampling every 1 s (incident cadence)" and "MacSlowdown itself: 0.4% CPU, 62 MB".

**Gap against what we render today**

Ours is a flat stack of text: severity word, a four-field grey box (memory pressure, thermal, power, disk), a three-row CPU box with Measured/Calculated labels, an unattributed paragraph, and machine details. Missing: the whole card layout, every sparkline, the contributor table (Now shows no per-app rows at all), the incident banner, the profile switcher, the search field, the mute control, the status dots, and the sampling-cadence line. The self-cost line exists.

Note the design's "MacSlowdown itself: 0.4% CPU, 62 MB" against our measured 307–418 MB — see TASK-55.1.

The profile switcher belongs to TASK-38 (named configuration profiles, To Do, low); this screen is where it surfaces.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Now leads with a verdict and, when an incident is open, an incident banner with actions -- not with a bare severity word above raw figures
- [ ] #2 CPU, memory pressure, disk, and thermals/power are presented as cards each carrying a state and its supporting figures
- [ ] #3 Now includes a contributor table with per-family CPU, resident memory and a short history, including unattributed system activity as a row
- [ ] #4 Attribution qualifiers are shown as chips on the rows they qualify (cannot be broken down, partial, expected workload)
- [ ] #5 The sampling cadence in force and our own cost are both stated
- [ ] #6 Verified on screen against design/screens/1c.png
<!-- AC:END -->
