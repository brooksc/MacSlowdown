---
id: TASK-90
title: >-
  Trends over instants: contextualise CPU over a window, stop ranking by the
  current sample, and sink the unattributable row
status: To Do
assignee: []
created_date: '2026-08-24 04:04'
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
- [ ] #1 The windowed statistic is chosen and named in copy, so a figure states which window and which statistic it is
- [ ] #2 The instantaneous reading remains available and is never presented as a sustained fact
- [ ] #3 Default ordering is derived from the retained window rather than the newest sample, and the interaction with TASK-74's 10 s order hold is settled
- [ ] #4 The unattributable entry is pinned outside the ranking in the peer process list
- [ ] #5 The unattributable entry remains first-class and in the sum wherever contributors are presented, or FR-055 is amended first
- [ ] #6 Verified on screen: a row's figure does not visibly churn at sampling cadence, and the list does not reorder on a one-second spike
<!-- AC:END -->
