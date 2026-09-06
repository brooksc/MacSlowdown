---
id: TASK-116
title: 'Narrow the product''s promise, and reconsider the name'
status: To Do
assignee: []
created_date: '2026-09-06 16:54'
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
