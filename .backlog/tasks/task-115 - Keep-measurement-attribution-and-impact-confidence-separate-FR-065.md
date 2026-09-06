---
id: TASK-115
title: 'Keep measurement, attribution and impact confidence separate (FR-065)'
status: To Do
assignee: []
created_date: '2026-09-06 16:54'
labels:
  - core
milestone: m-2
dependencies:
  - TASK-109
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
"Sustained memory pressure was measured" and "Xcode is slowing your Mac" differ in three independent ways, and the product currently lets them collapse. A measurement can be certain while its attribution is a hypothesis and its effect on the user is entirely unknown.

The failure this prevents is the most expensive one available: being confidently wrong about *which application*, which sends someone to quit useful work.

**Withholding a numerical score is correct and is not the same as withholding uncertainty.** No banner should say "60% confident" — that hands our problem to someone who cannot resolve it. But the uncertainty that matters must still be expressed, in words, and the three kinds must stay separable. FR-038's evidence classes already carry most of this; what is missing is the rule that they may not be merged into one summary judgement.

**Where to look:** incident summaries and their conclusions, the contributor list's confidence labels, the popover and notification wording, and anywhere a single "confidence" value is displayed as though it covered the whole finding.

Depends on TASK-109, which removes impact claims from resource measurements — much of the collapse disappears with it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No single label or score stands for measurement, attribution and impact together
- [ ] #2 A high-confidence measurement never confers confidence on its attribution
- [ ] #3 No numerical confidence score is shown to the user
- [ ] #4 Uncertainty that affects a decision is still stated, in words
<!-- AC:END -->
