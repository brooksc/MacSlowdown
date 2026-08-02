---
id: TASK-19
title: Aggregate disk I/O only -- per-process is blocked (FR-009)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:34'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rescoped by the Tier 0 probe: proc_pid_rusage is fully blocked under sandbox, so per-process I/O deltas are unobtainable. The spec permits omitting per-process detail in restricted builds. Aggregate throughput only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cumulative bytes never mislabeled as current rate
- [ ] #2 Absence of per-process attribution stated explicitly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DiskSignals.swift: DiskCounters (cumulative), DiskRates (per-second), and the conversion.

Sandbox feasibility confirmed rather than assumed. IOKit was not covered by the Tier 0 probe, so I verified it separately in a signed sandboxed .app launched via open: IOServiceGetMatchingServices returns KERN_SUCCESS, 3 IOBlockStorageDriver devices are readable, 1.70 TB read / 761 GB written. No entitlement beyond app-sandbox. Recorded in probe/FINDINGS.md.

- AC#1 Same discipline as FR-008: DiskCounters holds lifetime totals with no rate accessor, DiskRates is reachable only through an explicit delta over a measured interval. Tested that 10,000 bytes over 2s reads 5,000 B/s rather than the 900 MB lifetime figure, that an idle disk reports zero rather than its total, and that a counter going backwards (device removed, counter reset) reports zero rather than an underflowed spike.
- AC#2 The per-application limitation is stated in copy rather than silently omitted, per FR-009 as amended in v1.2: 'Disk activity is shown for the whole Mac. macOS does not report per-application disk activity to App Store apps, so it cannot be broken down by app.' Tested to be free of defensive language (denied, blocked, error, unfortunately, sorry).

counters() returns nil rather than zero when no driver can be read. Zero bytes would mean an idle disk; nil means an unavailable measurement, and conflating them is the FR-002 failure. Absent statistic keys are skipped rather than counted as zero for the same reason.
<!-- SECTION:NOTES:END -->
