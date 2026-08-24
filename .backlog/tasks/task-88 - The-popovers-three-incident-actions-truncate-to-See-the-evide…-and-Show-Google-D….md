---
id: TASK-88
title: >-
  The popover's three incident actions truncate to "See the evide…" and "Show
  Google D…"
status: To Do
assignee: []
created_date: '2026-08-24 04:03'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on screen by the product owner, 2026-08-23, who noted it did not happen before — which is consistent with the cause.

`MenuBarContentView.incidentActions` (`MacSlowdown/Sources/MenuBarContentView.swift:480`) puts three controls in one `HStack` inside a fixed-width popover: "See the evidence", the Show-target button, and the Mute menu. The Mute menu carries `.fixedSize()`, so it is guaranteed its intrinsic width and the other two absorb the entire shortfall. Observed: "See the evide…" and "Show Google D…".

TASK-65.21 added the third action (the design 1b action row) and its criteria were checked against tests, not against a running popover. This is the regression that introduced.

Design 1b is the reference for what the row should look like. Options include wrapping to two rows, shortening the primary to "See evidence", letting only the Show button truncate, or giving the Show button a `truncationMode` that keeps the application name legible — the name is the informative half of "Show Google Drive", so truncating it at the end is the worst of the available choices (FR-002's rule against showing a fragment as if it were the name is the same family of concern).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 At the popover's real width, no action button label is truncated in the default case
- [ ] #2 Where an application name is long enough that something must give, the application name remains identifiable and the fixed vocabulary gives way first
- [ ] #3 The row is checked against design 1b
- [ ] #4 Verified on screen at the popover's real width with a long application name and a short one
<!-- AC:END -->
