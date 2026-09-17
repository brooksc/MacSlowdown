---
id: TASK-114
title: 'Bounded field trial: does the explanation change a decision?'
status: Parked
assignee: []
created_date: '2026-09-06 16:54'
updated_date: '2026-09-17 18:48'
labels:
  - spike
  - decision
milestone: m-3
dependencies:
  - TASK-110
priority: high
type: spike
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both reviews independently said: stop expanding features and go and find out. The second put it hardest — the problem is real, but **a distinct product and a paying audience are unproven**, and "monitoring plus history plus alerts" is already a feature set that Activity Monitor, iStat Menus and EtreCheck cover between them. The potential standalone product is the reduction in *interpretation and decision effort*, and nothing measures that yet.

**Preconditions.** TASK-110 must be built — without user-reported slowdowns there is nothing to compare detections against, and the trial would measure only what we already detect. TASK-109 and TASK-111 should land too, or the trial measures copy nobody intends to ship.

**Who.** The owner plus a small group with the same shape: people running heavy local workloads who also need the machine responsive for other work — developers, local-model users, some creative professionals. The owner is a useful demanding test case but tolerates caveats others will not.

**What to capture.** Both detected episodes and user-marked slowdowns, and the relationship between them: how often each occurred without the other. That ratio is the product's actual precision and recall, and nobody has ever seen it.

**What to ask, per episode.** Did the explanation change a decision, save troubleshooting time, or provide justified reassurance? Compared against what they would otherwise have done — including simply waiting, which is often the correct action and costs nothing.

**The questions the trial exists to answer**, from the second review:
- Which recent slowdown caused a concrete loss of time, and what decision would this have changed?
- Does identifying an *application* improve the decision beyond knowing that CPU or memory was constrained?
- How often is the most useful answer "keep working, this load is expected"?
- When attribution fails, is the explanation still worth keeping the app installed?
- What happens when a user marks a slowdown and every measured resource looks normal?
- What background cost will users accept from an always-running recorder?
- Who would pay for the explanation, and what would they stop using?

**The decision it feeds.** If people mainly enjoy the graphs, this becomes a simpler monitor or a feature of one. If explanations repeatedly change decisions, the standalone case is credible. **Do not expand scope until this returns.**
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Detected episodes and user-marked slowdowns are both captured, with the overlap between them measured
- [ ] #2 Each episode carries whether the explanation changed a decision, saved time, or gave justified reassurance
- [ ] #3 The trial runs on more than the owner's machine
- [ ] #4 A written recommendation follows: standalone product, simpler monitor, or feature of something else
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Parked 2026-09-17 — needs days of real use on more than one machine, which a session cannot produce.** Named as an expected exception in the session's instructions, and criterion #3 says so outright: the trial runs on more than the owner's machine.

**The instrumentation it needs is now built, which is the part that was in scope.** Criterion #1 asks for detected episodes and user-marked slowdowns both captured with the overlap between them measured, and that exists end to end: `SlowdownReport` records the user's side, `SlowdownReportStore` persists it, and `SlowdownDetectionOverlap` computes reports-with and reports-without a coincident detection. Two things landed today that make the figure trustworthy rather than merely present:

- A retrospective report no longer inherits the conditions breaching at the moment of *filing* (TASK-120). Before that, filing a report about last Tuesday while any unrelated incident happened to be open counted as a coincidence — which would have inflated the exact number this trial turns on.
- A report can now be filed against a **coverage gap**, so the case where we were not watching at all produces data instead of a dead end (design 5c). Those are by construction reports without a detection, and they are the episodes the product currently has no other way of hearing about.

**Criterion #2 is not built and should not be built before the trial is scheduled.** Asking per-episode whether the explanation changed a decision, saved time, or gave justified reassurance is a questionnaire, and S-7 names asking the user to classify what they are experiencing as the first failure mode — it is why the previous attempt at feedback collected nothing. For a bounded trial the right instrument is probably an out-of-band note from the participant rather than a control in the product. **That is a design decision for the owner**, and building the control first would prejudge it.

Unpark when the trial is scheduled and participants exist.
<!-- SECTION:NOTES:END -->
