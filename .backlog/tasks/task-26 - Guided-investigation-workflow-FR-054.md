---
id: TASK-26
title: Guided investigation workflow (FR-054)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 07:00'
labels:
  - ui
milestone: m-2
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Raw evidence remains accessible
- [ ] #2 No step requires accepting an unsupported conclusion
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
GuidedInvestigation.swift: InvestigationStage, InvestigationAction, InvestigationStep, GuidedInvestigation, InvestigationBuilder.

Organised around FR-054's five questions in order: what happened, what was involved, was this expected, what can I do, did anything change.

- AC#1 Raw evidence remains accessible from EVERY step, not just at the end -- each carries the AttributedFigures behind it, and a test asserts no step hides its evidence. 'Show me the numbers' is never more than one interaction away.
- AC#2 No step requires accepting an unsupported conclusion. canContinue is unconditionally true and asserted per step, so a user who disagrees with an interpretation is never blocked by it. Interpretation is offered, never demanded. Every hypothesis carries a confidence, also asserted per step.

Details worth noting:
- The first step deliberately leads with measured facts and contains no hypotheses at all, tested. Opening an investigation with interpretation would prime the user toward a conclusion the evidence may not support.
- A large unattributed share adds an explicit caveat that the contributor list 'may be incomplete rather than wrong'. That distinction matters: incomplete is honest, wrong would be misleading.
- A relaunch pattern always travels with RelaunchPattern.limitation attached, so the 'we cannot tell whether an app has stopped responding' caveat cannot be separated from the finding.
- A user's own 'expected' marking is labelled .userProvided, which is FR-038's fourth evidence class finally earning its place.
- Marking something expected is described as reversible and as still recorded in history, both asserted, since FR-016 requires suppressed detections keep an audit trail.

Actions are tested against process control: no action's id, title or explanation may contain quit, kill, force, suspend, pause, throttle, renice, limit or terminate. The workflow states plainly that MacSlowdown does not quit, pause or throttle applications, and offers Activity Monitor for what we cannot see.

FR-050 guard: a closed incident reports that conditions returned to normal without attributing recovery to anything the user did.
<!-- SECTION:NOTES:END -->
