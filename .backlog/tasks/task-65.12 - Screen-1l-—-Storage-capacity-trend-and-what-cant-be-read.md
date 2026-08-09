---
id: TASK-65.12
title: 'Screen 1l — Storage: capacity, trend, and what can''t be read'
status: In Progress
assignee: []
created_date: '2026-08-09 02:24'
updated_date: '2026-08-09 03:30'
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
- [x] #1 The startup volume shows capacity with a trend over a period long enough to reveal a slide, with the finding stated in words and not only as a curve
- [x] #2 The low-storage warning threshold is drawn on the trend, and any incident that opened against it is marked on the timeline (FR-041, FR-042)
- [x] #3 A volume whose usage recovered but whose trend continues is described as such rather than as resolved
- [x] #4 All mounted volumes appear, including ones that cannot be read, which state why rather than being omitted
- [x] #5 Volumes excluded from monitoring are shown as excluded with a route to include them
- [x] #6 Each figure keeps its provenance label, and purgeable space is never presented as space the user has
- [ ] #7 Verified on screen against design/screens/1l.png with more than one volume mounted
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch `agent-a27d7484a2f5c33bf` (commit 006a32c). AC#1-#6 met and unit-tested; **AC#7 deliberately unchecked** — not verified on screen (see below).

**There was no storage history at all, so it had to be built.** `MetricsHistory` is a 15-minute CPU ring at a 2-second cadence; nothing anywhere retained capacity. A 14-day trend had nothing behind it. New `Metrics/Sources/StorageHistory.swift` records available/total bytes per volume, coalesced to a quarter-hour interval, retained 14 days, persisted to `Application Support/MacSlowdown/storage-history.json` and restored on launch. Cost against FR-030: ~130 bytes a reading, ~175 KB for a full fortnight of one volume, rewritten four times an hour — under 1 MB/hour against the 10 MB/hour budget.

**No history was fabricated.** The series starts empty, so a fresh install has none. `StorageTrend` has `insufficientHistory` as a first-class case: with fewer than two readings or less than 12 hours of span, the screen states what it has ("Not enough history for a trend — 6 readings over 3 hours") and draws **no chart**. The period label is always the covered span actually recorded, never the retention window.

**The finding is stated in words**, dated from the peak inside the window rather than from the window's edge — a slide that began four days into a fortnight is a four-day slide. Movement under 0.5% of capacity (floor 512 MB) is called steady rather than a direction; volumes breathe by a gigabyte from caches alone.

**Warning line = the detector's own effective threshold.** `LowStorageDetector` requires *both* the proportional and the absolute safeguard, so the effective line is the lower of them: on a 1 TB disk that is 5 GB, not 100 GB. Drawing 10% would have shown a crossing where no incident opens. Tested that a volume exactly at the drawn line is exactly at the detection boundary for 32 GB / 128 GB / 1 TB disks. Low-storage incidents whose trigger falls inside the recorded window are marked on the curve, sitting on the nearest measured reading rather than at an invented value.

**Recovered is not fine.** `standingStatement` produces "It is back above the line now, but the 6-day slide has not stopped" only when the *recent* readings are still going down — measured over a tail of a quarter of the decline's span (minimum 1 hour), requiring at least two readings inside that tail. Two readings a week apart show a decline and say nothing about whether it continues, so that case returns false. "We cannot tell" is never presented as "yes". When the decline genuinely stopped, the copy says so instead.

**All mounted volumes, including unreadable ones.** `StorageSignals.snapshot` answers "what can we measure" and silently `continue`d past excluded removable volumes. New `Metrics/Sources/VolumeInventory.swift` answers the different question the screen asks — every mounted volume in exactly one of `measured` / `unreadable(reason:)` / `excluded(reason:)`, with no fourth case for "left out". A network volume that does not report capacity shows "Can't be read — network volumes are not reported to App Store apps"; a removable volume shows "Excluded from monitoring · Include", the Include button persisting to `UserDefaults`. `StorageSignals.swift` was not edited (another agent owns existing Metrics files).

**Files created:** `Metrics/Sources/StorageHistory.swift`, `Metrics/Sources/VolumeInventory.swift`, `MacSlowdown/Sources/StorageScreenModel.swift`, `MacSlowdown/Sources/StorageTrendChart.swift`, `Metrics/Tests/StorageHistoryTests.swift`, `Metrics/Tests/VolumeInventoryTests.swift`, `MacSlowdown/Tests/StoragePresentationTests.swift`. **Modified:** `MacSlowdown/Sources/StorageView.swift` only.

**Tests: 422 passing, 35 new.** The one failure in the full run, `EndToEndIncidentTests.realSlowdownProducesOneIncident`, is the known load-sensitive flake — it passes in isolation (23.9 s), as does `CPUWorkloadTests`, which also flaked on an earlier full run under concurrent-agent load.

**Not verified on screen (AC#7).** No screen use was permitted in this session. Needs checking against `design/screens/1l.png`, and it needs **more than one volume mounted** — this machine mounts only Macintosh HD (confirmed from the terminal: `FileManager.mountedVolumeURLs` with `.skipHiddenVolumes` returns exactly `/`), so the network, external and excluded-removable rows have never been rendered with real data. It also needs a machine that has been running the app long enough to have ≥12 hours of readings before the chart itself appears at all.

**Two findings for other owners, not fixed here:**
1. `MonitorStore` builds its `SystemObservation` without the `lowStorage` field, which defaults to false — so a low-storage incident can never actually open today, and the incident marker and callout on this screen have nothing to draw until that is wired. `MonitorStore.swift` is owned by another agent.
2. Capacity is recorded only while the Storage screen is open (a `.task` loop at 30 s). A one-line `StorageHistory.shared.record(...)` in the sampling loop would make the series continuous; it belongs in `MonitorStore`, which I could not edit.
3. The design's "Open incident" button was omitted rather than coupling this screen to incident navigation another agent is changing concurrently.
<!-- SECTION:NOTES:END -->
