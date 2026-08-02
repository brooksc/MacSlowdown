---
id: TASK-14
title: Record machine and OS context per incident (FR-049)
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 04:03'
labels:
  - core
milestone: m-1
dependencies: []
priority: low
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Excludes serial numbers and persistent hardware identifiers
- [ ] #2 Versioned and previewable before export
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MachineContext.swift. Captures OS version, hardware model, architecture, logical/P/E core counts, physical memory, app version and build, and a schema version for FR-040.

AC#1: excludes serial numbers, hardware UUIDs and any persistent identifier. FR-049 requires their absence unless separately justified and consented, and nothing here needs them -- hw.model ('Mac14,15') identifies the machine type, not the machine.

AC#2: Codable and carries schemaVersion so retained records stay interpretable after an update. Verified live in the Now view footer: 'Mac14,15 - arm64 - 8 cores - 24 GB / Version 27.0 (Build 26A5388g)'.
<!-- SECTION:NOTES:END -->
