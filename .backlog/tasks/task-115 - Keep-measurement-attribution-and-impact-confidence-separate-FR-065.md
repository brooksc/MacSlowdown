---
id: TASK-115
title: 'Keep measurement, attribution and impact confidence separate (FR-065)'
status: Done
assignee: []
created_date: '2026-09-06 16:54'
updated_date: '2026-09-09 02:09'
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
- [x] #1 No single label or score stands for measurement, attribution and impact together
- [x] #2 A high-confidence measurement never confers confidence on its attribution
- [x] #3 No numerical confidence score is shown to the user
- [x] #4 Uncertainty that affects a decision is still stated, in words
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Done 2026-09-08**, merged as 5e6a4b8.

Three collapses, each found in the code rather than invented.

**1. A clean measurement was conferring its certainty on an uncertain name.** Both inputs to `IncidentAttribution.confidence(for:)` — the leader's share of busy CPU and the unattributable remainder — describe how well we *read* the machine. Neither says whether the processes we summed are one application. So a sweep where nearly everything was readable and one family dominated returned `.high` for a family held together by nothing better than a shared directory. That is FR-065's expensive direction exactly: confidently wrong about which app, which sends someone to quit useful work. Now capped at `.moderate` when the leading family has uncertain members — capped rather than fixed, following the `RelaunchPattern.causeConfidence` precedent.

**2. Two impact claims survived FR-063**, both inside sentences that also carried an attribution, so one confidence label stood for both: `PopoverPresentation.cause`'s "While that continues, other apps are likely to feel slower", and `MemoryPressureLevel.critical`'s "which can make everything feel slower". Both removed. Neither was caught by TASK-109's sweep because that sweep was headline-shaped and these sat in body copy — worth remembering.

**3. A bare confidence word did not say what it qualified.** `heuristicQualifier` became `attributionQualifier`, rendering "Likely · moderate confidence in which application". Renamed deliberately so a future caller holding a *cause* confidence cannot reach for a phrase that says "which".

`MacSlowdown/Tests/ConfidenceSeparationTests.swift` — 10 tests, sweep style, including a scan that no confidence is ever expressed numerically.

**Deliberately not done:** `Conclusion` was not given a `ConfidenceSubject` field. That is the structurally pure fix, but the type is `Codable` and persisted, so a new field risks the schema for a distinction the display layer already carries in words. Recorded as the option passed on, not rejected.

**Follow-on, now also done.** The longer caption was four words wider on the popover, the tightest surface in the product. Measured at its real geometry (340 pt, 14 pt padding, `.caption2` at 10 pt, uppercased) the long form is 294.5 pt against 312 available — it fits, and design 6a's premise that it wrapped was wrong. `attributionQualifierAtAGlance` was added anyway, reading "Which app · likely, moderate confidence": it says what is uncertain before how uncertain, and clears the width by 77 pt where the long form clears it by 17. See TASK-113's notes and `PopoverDecisionsTests`.
<!-- SECTION:NOTES:END -->
