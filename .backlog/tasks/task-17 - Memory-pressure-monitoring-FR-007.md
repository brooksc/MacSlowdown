---
id: TASK-17
title: Memory pressure monitoring (FR-007)
status: To Do
assignee: []
created_date: '2026-08-02 01:07'
labels:
  - m2-incident-diagnosis
  - core
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Use the official memory-pressure signal, not percent-RAM-used. Verify DISPATCH_SOURCE_TYPE_MEMORYPRESSURE fires sandboxed within the 2s requirement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pressure transitions captured within 2s
- [ ] #2 UI never describes cached memory as inherently wasted
<!-- AC:END -->
