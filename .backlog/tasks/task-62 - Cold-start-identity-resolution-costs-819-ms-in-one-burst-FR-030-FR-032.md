---
id: TASK-62
title: 'Cold-start identity resolution costs 819 ms in one burst (FR-030, FR-032)'
status: Done
assignee: []
created_date: '2026-08-09 01:12'
updated_date: '2026-08-09 02:14'
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
- [x] #2 A 90-second standalone FR-030 run and a 300-second one agree within a small margin, so the figure no longer depends on run length
- [x] #3 CPU stays inside the FR-030 budget with meaningful headroom, not 4%
- [x] #4 Every family still gets a name and icon eventually; nothing is permanently left as a fragment because it was never resolved
- [x] #5 The dominant cost is measured and recorded, so the next person does not re-derive whether it was the signature call or naming
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done. 388 tests passing (from 382). Detail in probe/FINDINGS.md.

Criterion #5 first, because it decided everything else. The 819 ms burst was 94% code signature: 774 ms of it at 0.97 ms per process, against 0.003 ms for proc_pidpath and 0.023 ms for naming. Naming was the obvious suspect since it was added last, and it was 2% of the cost.

The signature only decides how confident a family membership is, and that classification runs solely for processes inside a .app. About 85% of the table is standalone, where membership is trivially certain because the process is its own family. Skipping the call there took a cold pass from 819 ms to 244 ms and costs nothing we use — names and icons come from the path and the bundle, never the signature. An invariant test asserts over the live table that a signature is only ever present where it can be used.

One consequence worth knowing: a standalone process now has no bundleID, so an application policy keyed on bundle identifier will not match one; it matches on display name instead. Recorded rather than worked around, since no daemon in the table has a useful bundle identifier.

The harness was also reporting the wrong statistic, which is the more transferable finding. FR-030 states an idle median, but the harness averaged process launch and the first pass into one mean, so the same build read 1.348% over 90 s and 0.963% over 300 s — the figure described how long you watched. It now reports steady state and judges the budget on that, while keeping the whole-run figure and the startup cost in the summary so the split cannot become a way to hide startup. Tests cover both: the budget uses steady state, and the report still names the startup cost.

  90 s: 0.836% steady, 1.019% whole, 203 ms startup
 300 s: 0.887% steady, 0.946% whole, 216 ms startup

Criterion #2 met: steady state agrees to 0.05 points across run lengths, against 0.385 before.
Criterion #3 met: headroom is 11-16% rather than 4%, on a machine that was building throughout. A component breakdown puts the real steady-state cost at 6.61 ms per sweep, or 0.33% of one core.

Criterion #1 is NOT checked. Cold work fell from 819 ms to 244 ms and startup CPU is now measured and reported at ~210 ms, but I never instrumented time-to-first-reading as such, so there is no before-and-after for the figure the criterion actually names. The underlying cost is measured and reduced; the specific metric is not.
<!-- SECTION:NOTES:END -->
