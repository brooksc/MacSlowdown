---
id: TASK-93
title: Unattributed system activity wanders up and down the contributor list
status: In Progress
assignee: []
created_date: '2026-08-25 17:49'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed on screen by the product owner, 2026-08-25: the "Unattributed system activity" row climbs and falls through the "Share of the busy time" list every few seconds as the machine breathes, which is distracting and makes the list hard to read.

It was sorted by value among the applications. But it is an **aggregate**, not a contributor — and "Other applications", the other aggregate in the same list, has always been appended after the sort for exactly that reason. One of the two was pinned and the other was not.

Both `PopoverPresentation.contributorRows` and `PopoverPresentation.shareRows` had the same shape of bug.

**The FR-055 constraint, and how this stays inside it.** FR-055's design freedom says presentation is open *but the remainder may not be visually de-emphasised into insignificance*, and its acceptance criteria require contributor lists to visibly sum. Position is not the concern — a stable slot is more legible than a moving one, not less. What would breach it is pinning *and* dimming, and the row was already drawn in secondary grey. So the two changes travel together: pinned to the foot, and drawn at full text weight like the applications above it.

Extracted from TASK-90, which carries the wider trends direction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The unattributed row is pinned below the ranked applications in both the live contributor list and the incident share list
- [ ] #2 Its position does not depend on its value, at any value
- [ ] #3 It is drawn at full text weight rather than dimmed, keeping its full-width bar and its explanation
- [ ] #4 The applications above it remain ranked among themselves and the shares still sum to exactly 100
- [ ] #5 Verified on screen: the row holds its place while the machine is busy
<!-- AC:END -->
