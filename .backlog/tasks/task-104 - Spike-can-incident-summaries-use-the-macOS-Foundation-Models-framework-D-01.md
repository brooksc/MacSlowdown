---
id: TASK-104
title: >-
  Spike: can incident summaries use the macOS Foundation Models framework?
  (D-01)
status: To Do
assignee: []
created_date: '2026-08-31 20:43'
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
- [ ] #4 Generation cost is measured, and the timing question — generate on open or on close — is settled by that measurement
- [ ] #5 A concrete proposal exists for holding generated text to FR-038, or the spike concludes that a model cannot be held to it
- [ ] #6 The finding is written to probe/FINDINGS.md whichever way it goes
<!-- AC:END -->
