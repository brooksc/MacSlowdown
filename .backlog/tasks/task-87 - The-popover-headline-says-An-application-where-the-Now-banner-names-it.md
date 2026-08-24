---
id: TASK-87
title: The popover headline says "An application" where the Now banner names it
status: To Do
assignee: []
created_date: '2026-08-24 04:03'
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
- [ ] #1 The popover headline names the subject application for a repeated-quit incident, using the same wording and confidence qualifier as the Now banner
- [ ] #2 Where no subject is known the condition-only wording is used unchanged, and a test covers that path
- [ ] #3 A test asserts the popover and the Now banner produce the same subject for the same incident
- [ ] #4 IncidentEvidence's wording is checked for the same gap and either fixed or recorded as deliberately anonymous
- [ ] #5 Verified on screen in the popover during a real repeated-quit incident
<!-- AC:END -->
