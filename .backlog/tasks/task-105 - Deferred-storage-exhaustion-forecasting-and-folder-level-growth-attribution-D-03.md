---
id: TASK-105
title: >-
  Deferred: storage-exhaustion forecasting and folder-level growth attribution
  (D-03)
status: Parked
assignee: []
created_date: '2026-08-31 20:43'
labels:
  - parked
dependencies: []
priority: low
type: feature
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product owner, 2026-08-31, on D-03: **deferred**, with a backlog entry so it is not silently dropped.

The question was whether FR-041/FR-042 should extend to forecasting when a volume will fill, and to attributing growth to particular folders. Neither is built and neither is planned.

Two things a future reader should know before picking this up:

- **Folder-level attribution needs file-system access this product does not request.** Reading sizes across a user's home directory means either broad file access or user-selected scopes, which is a privacy posture change, not a feature addition. A-05 and FR-029 are the constraints.
- **Forecasting is a prediction**, and this product's whole discipline is to state measurements and label derivations. "You will run out of space on Thursday" is a claim of a kind nothing else here makes. If it is built, FR-038's evidence classification has to cover it explicitly — most likely as a derived calculation with its assumptions stated, never as a fact.

Storage capacity monitoring and low-storage detection, which FR-041 and FR-042 already require, are built and unaffected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Not started without a product decision reversing the deferral
- [ ] #2 If revived, the privacy posture change is decided before any implementation
- [ ] #3 If revived, any forecast carries its evidence class and its assumptions
<!-- AC:END -->
