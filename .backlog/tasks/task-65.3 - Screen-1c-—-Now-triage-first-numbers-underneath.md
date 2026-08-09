---
id: TASK-65.3
title: 'Screen 1c — Now: triage first, numbers underneath'
status: Done
assignee: []
created_date: '2026-08-09 02:22'
updated_date: '2026-08-09 03:30'
labels:
  - ui
milestone: m-1
dependencies: []
modified_files:
  - MacSlowdown/Sources/MainWindowView.swift
  - MacSlowdown/Sources/NowPresentation.swift
  - MacSlowdown/Tests/NowPresentationTests.swift
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
- [x] #1 Now leads with a verdict and, when an incident is open, an incident banner with actions -- not with a bare severity word above raw figures
- [x] #2 CPU, memory pressure, disk, and thermals/power are presented as cards each carrying a state and its supporting figures
- [ ] #3 Now includes a contributor table with per-family CPU, resident memory and a short history, including unattributed system activity as a row
- [ ] #4 Attribution qualifiers are shown as chips on the rows they qualify (cannot be broken down, partial, expected workload)
- [x] #5 The sampling cadence in force and our own cost are both stated
- [ ] #6 Verified on screen against design/screens/1c.png
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Implemented (commit 7566a0a, worktree agent-adac1178172972fd1)

**Files.** Modified `MacSlowdown/Sources/MainWindowView.swift`. Created
`MacSlowdown/Sources/NowPresentation.swift` (formatting and row-selection rules,
kept out of the view so they are reachable from a test) and
`MacSlowdown/Tests/NowPresentationTests.swift` (19 tests). Nothing under
`Metrics/Sources/` was touched.

**Now, top to bottom:** enumeration/stale banners (unchanged) -> incident banner
when one is open -> verdict -> four metric cards -> contributor table ->
footnotes. Sidebar carries an Incidents badge and a footer with the cadence in
force and our own cost. Toolbar carries the mute control and the machine
identity as `navigationSubtitle`. A search field filters the contributor table,
with an empty state that says nothing *matched* rather than nothing is running.

**Incident banner.** Headline and body are `IncidentSummarizer`'s own output,
rendered line by line via `Conclusion.display`, so each statement keeps its
evidence class and each hypothesis its confidence (FR-013, FR-038). Chip is
`severity + elapsed`. Actions: *Open incident* (switches the sidebar) and
*Bring <leader> forward* via `ActionPerformer.activate`, which reports the actual
`ActionResult` rather than assuming success (FR-017). The leader's record is
matched on `(pid, start time)`, never pid alone.

**Cards.** CPU (total % of one core + machine-relative), Memory pressure (kernel
state word + in-use figure + swap activity), Disk (write rate, read rate,
per-app limitation in the tooltip), Thermals & power (state + power summary).
Each carries a symbol and a word, never colour alone (FR-034), and an
unreadable value renders as "Unavailable", never as zero (FR-002). The memory
in-use figure is active + wired + compressed, labelled *calculated*; inactive
pages are excluded because they are reclaimable cache (FR-007, DR-08).

## Omitted, with the reason (data honesty)

- **Every sparkline (CPU card, disk card, "Last 5 min" column).** `MonitorStore`
  holds its `MetricsHistory` in a `private let` and exposes no accessor, so no
  retained series is reachable from the UI at all. Exposing it means editing
  `MonitorStore.swift`, owned by another agent concurrently. Accumulating a
  series inside the view instead would draw a *different* series from the one
  FR-005 retains, starting when the window opened. This is the gap TASK-58
  exists to close.
- **"Swap unchanged for 40 min".** Nothing timestamps the last change to the
  paging counters; only the current rate is kept. The card shows
  `store.swapActivity` instead.
- **"Expected workload" chip and the banner's third action ("Builds are normal
  for Xcode").** `PolicyStore` exists in `Metrics` but **nothing in the app owns
  an instance** -- `grep PolicyStore MacSlowdown/Sources` returns nothing. The
  chip would have no source but invention. Wiring it belongs to FR-016 /
  TASK-65.10.
- **Profile switcher** -- TASK-38, out of scope here.
- **Marketing machine name** ("MacBook Pro - M4 Pro"). No public API we can read
  returns it; `hw.model` gives `Mac14,15` and that is what is shown.

## Tests

Full suite: **405 passing, 2 failing**. Both failures are the known
load-sensitive `MetricsTests` cases (`realSlowdownProducesOneIncident`, "Two
single-core workloads each read as roughly one core") with several agents
building concurrently; both **pass when re-run in isolation**, so the effective
total is **407 passing** against a 388 baseline (+19 new).

New coverage: verdict wording per severity and before the first reading; memory
in-use excluding inactive pages and returning nil when counters are unreadable;
disk figures as per-second rates; the cadence line and its not-yet-established
case; machine identity; the system-processes row surviving truncation and never
being duplicated; chips; search by family or child name; the incident chip; the
summary being well formed; `(pid, start time)` matching for the safe action;
footnotes carrying the CPU convention, the topology note and the per-app disk
limitation.

## Criteria

- #1, #2, #5 met.
- **#3 partially met, left unchecked** -- the contributor table ships with
  per-family CPU, resident memory, process counts, expansion to member processes
  and the unattributed system row, but **not** the short history, for the
  sparkline reason above.
- **#4 partially met, left unchecked** -- "Can't be broken down" and "Not
  measurable" chips ship, as do the grouping qualifiers (uncertain /
  by-parent). "Expected workload" does not.
- **#6 not verified.** The agent was instructed not to use the screen: the app
  was not launched and no screenshot was taken.

## What a human must check on screen (against design/screens/1c.png)

1. The four cards sit in one row at the default window width and wrap without
   clipping when narrowed (`LazyVGrid`, adaptive minimum 190 pt).
2. The hand-built table header aligns with its rows (fixed 90 pt CPU, 130 pt
   memory columns) and does not drift with long application names.
3. Disclosure triangles expand and collapse a family in place; child rows are
   visibly indented.
4. Chips stay legible and do not push the numeric columns off screen when a row
   carries two.
5. The Incidents sidebar badge appears only while an incident is open.
6. The toolbar shows the machine identity as a subtitle beside "Now", and the
   Mute alerts menu opens, mutes, and switches to the "Muted for N min --
   unmute" button.
7. The search field filters the contributor rows, and its empty state reads as
   "nothing matched", never as "nothing is running".
8. The incident banner needs a real sustained incident (85% of machine capacity
   for 3 minutes) to appear. Check the action row wraps, and that *Bring X
   forward* prints its outcome underneath rather than silently succeeding.
9. VoiceOver over the cards, the banner and the contributor rows. Every element
   is `.accessibilityElement(children: .combine)` with a composed label, but
   none of it has been heard -- blocked on TASK-15.
<!-- SECTION:NOTES:END -->
