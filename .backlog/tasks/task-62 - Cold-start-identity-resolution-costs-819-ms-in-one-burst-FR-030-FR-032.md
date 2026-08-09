---
id: TASK-62
title: 'Cold-start identity resolution costs 819 ms in one burst (FR-030, FR-032)'
status: To Do
assignee: []
created_date: '2026-08-09 01:12'
updated_date: '2026-08-09 01:13'
labels:
  - core
milestone: m-3
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while re-measuring FR-030 for TASK-57. Not caused by that work — it was always there, and the overhead harness was not measuring it.

On the first sweep, FamilyGrouper.group resolves identity for every process in the table. Measured: 844 processes, 819 ms of work in a single burst. A warm sweep is 2.90 ms — a 282x difference between the first sweep and every one after it.

Two consequences.

FR-030. Over a 300 s run the one-off amortises to an acceptable figure — CPU came out at 0.963% of one core against a 1.0% budget — but that is 4% headroom, and a 90 s run reads 1.348% and breaches. The budget is stated as an idle median, so a startup burst arguably does not violate it. But a figure that depends this heavily on how long you measure is not one anyone should rely on. Either the burst goes, or the requirement should say explicitly that it excludes first-sighting cost.

FR-032 is the more interesting one. 819 ms before the first complete reading means the first thing the app does on launch is spend most of a second resolving identity — at exactly the moment a user who launched it because their Mac is slow is watching. Under real load it will be worse.

Options, in rough order of preference:
1. Resolve lazily. Only displayed processes need a name and icon; the inventory shows what fits on screen and the popover shows three. The rest resolve when scrolled to.
2. Spread the cold pass across sweeps — a bounded number of resolutions per sweep until the cache is warm. Preserves eventual completeness, removes the burst.
3. Resolve in priority order: measurable processes first, so the numbers that matter appear first.

Measure the split before choosing. The code signature call is likely the dominant term, not naming: identity plus naming is 0.821 ms per process, and naming alone is well under 0.1 ms of that.

Do not solve this by resolving less. The inventory needs every family named; the question is when, not whether.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The first complete reading is not delayed by a bulk identity pass; measure and record the time to first reading before and after
- [ ] #2 A 90-second standalone FR-030 run and a 300-second one agree within a small margin, so the figure no longer depends on run length
- [ ] #3 CPU stays inside the FR-030 budget with meaningful headroom, not 4%
- [ ] #4 Every family still gets a name and icon eventually; nothing is permanently left as a fragment because it was never resolved
- [ ] #5 The dominant cost is measured and recorded, so the next person does not re-derive whether it was the signature call or naming
<!-- AC:END -->
