---
id: TASK-65.8
title: >-
  Screen 1h — The unattributable incident, told honestly (~40% of real
  slowdowns)
status: To Do
assignee: []
created_date: '2026-08-09 02:23'
labels:
  - ui
  - core
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1h.png`. No implementation exists. This is the single most important screen in the set for this product's credibility, because CLAUDE.md measured that ~40 percentage points of busy CPU is unattributable in the MAS build.

**What the design specifies**

Headline: "Something outside your apps used the CPU for 8 minutes". The opening paragraph states the limit without apology: "None of your open apps accounts for it — 79% of the load came from system processes that macOS doesn't let us look inside. We can tell you what happened, and which system processes were running at the time — but not how much CPU any of them used."

- **Where the CPU went** — contributor bars totalling 100%, unattributed at 79% as the largest bar.
- **Total CPU** chart with started/recovered markers.
- **What we found** — Measured / Calculated / "Likely, moderate confidence" / Ruled out. The Likely paragraph is a model of inference discipline: `backupd` started two minutes before the rise and ran the whole window, *and* the shape of the load (sharp start, flat plateau, clean stop, no memory or storage change) matches a backup — "We can see that it was running; we can't measure how much CPU it used, so this is an inference from timing, not an attribution."
- **What was running** — "Measured — names and timing only, never their CPU". Lists Time Machine (`backupd`, started 11:02, exited 11:13), Spotlight system indexer (`mds_stores`, running throughout), Software update (`softwareupdated` — **not running**). Listing what was *absent* is evidence too.
- **Why we can't name it** — a plain explanation of the sandbox limit, ending "The 79% above is a real measurement of what's left over, not a rounding error" and pointing out that Activity Monitor is unsandboxed and can see inside.
- **What you can do** — Open Activity Monitor, Check Time Machine, Check for a software update; plus "I know what this was…" letting the user label it so the pattern is recognised next time, stored locally.
- **Has this happened before?** — "Three unattributed CPU incidents in the last 14 days, all between 11:00 and 11:30 on a weekday. A regular time of day is a strong hint that it's scheduled work rather than something you did."

**What this requires that we have**

Process lifecycle and start/stop times for unmeasurable processes are readable — CLAUDE.md confirms name, PID, parent and start time are available for all 234, only CPU and memory are denied. So the timing evidence this screen is built on is obtainable. The recurrence analysis needs incident history with time-of-day clustering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An incident whose load is mostly unattributable produces this presentation rather than a contributor list that silently fails to sum (FR-013, FR-038)
- [ ] #2 The unattributed share is presented as a measured remainder, with the reason it cannot be broken down stated in plain language
- [ ] #3 System processes running during the window are listed by name and timing only, with an explicit statement that their CPU is not measurable, including processes that were notably absent
- [ ] #4 Any suggested cause is labelled as an inference from timing rather than an attribution, with its supporting evidence shown
- [ ] #5 The user can label an unattributed incident so the pattern is recognised later, stored only on this Mac (FR-039)
- [ ] #6 Recurrence across incidents is surfaced where a time-of-day or day-of-week pattern exists
- [ ] #7 Verified on screen against design/screens/1h.png
<!-- AC:END -->
