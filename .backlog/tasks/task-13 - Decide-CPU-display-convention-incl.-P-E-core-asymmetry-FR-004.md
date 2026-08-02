---
id: TASK-13
title: Decide CPU display convention incl. P/E core asymmetry (FR-004)
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
labels:
  - m1-core-monitor
  - decision
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
