---
id: TASK-80
title: >-
  Four measured-but-unshown disclosures: swap usage, per-app I/O unavailability,
  incident start provenance, storage-trend calculation label
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-09 20:28'
labels:
  - core
  - ui
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`). Four small items, grouped because each is one call away and each is a statement the spec asks the app to make.

**1. Swap usage is measured and never shown (FR-008).** The app calls `SwapSignals.pagingCounters` and `.rates`, so compression and paging are surfaced. `SwapSignals.swapUsage()` (`Metrics/Sources/SwapSignals.swift:53`) has no caller, so swap bytes in use — and `SwapUsage.encrypted` (`:9`) — are never displayed. FR-008 asks for swap *and* compression *and* paging; two of three arrive.

**2. Per-application disk I/O unavailability is never stated (FR-009).** `DiskSignals.perApplicationUnavailable` (`:92`) is the written statement that per-process I/O is blocked under the sandbox — a Tier 0 finding recorded in `probe/FINDINGS.md` and in CLAUDE.md. It is composed, tested and shown nowhere. FR-002's "unavailable data is labeled unavailable" applies: a user looking at aggregate disk figures has no way to learn why there is no per-app breakdown.

**3. Incident start provenance is never rendered (FR-038).** `Incident.startProvenance` (`Metrics/Sources/Incident.swift:172`) returns a `Conclusion` when `beganAtEstablishedFromRetainedHistory` is set — that is, when the start time was reconstructed from retained history rather than observed live. It has 3 test references and no caller. FR-038 requires every conclusion carry its evidence class; this is one the app computes and swallows.

**4. Storage trend is shown without its derived label (FR-038).** `StorageTrendAnalysis.describe` and `.standingStatement` are wired into the storage screen, but `StorageTrend.isCalculated` (`Metrics/Sources/StorageHistory.swift:200`) — whose doc comment says it exists "for the provenance label (FR-038)" — has no caller. The trend reads as a measurement when it is a calculation over measurements.

None of these needs new framework code. Check `design/` for where each belongs before placing it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Swap bytes in use, and whether swap is encrypted, appear somewhere a user can find them, sourced from SwapSignals.swapUsage()
- [x] #2 Where aggregate disk throughput is shown, DiskSignals.perApplicationUnavailable explains why there is no per-application breakdown
- [ ] #3 An incident whose start time was reconstructed from retained history displays Incident.startProvenance rather than presenting the time as observed
- [x] #4 Storage trend text carries its derived-calculation provenance label, driven by StorageTrend.isCalculated
- [x] #5 probe/seam-reachability.sh no longer reports swapUsage, perApplicationUnavailable, startProvenance or isCalculated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Done (branch `worktree-agent-a49250753dc5e51b8`, on top of main `fded4a3`)

All four wired. Tests: **970 passing, 1 failing** — `EndToEndIncidentTests.realSlowdownProducesOneIncident`, which also failed at my baseline on the same tree and is the documented load-sensitive test (another agent built throughout). Baseline before any change: 953 passing, same single failure. +17 is exactly the 17 tests added; **no test deleted**.

seam-reachability: **16 unexplained -> 5**. All five remaining belong to TASK-76-79. None of this task's four names is reported any more.

### 1. Swap usage (FR-008)
`MonitorStore.swapUsage`, read on the sampling loop, feeds `Presentation.swapInUse` into the Now screen's memory-pressure card beside the existing swap *activity* line. Design 1c pairs the two there.

Read on the loop, not in the view, for the reason `startupVolume` is: two views calling `SwapSignals.swapUsage()` independently would read at different moments and disagree. Assigned unconditionally each sweep, so a reading that stops being available reverts to nil rather than leaving a stale figure on screen. Nil renders "Swap usage unavailable", never zero — a swap file we could not read is not an empty one. Empty swap is a *different* statement ("No swap in use") and is tested separately. A test asserts the copy never contains "free up", "freed", "wasted", "reclaim", "clean" or "optimi" (FR-036, DR-08).

The card's detail lines moved out of the view `body` into `NowPresentation.memoryCardDetails(...)` so the composition is testable.

### 2. Per-application disk I/O (FR-009)
There were **two** hand-written paraphrases on the Now screen, not one: the Disk card's `help:` and a separate footnote, differently worded. Both now read `DiskSignals.perApplicationUnavailable`. A test asserts the footnote list contains that constant and that no second per-app paraphrase survives. `NowPresentationTests.footnotes` used to assert a copied phrase and now asserts the constant — which is how the drift became possible.

Structure unchanged: the footnote is the always-visible (and VoiceOver-reachable) statement; the card's tooltip is the same sentence on hover.

### 3. Incident start provenance (FR-038)
Carried on `IncidentTimeline` (from `IncidentTimeline.build`) and rendered by the existing `ConclusionRow` under the timeline band — beside the window edge it explains. `ConclusionRow` already shows the evidence class and folds it into its accessibility label, so no new accessibility surface was invented. On the timeline rather than read from the incident in the view so the decision is a value a test asserts. Both branches tested.

### 4. Storage trend provenance (FR-038)
`StoragePresentation.trendProvenance(_:)` maps `StorageTrend.isCalculated` to "Calculated"/"Measured" — the vocabulary the capacity legend above already uses and the screen footer defines. Shown under the trend statement and folded into that element's accessibility label and the chart's accessibility summary. `.insufficientHistory` is "Measured" deliberately: it reports a count of readings and a span, which is not a derivation.

### Files changed
`MacSlowdown/Sources/`: `MainWindowView`, `NowPresentation`, `Presentation`, `IncidentDetailView`, `IncidentEvidence`, `StorageView`, `StorageScreenModel`. `MacSlowdown/Tests/`: `MeasuredButUnshownTests.swift` (new), `NowPresentationTests.swift`. Plus `probe/SEAM-AUDIT.md`.

### Criteria not met

**#3 left unchecked.** The wiring and both branches are tested at `IncidentTimeline.build`, but nobody has seen the row render, and a passing unit test is not a UI criterion. It needs an incident whose `beganAtEstablishedFromRetainedHistory` is true, which happens only when a threshold change re-decides an already-present condition (TASK-69).

**The check that would settle it:** with CPU sustained above some level, lower the CPU threshold in Settings so an incident opens immediately; open that incident and confirm a `ConclusionRow` reading "Dated from readings MacSlowdown had already kept..." sits directly under the timeline band, with its evidence chip reading Measured.

Also not verified on screen, same reason (instructed not to use the display): that the memory card's third detail line fits without truncating at the 190 pt adaptive-grid minimum, and that the storage trend's new two-line provenance stack does not collide with the trend statement at narrow window widths. Everything else asserted here is a pure function.

### `MonitorStore.swift` diff still to apply

I was not permitted to edit `MonitorStore.swift`. The change below was applied locally to verify the build and the 970-test run, then reverted before committing. **The branch as committed does not compile until this is applied** — `MainWindowView` references `store.swapUsage`. Verbatim, against `fded4a3`:

```diff
--- a/MacSlowdown/Sources/MonitorStore.swift
+++ b/MacSlowdown/Sources/MonitorStore.swift
@@ -83,6 +83,18 @@ final class MonitorStore {
     private(set) var thermalState: ThermalState = .nominal
     private(set) var power: PowerContext = PowerSignals.current()
     private(set) var pagingRates: PagingRates = .zero
+    /// Swap bytes in use, as the sampling loop last read them (FR-008).
+    ///
+    /// Read here rather than by a view for the same reason `startupVolume` is:
+    /// every surface has to quote the same figure. Two views calling
+    /// `SwapSignals.swapUsage()` independently would read at different moments and
+    /// could disagree about how much swap exists, which a user would reasonably
+    /// read as one of them being wrong.
+    ///
+    /// Nil until the first sample, and nil again if `sysctl vm.swapusage` stops
+    /// answering. Never defaulted to a zeroed `SwapUsage`: a swap file we could not
+    /// read is not an empty one (FR-002).
+    private(set) var swapUsage: SwapUsage?
     /// Aggregate disk throughput, or nil when there is no rate to report (FR-009).
     ///
     /// Optional rather than `.zero` deliberately. A driver that will not report its
@@ -579,6 +591,12 @@ final class MonitorStore {
 
             // Rates only ever from deltas over the measured interval.
             let seconds = elapsed.totalSeconds
+            // Swap usage is a level, not a rate: it is whatever the current reading
+            // says, and it does not need two samples the way paging does. Assigned
+            // unconditionally so a reading that stops being available reverts to
+            // nil rather than leaving the last good figure on screen as if it were
+            // current (FR-002, FR-008).
+            swapUsage = SwapSignals.swapUsage()
             if let counters = SwapSignals.pagingCounters() {
                 if let previous = previousPaging,
                    let rates = SwapSignals.rates(from: previous, to: counters, seconds: seconds) {
```
<!-- SECTION:NOTES:END -->
