---
id: TASK-5
title: 'Build metrics sampler: sysctl enumeration + PROC_PIDTASKALLINFO'
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:05'
labels:
  - core
milestone: m-1
dependencies:
  - TASK-4
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the validated probe approach into the app. Enumerate via sysctl KERN_PROC_ALL; per-process metrics via PROC_PIDTASKALLINFO (one syscall instead of two).

MUST scale CPU times by mach_timebase_info -- they are mach ticks, not nanoseconds, and omitting this under-reports CPU by ~42x on Apple Silicon.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Synthetic single- and dual-core workloads read accurately vs ps (FR-004 acceptance criteria)
- [x] #2 CPU derived from deltas of monotonic counters, never cumulative totals
- [x] #3 Denied processes labeled unavailable, not omitted silently (FR-002)
- [x] #4 Sweep cost stays within FR-030 budget at 2s cadence
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Sampler implemented in the Metrics module: ProcessRecord.swift (types), ProcessSampler.swift (enumeration + metrics), CPUUsage.swift (rate calculation).

Verified by test, all 19 passing:
- AC#1 A synthetic single-core spinner reads ~100% of one core and is cross-checked against `ps -o %cpu` for the same pid, tolerance 25 points. Two spinners each read ~one core and combine above 160%. This is the test that fails loudly if the mach-tick conversion is ever dropped -- without it the reading is ~2.4% instead of ~100%.
- AC#2 CPU comes only from the difference between two cumulative counters over a measured interval. A snapshot compared with itself returns empty rather than reporting lifetime totals. Nothing may exceed the machine's total capacity.
- AC#3 Denied processes are present and labeled. MetricsResult is an explicit enum (measured / notPermitted / exited / failed(errno)) rather than an optional, so EPERM is distinguishable from "process vanished" and neither is silently treated as zero. Test asserts denied processes appear with names and that measurable + notMeasurable equals the total.
- AC#4 Median sweep is well inside the FR-030 budget: 10 snapshots complete in ~26ms, about 2.6ms each, against a 20ms budget (1% of one core at 2s cadence). The test uses the median, matching how FR-030 states the requirement.

Deviation from the task title, deliberate: uses PROC_PIDTASKINFO, not PROC_PIDTASKALLINFO. The sysctl enumeration already yields everything TASKALLINFO's bsdinfo half provides -- name, uid, ppid, start time -- so requesting it again would copy an extra 136 bytes per process for no benefit. Same syscall count, strictly less work. CLAUDE.md's note preferring TASKALLINFO assumed we would otherwise need two calls; that assumption does not hold once sysctl supplies identity.

Design notes:
- Identity is (pid, p_starttime in microseconds). Start time comes free from kinfo_proc, so no extra syscall is needed to make PID reuse safe.
- sysctl sizing races the process table growing; the enumerator retries on ENOMEM with slack rather than truncating.
- Rates use ContinuousClock, never wall clock, which can jump.
- Processes denied in either snapshot are excluded from attributed usage rather than counted as zero -- their load is real but unattributable, which is what TASK-8's bucket is for.

Sandboxed operation is not re-verified here: MetricsTests runs unsandboxed, and probe/FINDINGS.md already establishes that these exact calls work under App Sandbox (720/1058 measurable, identical to unsandboxed). End-to-end verification inside the sandboxed app comes with the inventory view in TASK-12.
<!-- SECTION:NOTES:END -->
