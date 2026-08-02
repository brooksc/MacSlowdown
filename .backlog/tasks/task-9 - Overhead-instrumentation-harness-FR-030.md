---
id: TASK-9
title: Overhead instrumentation harness (FR-030)
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:19'
labels:
  - infra
milestone: m-1
dependencies:
  - TASK-4
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FR-030 targets are tests, not aspirations: idle CPU median <=1% of one core, resident memory <=100MB, disk writes <=10MB/hour absent incidents. Reuse the probe measurement code as the permanent harness.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Automated check fails the build when the CPU budget regresses
- [ ] #2 Measured on reference hardware with documented conditions
- [ ] #3 Resident memory stays under 100MB target
- [ ] #4 Disk writes stay under 10MB/hour absent incidents
<!-- AC:END -->
