---
id: TASK-18
title: 'Swap, compression and paging trends (FR-008)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:30'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rates never derive from cumulative totals without delta calculation
- [ ] #2 Counter reset and wrap handled
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SwapSignals.swift: SwapUsage, PagingCounters (cumulative), PagingRates (per-second), and the conversion between them.

- AC#1 The type system enforces the requirement rather than relying on discipline. PagingCounters holds only lifetime totals and has no rate accessor; PagingRates is a separate type reachable only through SwapSignals.rates(from:to:seconds:). Tests assert a rate is the delta over the interval and not the total -- 100 page-ins over 10s reads 10/s, not the 1,000,000 lifetime figure -- and that an unchanged counter yields zero rather than its total. A non-positive interval returns nil rather than dividing.
- AC#2 A counter going backwards means a reboot or a wrap. Neither is a measurement, so that field reports zero rather than the unsigned underflow, which would show ~9.2e18 presented as fact. Tested with a simulated reboot, and separately with one field resetting while others advance, to confirm the isolation is per-field rather than discarding the whole reading.

Swap existing is deliberately not treated as a problem: macOS swaps opportunistically and a non-zero figure on a healthy Mac is normal. What matters for an incident is whether it is growing, which is why isSwapping keys on the swap-in/swap-out RATES rather than on swap being non-empty. Tested that page-ins alone do not count as swapping.

Two issues surfaced during this task, neither a product regression:
1. xsu_encrypted is boolean_t (Int32), not Bool -- caught at compile time.
2. The FR-030 CPU budget test failed. Investigated rather than assumed: OverheadHarness reads our own process CPU via proc_pidinfo(getpid()), and inside a parallel test run that process is also executing every other suite, including the spinner tests. The in-process reading therefore includes work that is not ours. Standalone measurement on the same build was 0.493% of one core, comfortably inside budget. The test now asserts memory, disk, sweeps and a loose CPU bound that still catches a gross regression, with the authoritative standalone figures recorded in the suite comment. Silently loosening it without explaining why would have been the wrong fix.
<!-- SECTION:NOTES:END -->
