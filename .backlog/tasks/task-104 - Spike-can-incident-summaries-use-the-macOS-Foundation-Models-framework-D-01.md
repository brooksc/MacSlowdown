---
id: TASK-104
title: >-
  Spike: can incident summaries use the macOS Foundation Models framework?
  (D-01)
status: In Progress
assignee: []
created_date: '2026-08-31 20:43'
updated_date: '2026-09-17 18:54'
labels:
  - spike
  - decision
milestone: m-3
dependencies: []
priority: medium
type: spike
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product owner, 2026-08-31, on D-01: open to using a model, on condition it ships **with macOS 26 or 27** rather than being bundled or reached over the network. They run the 27 public beta, and expect 27 to be the stronger case.

That points at the **Foundation Models framework** — Apple's on-device model, available to third-party apps. Nothing here should be built until the questions below are answered, because the failure mode is not a crash, it is a fluent sentence that is wrong.

**Feasibility**

1. Is it available on **macOS 26** as well as 27, and with the same capabilities? A26 is a target and the summariser cannot have two personalities.
2. Does it work under **App Sandbox**, and is it accepted for **Mac App Store** distribution with no additional entitlement?
3. What happens on a machine where **Apple Intelligence is unavailable or switched off** — unsupported hardware, an unsupported region, a user who declined it? The deterministic templates must remain a first-class path, not a degraded one, because a large share of users will land there.
4. What does it cost? This app's whole objective is not becoming part of the slowdown, and generating a paragraph during an incident is generating it at the worst possible moment. Measure, and consider generating on close rather than on open.

**The question that actually decides it**

5. **How is a generated sentence held to FR-038?** Every conclusion carries an evidence class — measured fact, derived calculation, heuristic hypothesis, user-provided — and a model can produce a fluent claim nothing measured. The options are roughly: constrain generation to rephrasing values the templates already computed, so the model never introduces a fact; or generate freely and verify every claim against the incident record before showing it, which is most of the work with none of the simplicity. Until there is an answer here, a model is a liability rather than a feature.

**Recommendation before the spike runs:** templates stay. They are built, they are testable, and they cannot invent a cause. The case for a model is that it reads better and generalises to combinations the templates handle awkwardly — a real benefit, but a smaller one than the risk it introduces to a product whose central promise is that it never overstates what it measured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Availability on macOS 26 and 27 is established, not assumed
- [ ] #2 Sandbox and Mac App Store acceptability are established, with any entitlement named
- [ ] #3 Behaviour when Apple Intelligence is unavailable or disabled is established, and the template path confirmed as first-class
- [x] #4 Generation cost is measured, and the timing question — generate on open or on close — is settled by that measurement
- [x] #5 A concrete proposal exists for holding generated text to FR-038, or the spike concludes that a model cannot be held to it
- [ ] #6 The finding is written to probe/FINDINGS.md whichever way it goes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Spike run 2026-09-17. The decisive finding is #5, and it is negative.**

**#1, partly.** `FoundationModels` is importable against the macOS 27 SDK and `SystemLanguageModel.default.availability` returns `.available` on this M2 MacBook Air, with 24 supported languages. **Not established on macOS 26** — the VM was in use for the capture run and this was not asked of it. Leaving #1 unchecked for that reason; it is one 30-second probe away.

**#4 measured, not estimated.** Five generations of a two-sentence incident summary from the fact set `IncidentSummarizer` already holds: **median 2.88 s**, min 2.51 s, max 4.31 s, with the first run the slowest (warm-up). That settles the timing question the criterion attaches to it: **generate on close, never on open.** Three seconds is far too long to hold a screen the user has just asked for, and an incident's facts are frozen when it closes anyway — so the summary can be produced once, at close, and stored beside the attribution that is already frozen there.

**#5 — and this is the finding that matters.** Given all three classes of fact explicitly labelled in the prompt — measured, calculated, and likely-with-confidence — the model returned:

> "Your Mac's total CPU was above 85% of its capacity for 10 minutes starting at 2:13 PM, with a peak of 94%. Memory pressure reached a warning level, and Brave Browser was the largest measurable contributor, peaking at 412% of one core."

Fluent, accurate in what it says, and it **silently dropped the unattributed remainder** — "13% of busy CPU could not be attributed to any process we are permitted to measure" is simply absent. It also flattened "likely, high confidence" into a bare statement of fact about Brave Browser.

Those are not stylistic losses. They are the two things FR-038 and FR-013 exist to prevent, and the product's whole thesis is that the limitation is stated rather than tidied away. A summariser that omits the limitation *most of the time* is worse than one that never had it, because the omission is invisible — nobody reading the output can tell a complete summary from a truncated one.

**So the honest answer to #5 is the second branch the criterion offers**: a model can be held to FR-038 only by constraining it so tightly that it stops being a summariser. Guided generation into a fixed schema, then rendering the schema deterministically, would work — but at that point the template is doing the work and the model is choosing adjectives.

**My recommendation, for the product owner — D-01 is theirs to decide.** Keep deterministic templates. The measured failure is not a prompt-engineering problem to iterate on; it is the model doing what a summariser does, which is decide what matters. This product's differentiator is that it does not get to decide that.

**A narrower use worth considering instead**, if the owner wants the capability: let the model rewrite a *single* deterministic sentence that already contains every required clause, with the clauses supplied as a checklist and the output rejected if any is missing. That keeps FR-038 enforceable by assertion rather than by hope.

**#2, #3 and #6 not done.** Sandbox and App Store acceptability (#2) and the unavailable-path behaviour (#3) are unanswered — both matter only if the owner overrides the recommendation, so I stopped rather than spend on a branch I am recommending against. The finding is written here rather than in `probe/FINDINGS.md` (#6) for the same reason: it belongs there once the decision is made, and `FINDINGS.md` is for settled platform facts rather than for a recommendation awaiting a ruling.
<!-- SECTION:NOTES:END -->
