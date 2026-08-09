---
id: TASK-65.4
title: 'Screen 1d — Apps &amp; processes: family grouping expanded, with an inspector'
status: In Progress
assignee: []
created_date: '2026-08-09 02:22'
updated_date: '2026-08-09 03:31'
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
- [x] #2 Expanding a family shows its member processes with PID and start time, and marks any member grouped by heuristic rather than by a strong signal
- [x] #3 A selected family opens an inspector showing recent history, family totals, growth, relaunch count, and explicitly labels disk activity as unavailable
- [x] #4 The inspector offers only non-destructive actions and states plainly that quitting and pausing are not available (FR-037)
- [ ] #5 The inspector shows how the grouping was decided and allows the user to correct it (FR-039)
- [x] #6 A footer states how many processes belong to an app and how many are not measurable, and when the data was last updated
- [ ] #7 Verified on screen against design/screens/1d.png
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Implemented (worktree `agent-ae83f187193f08460`, commit `caa0425`).**

**The inspector** (`MacSlowdown/Sources/FamilyInspectorView.swift`, new). Right-hand pane, 340 pt, shown for the selected application or the System processes group. Icon, name, `Version X · /Applications` read from the bundle's own `Info.plist` once per selection (never per render — it is filesystem work). A chart with CPU / Memory tabs over the observed window, a figures grid, the two standing caveats, safe actions, and grouping provenance.

**Does the data exist?** Checked before rendering anything:
- *Recent per-family history*: **did not exist**. `MetricsHistory` retains the machine aggregate plus the five leading contributors (FR-005), so a per-family series built from it would be full of holes for any app that drops out of the top five. Added `FamilyHistory` (new, app layer), recording from what the store has already measured. **Bounded to the 40 busiest families plus the selection**: ~800 families × 450 samples is tens of megabytes against FR-030's 100 MB whole-app budget. A family with no history yet says so instead of drawing a flat line at zero.
- *Growth over 2 hours*: **not available as the design states it**. We can only report the window the app has been open. Rendered as "Growth, last N min" against the actually-observed span, withheld below 2 minutes ("Not enough history yet"). A fall is reported as a fall. Nothing calls it a leak.
- *Relaunches today*: **not tracked**. `LifecycleTracker` exists in `Metrics` but nothing wires it into `MonitorStore`, which another agent owns this session. Rather than invent a zero, the inspector counts *replacements observed while watching* — a member identity gone and another arrived under the same command, identity being `(pid, start time)` so a recycled PID reads as a replacement — and says "Not watched long enough" until the window is real. **If `LifecycleTracker` is later wired into the store, replace this with it.**
- *Disk activity*: correctly "Not available", with the reason. `proc_pid_rusage` is self-only under the sandbox; there is no code path that could approximate it from the aggregate disk rates.
- *Memory*: resident size, with the Activity Monitor footprint caveat, in the inspector, the footer and the copied diagnostics.

**Safe actions** come from `SafetyPolicy().availableActions(for:)` and run through the existing `ActionPerformer` (this is its first UI consumer). A protected process is therefore offered only Open Activity Monitor and Copy diagnostics, with the category explanation. Results are reported from the `ActionResult`, never assumed. `markExpected` is handled by the view against a `PolicyStore` (the app had no instance; one was added as `InspectorPolicies`) because `ActionPerformer` deliberately refuses it. FR-037 is stated as a fact about the product — "quitting and pausing are not part of MacSlowdown" — not as a disabled control, because there is no such control anywhere in the build to disable.

**Also delivered**: Name / CPU / Memory / PID / Started columns, with sort keys that keep "no PID" and "no start time" out of the real values; member rows carrying their own PID and start time; a **"Grouped by guess"** chip (a word, not a colour) on members whose signature contradicts their path; `GroupingProvenance` counting members by kind of evidence and stating each in a sentence; and an `InventoryCensus` footer — "20 apps · 63 of 412 processes belong to an app · 234 not measurable" — plus freshness and the explanation of why the numbers do not add up to the visible list.

**Deliberately not done**
- **All-processes list — TASK-65.13.** The segmented control is present as a shell with real counts on both segments; selecting *All processes* says the list is not built yet and states how many processes and how many unmeasurable ones it will contain. **AC #1 left unchecked.**
- **Grouping correction ("Split out…" / "Merge into…") — TASK-35.** Provenance is rendered and the interface says correcting by hand is not available yet. **AC #5 left unchecked.**
- **Collapsed helper tail ("19 more helpers below 1%") and the "Other applications" rollup.** Both hide measured processes behind a threshold, and `Table`'s row model offers no way to reveal them short of overloading selection. Judged not worth the honesty cost without a design conversation.

**AC #7 (verified on screen) is NOT met** — this agent was instructed not to use the screen, so nothing here has been seen running. What needs looking at: the inspector's layout at 340 pt; whether the `Charts` line renders legibly at 70 pt with a hidden X axis; the segmented control's placement against the search field; whether six columns plus the inspector are too wide at the default 900 pt window; and the "Grouped by guess" chip's contrast.

**Tests**: `MacSlowdown/Tests/InventoryInspectorTests.swift` (new) — 31 tests, 6 suites, all passing. Full run **419 passing** (baseline 388). One failure in the full run, `MetricsTests/EndToEndIncidentTests.realSlowdownProducesOneIncident`; re-ran in isolation and it **passed** — the known load-sensitive flake, not a regression.

**Changed**: `MacSlowdown/Sources/InventoryRow.swift`, `MacSlowdown/Sources/ProcessInventoryView.swift`.
**Created**: `MacSlowdown/Sources/FamilyInspectorView.swift`, `MacSlowdown/Sources/FamilyHistory.swift`, `MacSlowdown/Sources/InventoryCensus.swift`, `MacSlowdown/Tests/InventoryInspectorTests.swift`.
<!-- SECTION:NOTES:END -->
