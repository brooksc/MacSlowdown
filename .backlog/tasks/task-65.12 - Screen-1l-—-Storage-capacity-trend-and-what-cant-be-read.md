---
id: TASK-65.12
title: 'Screen 1l — Storage: capacity, trend, and what can''t be read'
status: In Progress
assignee: []
created_date: '2026-08-09 02:24'
updated_date: '2026-08-09 03:09'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1l.png`. Current state: `screenshots/06-storage.png`. Existing implementation: `StorageView` (TASK-21, TASK-53).

**What the design specifies**

- Header "Storage" with freshness: "Checked 30 s ago".
- **Startup volume card**: "Macintosh HD — Startup volume · APFS · internal", a large "96 GB available of 1 TB", a segmented capacity bar, and a breakdown of In use / Purgeable ("roughly 48 GB — an estimate, not space you have") / Free.
- **Trend chart**: "Last 14 days — available space", with the headline finding stated in words: "**Down 62 GB in the last 6 days**". A 10% warning line is drawn at 100 GB, and the point where an incident opened is marked on the curve with a callout: "Startup disk below 10% free — Wed 8:41 PM, lasted 2 hr 14 min, resolved on its own. It's back above the line now, but the 6-day slide hasn't stopped." That last clause is the screen's reason to exist — recovered is not the same as fine.
- **Other volumes** (4 mounted): Time Machine (External, 1.16 TB free of 4 TB); design-share (Network — "Can't be read — network volumes aren't reported to App Store apps"); SAMSUNG T7 (Removable — "Excluded from monitoring · include").
- **Provenance footer**: Measured (capacity read from the volume), Calculated (the 6-day rate of change), Estimate (purgeable, "which macOS reports as a guess and may not actually release").

**Gap against what we render today**

We show one card for Macintosh HD with Available / In use / Capacity / Purgeable, each labelled Measured / Calculated / Estimate, a single progress bar, and the purgeable caveat. That is the provenance discipline already done well. Missing: the 14-day trend chart with the warning line and incident marker, the trend stated in words, every other volume, the network-volume and excluded-volume cases, and the freshness line.

The multi-volume cases are the substantive work: a network volume that cannot be read must appear and say so rather than being silently omitted (FR-002, FR-010).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The startup volume shows capacity with a trend over a period long enough to reveal a slide, with the finding stated in words and not only as a curve
- [ ] #2 The low-storage warning threshold is drawn on the trend, and any incident that opened against it is marked on the timeline (FR-041, FR-042)
- [ ] #3 A volume whose usage recovered but whose trend continues is described as such rather than as resolved
- [ ] #4 All mounted volumes appear, including ones that cannot be read, which state why rather than being omitted
- [ ] #5 Volumes excluded from monitoring are shown as excluded with a route to include them
- [ ] #6 Each figure keeps its provenance label, and purgeable space is never presented as space the user has
- [ ] #7 Verified on screen against design/screens/1l.png with more than one volume mounted
<!-- AC:END -->
