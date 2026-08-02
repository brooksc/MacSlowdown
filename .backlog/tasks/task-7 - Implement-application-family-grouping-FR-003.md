---
id: TASK-7
title: Implement application-family grouping (FR-003)
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:07'
labels:
  - m1-core-monitor
  - core
dependencies:
  - TASK-3
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Depends on the identity spike. Group helper processes into user-meaningful application families while preserving individual PID records.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Known browser/helper fixtures aggregate correctly
- [ ] #2 Uncertain associations are labeled and reversible
- [ ] #3 Individual PID records preserved beneath the aggregate
<!-- AC:END -->
