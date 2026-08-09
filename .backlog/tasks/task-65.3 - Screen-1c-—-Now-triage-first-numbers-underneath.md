---
id: TASK-65.3
title: 'Screen 1c — Now: triage first, numbers underneath'
status: Done
assignee: []
created_date: '2026-08-09 02:22'
updated_date: '2026-08-09 06:33'
labels:
  - ui
milestone: m-1
dependencies: []
modified_files:
  - MacSlowdown/Sources/MainWindowView.swift
  - MacSlowdown/Sources/NowPresentation.swift
  - MacSlowdown/Sources/HistorySparkline.swift
  - MacSlowdown/Sources/SparklinePresentation.swift
  - MacSlowdown/Tests/NowPresentationTests.swift
  - MacSlowdown/Tests/SparklineTests.swift
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

## History added, and the part that cannot honestly be added (commit 6adc296, worktree agent-a775f508b2ba47358)

The sparkline omission recorded above is now partly closed and partly settled as *not possible from what we retain*. TASK-66 landed `MonitorStore.retainedSamples`, so the FR-005 series is reachable; nothing was accumulated in the view.

**New files.** `MacSlowdown/Sources/SparklinePresentation.swift` (rules, pure) and `MacSlowdown/Sources/HistorySparkline.swift` (the `Canvas` view and `HistorySparklineBlock`). `MacSlowdown/Tests/SparklineTests.swift` — 26 tests. `MainWindowView.swift` and `NowPresentation.swift` modified.

**Drawn.**

- *CPU card* — total CPU over the retained window, from `SparklinePresentation.totalBusySeries(store.retainedSamples)`, captioned with the span actually retained ("Last 3 min — all we have retained, of a 15 min window") rather than the window the design names.
- *Contributor table, new "Retained history" column* — a curve on the **System processes** row only. That row's figure *is* `unattributedPercentOfOneCore` (`InventoryRow` builds it from exactly that), and every retained sample records it, so its coverage equals the machine total's. This is the row the criterion calls "unattributed system activity", and it is the one contributor row with an honest series.

**Rules the chart obeys, each tested.** Only measured samples; the caption states the retained span, never the nominal window; `runs(_:gapThreshold:)` breaks the stroke where consecutive samples are more than 4× cadence apart (floor 8 s) rather than interpolating across minutes nobody observed; and below five readings the cell says "Too few readings" (full sentence in help and VoiceOver) rather than drawing a flat line, which would read as "nothing happened" when the truth is "we have not watched long enough".

**Accessibility (FR-034).** `SparklinePresentation.accessibilitySummary` states span, reading count, lowest, highest and most recent — every figure one that was plotted — plus "with a break where no readings were taken" when the series is split. It is folded explicitly into `MetricCard`'s and `ContributorRow`'s own `accessibilityLabel`, because an explicit label overrides `children: .combine` and would otherwise have silently dropped the chart.

### Not drawn, and why — this is the finding

*Per-application history is not retained, so no application row gets a curve.* `HistorySample.topContributors` holds at most five entries, keyed by `(pid, start time)` and recorded per **process**, not per family. Three separate holes follow, any one of which would be fatal:

1. A family outside the leading few is simply absent from most samples.
2. A family made of many small processes can rank high as a family while no single member ever enters the top five — so it would have a family-level figure now and no history at all.
3. A member that has since exited cannot be matched back to the family it belonged to, so its past samples would vanish from the sum and the curve would dip for a reason that never happened.

Drawing that with the gaps stroked out would still imply we watched the app throughout and it did nothing in between. So those cells read **"not retained"**, with the reason in the tooltip and in the VoiceOver label, and `NowPresentation.historyColumnNote` is a footnote saying it in the open. The wording is about our records, never about the application — a test asserts it.

*`FamilyHistory` was considered and rejected as the source.* It exists and does keep per-family series, but it is `@State` on `ProcessInventoryView`: it accumulates only while Apps & Processes is open. Reading it from Now would mean a second instance accumulating only while Now is open — the exact "different curve from the one we retain" this task refused the first time round.

*Disk card.* Design 1c charts disk throughput. `MetricsHistory` retains CPU and nothing else, so the card carries `NowPresentation.diskHistoryNote` — "No history is retained for disk throughput, so there is no trend here — only the rate over the last interval" — instead of a curve assembled while the screen happened to be open.

### Criteria after this pass

- **#3 still unchecked.** The table now has per-family CPU, resident memory, the unattributed system row **and** a history column — but the criterion's "short history" *per family* is not deliverable from what FR-005 retains, for the three reasons above. What ships is history where it is honest and a stated absence where it is not. Closing this criterion properly needs a decision about whether `MetricsHistory` should retain a bounded per-family series (~40 families × ~450 samples), which is a spec-level question, not a view change.
- **#4** unchanged, still unchecked.
- **#6 not verified** — this session was also barred from the screen.

### Tests

Full suite **696 passing, 0 failing** (`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .build`), against a 670 baseline — all 26 additions accounted for. One earlier run of the pair failed `EndToEndIncidentTests.realSlowdownProducesOneIncident`, the documented load-synthesising flake with several agents building concurrently, and passed on re-run.

### What a person must check on screen (added to the list above)

1. The CPU card with a chart inside it does not break the four-across `LazyVGrid` at the default width; the other three cards are shorter and the row may now look ragged.
2. The new 110 pt "Retained history" column does not push the name column into truncation at the default window width, and the header still aligns with the rows.
3. A 20 pt sparkline inside a 6 pt-padded table row is legible at all, and in dark mode.
4. "Not retained" reads as a statement about our records and not as "this app did nothing" — the wording most likely to be misread, and the one thing a test cannot settle.
5. The first minute after launch: the CPU card should show the too-few-readings sentence, and the card should not jump in height when the curve replaces it.
6. VoiceOver over the CPU card and the System processes row — the chart summary should be spoken as part of each.
<!-- SECTION:NOTES:END -->
