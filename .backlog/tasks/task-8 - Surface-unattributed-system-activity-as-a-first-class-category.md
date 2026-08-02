---
id: TASK-8
title: Surface unattributed system activity as a first-class category
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:23'
labels:
  - core
milestone: m-1
dependencies:
  - TASK-5
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Direct consequence of the Tier 0 finding: ~40 percentage points of busy CPU cannot be attributed to any visible process, because other-uid processes (WindowServer, mds_stores, backupd, coreaudiod, launchd) are denied.

Contributor lists must never silently fail to sum. Show the remainder explicitly as unattributed system activity. This is what FR-038 evidence classification and FR-013 confidence labeling exist for.

Note users may compare against Activity Monitor, which sees everything via a privileged helper (sysmond).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Aggregate CPU minus attributed CPU is displayed, never hidden
- [x] #2 Copy explains the limitation without overstating causation (FR-013, FR-036)
- [x] #3 Classified as measured fact vs derived per FR-038
- [x] #4 Unattributed bucket lists which protected processes were running in the window, as measured fact, distinct from the unapportionable CPU total
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Design review finding: we can NAME every running process even when we cannot MEASURE it. sysctl KERN_PROC_ALL returns p_comm, uid, ppid and start time for all 1063 processes regardless of ownership; proc_pidpath resolves 1042/1063 and code signing 212/338 other-uid. Only CPU and memory are denied.

So the unattributed bucket should not be an anonymous blob. We can state as MEASURED FACT which protected processes were running during an incident window, and when they started and exited (FR-045). 'Time Machine (backupd) was running for the whole window' is a measured observation even though its CPU share is not.

This turns the hard case from 'we cannot tell you anything' into 'here is exactly what was running, and here is why we cannot apportion it' -- a materially better product for the ~40% of incidents that land here.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
HostCPU.swift (aggregate counters) and Attribution.swift (the breakdown). 48 assertions passing, verified stable across 5 consecutive runs.

- AC#1 CPUAttribution always carries totalBusy, attributed and unattributed, and a test asserts attributed + unattributed == total to within 0.001 points -- including under load, not only on a quiet machine. Unattributed is clamped at zero: sampling the host and the process table at slightly different instants can make the attributed sum marginally exceed the host total, and a negative remainder is a measurement artefact, not a finding.
- AC#2 `explanation` states the remainder is "the measured difference between total CPU and everything we are permitted to read, not an estimate", and that we can see which processes ran "but not how much CPU they used". A test asserts the copy contains no causal or judgemental language: caused, wasted, leak, optimi, clean up, fix.
- AC#3 Evidence enum (measured / calculated). Total and attributed are .measured (kernel counters); the remainder is .calculated. Test asserts each figure's class, so a derived remainder can never be presented as though read from a counter.
- AC#4 protectedProcesses names every denied process with its start time as a Date, so it can be correlated with an incident window. Test asserts the list is non-empty and intersects the canonical set (launchd, WindowServer, mds_stores, coreaudiod, hidd). This is the design-review insight made concrete: we can say what was running even when we cannot say what it used.

Test flakiness fixed properly rather than by loosening tolerances. Two causes:
1. Spinner-based tests in separate suites ran in parallel and competed for cores, so neither spinner got a full core. All workload-sensitive tests now live in one @Suite(.serialized); the trait is load-bearing, not tidiness.
2. "A real workload raises the attributed share" compared an idle baseline against a busy one, but the baseline drifted because other suites run in parallel. Replaced with a direct assertion: the spinner must appear among attributed contributors at >80% of one core and be included in the attributed total. That tests the actual property -- measurable work lands in the attributed column, not the remainder -- rather than a noisy aggregate delta.
<!-- SECTION:NOTES:END -->
