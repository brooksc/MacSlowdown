---
id: TASK-116
title: 'Narrow the product''s promise, and reconsider the name'
status: Parked
assignee: []
created_date: '2026-09-06 16:54'
updated_date: '2026-09-17 18:49'
labels:
  - decision
milestone: m-3
dependencies: []
priority: medium
type: spike
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the second review. "MacSlowdown" invites expectations the evidence cannot support: beachballs, an individual sluggish application, unexplained delays generally. Application hangs are undetectable to us; per-app network is impossible; a large share of activity is unattributable.

What the available evidence *does* support is a narrower and defensible promise: **understanding sustained resource pressure and its recent history.**

**The cost of narrowing is a smaller audience. The cost of not narrowing is repeatedly delivering an honest answer that still fails the reason someone installed it** — which is the worse failure, because it is invisible until the user leaves.

**Two decisions, and they are separable:**

1. **The promise** — what §1 and §2 claim, and what the interface implies on first run. This is the substantive half and should be settled regardless of the name.
2. **The name** — cheaper to say than to do, and only worth changing if the promise narrows. Park until after the field trial (TASK-114): if the trial says this is a simpler monitor or a feature of something else, the naming question resolves itself.

**Distribution stays as it is for now**, and the reasoning is worth recording: ordinary unsandboxing does not solve the cross-user visibility problem — only root does — so a privileged build would take on installation, trust, support and maintenance cost before we have established that more attribution would change anyone's decision. Change distribution only after real cases repeatedly fail for one specific missing capability, **and** after verifying the proposed privilege actually supplies it.

Related: the process-enumeration risk (spec §10.3) is unresolved and gates nothing, while being called the largest single risk. Those cannot both be true — see TASK-50, which should be raised in priority.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The product's promise in §1 and §2 is narrowed to what the evidence supports, or the wider promise is defended in writing
- [ ] #2 First-run copy matches the narrowed promise
- [ ] #3 The naming decision is made after the field trial, not before
- [ ] #4 The distribution decision is recorded with its reasoning so it is not re-litigated without new evidence
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Parked 2026-09-17 — every criterion here is the product owner's to decide, and #3 says explicitly that the naming decision comes after the field trial.** TASK-114 is parked for want of participants, so this is parked behind it.

**What has moved in the meantime, so the decision is not re-derived from scratch:**

- **The narrowing #1 asks for has largely happened in the product**, ahead of the specification. First run now opens "What this can and can't tell you" and says in the second paragraph: "We can't tell you your Mac was slow — we measure resources, not how it felt to use. A Mac flat out on a video export and a Mac that's genuinely struggling look identical to us, so we'll tell you what was measured and leave the verdict to you." The third says about 40% of a busy Mac is invisible to us. Seen on screen today: `design/verified/2026-09-17/06-first-run.png`. That is **criterion #2 already satisfied**, which inverts the task's expected order — the copy is now narrower than §1 and §2 of `requirements.md`, so the spec is the thing out of step.
- The governing product decision of 2026-09-06 (a measured resource condition is not a slowdown the user experienced) is what drove that copy, and it is recorded in `CLAUDE.md` and in FR-063.

**My recommendation on #1, for the owner to accept or reject:** narrow §1 and §2 to match the first-run copy rather than defend the wider promise. The wider promise is not supported by anything measurable — the 40% unattributable share is a hard limit of the sandbox and of uid, not a gap that further work closes — and the product already tells the user so on its first screen. Leaving the spec wider than the product means every future reader has to discover the narrowing by reading the UI.

**#3 and #4 are untouched and should stay so**: a name and a distribution decision made before the trial would be exactly the re-litigation #4 exists to prevent.
<!-- SECTION:NOTES:END -->
