---
id: TASK-10
title: Bounded rolling history ring buffer (FR-005)
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
labels:
  - core
milestone: m-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Default history covers at least 15 minutes. Storage format is open, but must meet the FR-030 disk budget -- validate write amplification before committing to SwiftData/CoreData.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Default history at least 15 minutes
- [ ] #2 Memory and disk budgets met
- [ ] #3 Restart persistence configurable
<!-- AC:END -->
