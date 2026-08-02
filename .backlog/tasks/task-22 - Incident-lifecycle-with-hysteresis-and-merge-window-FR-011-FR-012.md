---
id: TASK-22
title: 'Incident lifecycle with hysteresis and merge window (FR-011, FR-012)'
status: To Do
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 01:07'
labels:
  - core
milestone: m-2
dependencies:
  - TASK-10
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Converts continuous metrics into episodes. The heart of the product.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Repeated samples do not create duplicate incidents
- [ ] #2 Incident closes only after recovery hysteresis
- [ ] #3 At least 2 min pre-trigger and 1 min post-recovery evidence retained
<!-- AC:END -->
