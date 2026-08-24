---
id: TASK-87
title: The popover headline says "An application" where the Now banner names it
status: In Progress
assignee: []
created_date: '2026-08-24 04:03'
updated_date: '2026-08-24 04:25'
labels:
  - ui
milestone: m-2
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on screen by the product owner, 2026-08-23.

The popover headline for a repeated-quit incident reads "An application has been quitting and reopening" — anonymous, when the incident knows its subject.

TASK-82 fixed exactly this for the **Now banner**: `NowPresentation.bannerHeadline` calls `leadingRelaunchPattern(incident)` and produces "<name> keeps quitting and reopening" with a heuristic confidence qualifier (`heuristicQualifier(pattern.confidence)`), because the association between exits of one command is a heuristic and FR-038 requires the label.

The popover never received it. `PopoverPresentation.conditionPhrase` (`MacSlowdown/Sources/PopoverPresentation.swift:347`) is a pure `IncidentCondition -> String` map with no access to the incident, so it cannot name anything. `PopoverPresentation.incidentHeadline` has the incident in hand and could.

Note `IncidentEvidence.swift:141` carries a third anonymous wording of the same condition ("An application quit and started again, repeatedly"). Check whether it has the same gap while here.

The naming must carry the same confidence qualifier the banner uses — a name without its heuristic label would be a stronger claim in the popover than in the banner, and TASK-82's whole point was that the surfaces must not disagree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The popover headline names the subject application for a repeated-quit incident, using the same wording and confidence qualifier as the Now banner
- [x] #2 Where no subject is known the condition-only wording is used unchanged, and a test covers that path
- [x] #3 A test asserts the popover and the Now banner produce the same subject for the same incident
- [x] #4 IncidentEvidence's wording is checked for the same gap and either fixed or recorded as deliberately anonymous
- [ ] #5 Verified on screen in the popover during a real repeated-quit incident
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`PopoverPresentation.incidentHeadline` now resolves the subject through `NowPresentation.leadingRelaunchPattern` — the same single rule the banner uses, which its own doc comment insists on ("One rule, one place") — and passes it to `conditionPhrase(_:subject:)`. New `incidentHeadlineQualifier` returns the heuristic label, present exactly when the headline names an application, and the popover renders it as its own caption line and includes it in the accessibility label.

**`IncidentEvidence.phrase` is deliberately left anonymous** (AC #4). Its headline's stated contract is that it makes no causal claim and therefore carries no confidence label. Naming the application would break that: the association between exits sharing a truncated 16-byte command *is* a heuristic, so a name there would be the one unlabelled heuristic claim on the screen (FR-038). The reason is now written at the case itself. The detail screen names the subject where the label can travel with it.

Four tests in `PopoverRepeatedQuitSubjectTests`: the subject is named; a name never appears without its qualifier, and the qualifier is the framework's own label rather than a second wording of it; the anonymous fallback survives with no qualifier; and the popover and the banner name the same application and carry the same qualifier for one incident.

`-only-testing:MacSlowdownTests`: one failure, the pre-existing TASK-91 container-isolation issue. AC #5 needs the screen and is unchecked.
<!-- SECTION:NOTES:END -->
