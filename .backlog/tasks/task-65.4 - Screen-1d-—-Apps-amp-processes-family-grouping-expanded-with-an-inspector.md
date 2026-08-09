---
id: TASK-65.4
title: 'Screen 1d — Apps &amp; processes: family grouping expanded, with an inspector'
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
Reference: `design/screens/1d.png`. Current state: `screenshots/03-apps-processes.png`. Existing implementation: `ProcessInventoryView`/`InventoryRow` (TASK-12, TASK-56, TASK-60, TASK-61).

**What the design specifies**

A segmented control at the top switching "Apps · 20" and "All processes · 412" (the latter is screen 1m), with a search field beside it.

Table columns: Name, CPU, Memory, PID, Started. A family row expands to show its members with their individual PIDs and start times; a member matched only by heuristic carries a "Grouped by guess" chip. Long tails collapse: "19 more helpers below 1%". Families below a threshold roll into a single "Other applications — 16 apps, each below 12%" row. Spotlight carries "Partial · Protected".

A footer states the census honestly: "20 apps · 63 of 412 processes belong to an app · 234 not measurable", plus "Updated 1 s ago" and a note that daemons appear under All processes.

**The inspector** is the substantial missing piece — a right-hand pane for the selected family:
- Icon, name, "Version 141.0 · /Applications"
- A "Last 15 minutes" chart with CPU / Memory tabs
- Figures: CPU (family) "147% · 1.5 cores", Resident memory, "Growth, 2 hrs +1.9 GB", "Relaunches today 0", "Disk activity — Not available"
- Two standing caveats: resident vs Activity Monitor's footprint, and per-app disk being unavailable
- **Safe actions**: Bring to front, Show in Finder, Copy diagnostics, "Treat this app's load as expected…", with the line "Quitting and pausing apps aren't available in the App Store version. Use Chrome's own Task Manager to close a tab."
- **Grouping** provenance: "22 processes matched by bundle ID. 1 matched by name pattern only." with "Split out…" and "Merge into…" (FR-039, user correction of attribution — TASK-35).

**Gap against what we render today**

We have the table with Application / CPU / Resident memory / Processes, expandable families, and a System processes group. Missing: the Apps vs All processes segmented control, the PID and Started columns, per-member rows showing PID and start time, the "grouped by guess" provenance chip, the collapsed-tail and "Other applications" rows, the census footer, the freshness line, and the entire inspector with its charts, safe actions and grouping controls.

Our "System processes / 237" group is the equivalent of the design's unmeasurable census but is presented as a family rather than as a stated count.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The view offers both an application-grouped list and an all-processes list, switchable, with counts on each
- [ ] #2 Expanding a family shows its member processes with PID and start time, and marks any member grouped by heuristic rather than by a strong signal
- [ ] #3 A selected family opens an inspector showing recent history, family totals, growth, relaunch count, and explicitly labels disk activity as unavailable
- [ ] #4 The inspector offers only non-destructive actions and states plainly that quitting and pausing are not available (FR-037)
- [ ] #5 The inspector shows how the grouping was decided and allows the user to correct it (FR-039)
- [ ] #6 A footer states how many processes belong to an app and how many are not measurable, and when the data was last updated
- [ ] #7 Verified on screen against design/screens/1d.png
<!-- AC:END -->
