---
id: TASK-80
title: >-
  Four measured-but-unshown disclosures: swap usage, per-app I/O unavailability,
  incident start provenance, storage-trend calculation label
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-09 19:59'
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
- [ ] #1 Swap bytes in use, and whether swap is encrypted, appear somewhere a user can find them, sourced from SwapSignals.swapUsage()
- [ ] #2 Where aggregate disk throughput is shown, DiskSignals.perApplicationUnavailable explains why there is no per-application breakdown
- [ ] #3 An incident whose start time was reconstructed from retained history displays Incident.startProvenance rather than presenting the time as observed
- [ ] #4 Storage trend text carries its derived-calculation provenance label, driven by StorageTrend.isCalculated
- [ ] #5 probe/seam-reachability.sh no longer reports swapUsage, perApplicationUnavailable, startProvenance or isCalculated
<!-- AC:END -->
