---
id: TASK-13
title: Decide CPU display convention incl. P/E core asymmetry (FR-004)
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 04:03'
labels:
  - decision
milestone: m-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Open question in the spec. This machine is 4P+4E via hw.perflevel0/1.logicalcpu. Decide core-relative vs machine-relative and whether host_processor_info indices map to perflevels. Hard to change later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Convention documented and applied consistently
- [ ] #2 Synthetic two-core workload represented accurately
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DECISION: percentage of one core is the primary unit; machine-relative is shown alongside as context, not instead.

Rationale: it matches the kernel counter we read and what top, ps and Activity Monitor report, so a user cross-checking finds the same number; it makes a runaway process legible (412% says four cores' worth, which a machine-relative 41% hides); and FR-004's own acceptance criterion is a two-core workload represented accurately, which core-relative does directly. The known cost is that values above 100% confuse people who have not seen the convention, which is why CPUPresentation.convention() accompanies the figures wherever they appear rather than living in a comment.

P/E asymmetry: deliberately NOT normalised. host_processor_info gives per-core tick counters but nothing mapping an index to a performance level, and mach tick accounting does not scale by core capability. Weighting would mean inventing a factor we cannot measure, which FR-036 and FR-038 forbid. So a percentage is a share of one core's TIME, not of its speed, and topologyNote() says exactly that on asymmetric hardware (verified live: 'This Mac has 4 performance and 4 efficiency cores...').

AC#2 is covered by the CPUWorkloadTests dual-spinner test: two single-core workloads each read ~100% and combine above 160%.
<!-- SECTION:NOTES:END -->
