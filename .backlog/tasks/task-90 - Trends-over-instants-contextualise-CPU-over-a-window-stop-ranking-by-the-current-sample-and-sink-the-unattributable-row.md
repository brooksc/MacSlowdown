---
id: TASK-90
title: >-
  Trends over instants: contextualise CPU over a window, stop ranking by the
  current sample, and sink the unattributable row
status: In Progress
assignee: []
created_date: '2026-08-24 04:04'
updated_date: '2026-08-26 18:35'
labels:
  - ui
  - decision
milestone: m-3
dependencies: []
priority: high
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product direction stated by the product owner on screen, 2026-08-23, after using the built app for the first time. Recorded in their words because it reframes what several surfaces are for:

> "this isn't really intended so much as a real time CPU monitor but to show general trends on my machine. It's nice that it's showing every 1s what Google Drive's CPU is, but I think it detracts from the analysis part by doing that — or at least not putting it in context (e.g. over the past 1m it used xx cpu) to show more about why your machine is slow. I wouldn't cut the real time cpu, but at the same time maybe don't sort based on the highest cpu. Also I don't know what to do about the system processes we can't measure - I'd suggest just putting it at the bottom of the list of processes because saying we don't know what it is doesn't really add much value to the user it's noise."

Three distinct changes, with different amounts of spec exposure.

**1. Context, not instants.** A figure like "Google Drive 29%" answers "what is happening this second", which is not the question the product exists to answer. The proposal is to show a windowed figure alongside or instead — "over the last minute, xx%" — so a row states a sustained fact rather than a sample. This is well aligned with the existing sustained-not-transient rule (FR-006, FR-011) and with FR-005's retained history, which is already kept and already underused. The instantaneous reading is not to be removed.

**2. Default sort is not current CPU.** Ranking by the newest sample makes the list reorder constantly and promotes whatever spiked in the last second. Candidates: mean or peak over the retained window, or time spent above a threshold. Note TASK-74 already froze the inventory's *order* for 10 s to stop it churning — that is a symptom of the same problem, and this change may make that holding period unnecessary or may compose with it. FR-027 governs sorting and grants the choice of default; user-selectable sort is a separate matter (TASK-56).

**3. The unattributable row moves to the bottom.** This is the one with a real constraint. FR-055's design freedom says presentation is open **but the remainder may not be visually de-emphasised into insignificance**, and its acceptance criteria require that contributor lists visibly sum.

The compliant split, to be confirmed with the product owner:
- In the **process/peer list** (Apps & Processes, design 1d/1m) the unattributable entry is a row among hundreds and is not a contributor list. Pinning it to the bottom, out of the ranking, is presentation freedom and is fine.
- In a **contributor list** (the popover's "SHARE OF THE BUSY TIME", incident evidence, reports) FR-055 requires it stay first-class and in the sum — in the screenshot that prompted this it was third at 18%, which is exactly what the requirement is for. Sinking it there would need a spec amendment, and given the measured ~40 percentage points of unattributable CPU it is the entry that stops the other rows being read as a complete explanation.

Do not start implementing until the split above is confirmed, and until the windowed statistic in (1) is chosen — mean, peak, or time-above-threshold are materially different claims and the copy has to say which one it is (FR-038).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The windowed statistic is chosen and named in copy, so a figure states which window and which statistic it is
- [x] #2 The instantaneous reading remains available and is never presented as a sustained fact
- [x] #3 Default ordering is derived from the retained window rather than the newest sample, and the interaction with TASK-74's 10 s order hold is settled
- [ ] #4 The unattributable entry is pinned outside the ranking in the peer process list
- [x] #5 The unattributable entry remains first-class and in the sum wherever contributors are presented, or FR-055 is amended first
- [ ] #6 Verified on screen: a row's figure does not visibly churn at sampling cadence, and the list does not reorder on a one-second spike
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Settled and built, 2026-08-25/26

**The statistic is the mean over a trailing 60 s** (product owner: "averaging this over the last 1m"). Delivered through `FamilyHistory.trailing`, which carries mean, peak, sample count and the span actually covered, and `TrailingPresentation`, which names the window and says the span out loud when it is short. Built under TASK-95, along with the per-family retention that made it possible and the FR-031 cadence amendment that feeds it.

**The instant is kept.** The Now table now has two labelled columns, "Now" and "Last minute", rather than one ambiguous "CPU". A spike is real information; it is just not the thing to rank a list by.

**Default sort is the trailing mean** (`InventoryRow.trendSortKey`, used by `defaultInventorySort`), falling back to the instant while no history exists so a freshly launched application takes its place immediately rather than sinking for a minute. A fallback, not a blend — averaging the two would give a figure that is neither.

**Interaction with TASK-74's 10 s order hold:** left in place. They address different causes — the hold damps re-sorting between samples, the mean damps what is being sorted — and removing the hold is a change worth making on its own evidence, on screen, rather than blind.

**AC #4 (the unattributable row pinned in the peer list) was split out as TASK-93** and is done for both popover lists. The peer *process* list in Apps & Processes has not been checked for the same behaviour.

Remaining here: AC #4's Apps & Processes half, and AC #6, which needs the screen.
<!-- SECTION:NOTES:END -->
