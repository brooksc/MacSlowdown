---
id: TASK-17
title: Memory pressure monitoring (FR-007)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:22'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Use the official memory-pressure signal, not percent-RAM-used. Verify DISPATCH_SOURCE_TYPE_MEMORYPRESSURE fires sandboxed within the 2s requirement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pressure transitions captured within 2s
- [x] #2 UI never describes cached memory as inherently wasted
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MemorySignals.swift: MemoryPressureLevel, MemoryStatistics, and MemoryPressureMonitor.

- AC#1 Transitions are captured by a DispatchSource memory-pressure source rather than by polling, so a change is observed when it happens instead of at the next sample -- the 2s cadence alone could not guarantee the 2s requirement. Each transition is timestamped on receipt; a test asserts the recorded timestamp lands within 2s. The initial level comes from sysctl kern.memorystatus_vm_pressure_level, because a dispatch source only reports changes and would otherwise leave us blind until the first one.
- AC#2 Verified by test, not by inspection. Every level's explanation is asserted to contain none of: wasted, waste, free up, freed, reclaim memory, clean, optimi, hog, leak. The normal-level copy goes further and states positively that memory shown as in use includes cache macOS will reuse, "which is normal and not a problem" -- the misreading FR-007 exists to prevent.

Deliberately not derived from percent-RAM-used. A Mac with 2% free memory can be perfectly healthy because macOS fills unused RAM with reclaimable cache; only the kernel knows what is reclaimable, so the kernel's own signal is the only meaningful one.

Statistics are reported in bytes rather than pages, with a test asserting values are whole multiples of the page size and that the categories account for a sane fraction of physical memory. Inactive memory is documented in the type as reclaimable rather than wasted, since that is the number naive monitors misreport.

Repeated notifications at the same level are not transitions -- tested, since the dispatch source can fire without a level change and would otherwise inflate the history. History is bounded.

Unrelated fix made along the way: the CPU workload tests failed during this run because the machine was saturated by an unrelated Xcode build (load 14.5, two swift-frontend at 100%), so the spinners could not get a full core. That was environmental, but it exposed a real fragility -- the tests asserted an absolute ~100% reading, which only holds when a core is free. They now assert agreement with `ps` for the same pid, which is the actual correctness property and holds under any load, with a floor of 20% that still catches a dropped mach-tick conversion (which reads ~2.4%).
<!-- SECTION:NOTES:END -->
