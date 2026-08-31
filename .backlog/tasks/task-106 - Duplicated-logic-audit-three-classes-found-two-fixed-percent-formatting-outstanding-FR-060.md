---
id: TASK-106
title: >-
  Duplicated logic audit: three classes found, two fixed, percent formatting
  outstanding (FR-060)
status: In Progress
assignee: []
created_date: '2026-08-31 21:14'
labels:
  - core
  - infra
milestone: m-3
dependencies: []
priority: medium
type: chore
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Product owner, 2026-08-31, accepting FR-060 as a debt to pay down rather than a rule for new work only: "it's important that all key logic be implemented in one place for maintenance and consistency. Do a review to see if there are other cases like this."

The review found three classes. None was *wrong*, which is what makes them dangerous — the moment one copy is corrected the others quietly disagree, and two surfaces start describing the same fact differently. That is the shape of most of the review findings in TASK-96.

**1. Duration phrasing — five implementations. Fixed.**
`PopoverPresentation.elapsedPhrase` and `MenuBarPresentation.durationPhrase` were line-for-line the same algorithm differing only in "min" versus "minutes". Three more lived in `NotificationPolicy`, `LifecycleEvents` and `StorageHistory`, each rounding a little differently. So one incident could be "6 min" in the popover and "6 minutes" in the banner, and any correction to one would have left the rest behind. Now `DurationPhrase` with two registers — `.compact` for figures read at a glance, `.full` for prose — one arithmetic, two voices, which is a real difference of register rather than a duplicated rule.

**2. Trailing statistics — two implementations. Fixed.**
`FamilyHistory.trailing(for:)` over `FamilyHistoryPoint` and `TrailingPresentation.trailing(of:)` over `SparklinePoint`, identical in every line that mattered, written a week apart by the same hand. Both now delegate to `TrailingUsage.over(_:window:now:)`, which takes `(at, value)` pairs.

**3. Percent formatting — about twelve hand-rolled sites. Outstanding.**
`CPUPresentation.percentOfOneCore` is the canonical formatter and many surfaces use it; roughly a dozen others inline `Int(x.rounded())%` — in `IncidentEvidence`, `AlertSettings`, `RepeatedQuitIncident`, `UnattributedIncident`, `StorageView`, `MenuBarIconReadout`. Two risks: rounding could drift, and the *units* are already inconsistent in the wild — some say "of one core", others "of this Mac's capacity", others nothing at all. FR-004 requires the convention be stated consistently, so this is a live requirement rather than tidiness.

**Deliberately not merged:** `DateComponentsFormatter.incidentDuration` stays separate from `DurationPhrase`. Apple's formatter is localized and ours is not, which is a real reason for two implementations — recorded here so a later reader does not "fix" it. If localization is ever adopted the two should be reconciled, and `DurationPhrase` is the one that would go.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duration phrasing has one implementation with explicit registers
- [ ] #2 Trailing statistics have one implementation
- [ ] #3 Percent formatting goes through one formatter, with the unit stated consistently per FR-004
- [ ] #4 The deliberate divergence from DateComponentsFormatter carries its reason in the code, per FR-060
- [ ] #5 A standing check exists for 'the same fact derived in two places', or its absence is recorded as accepted
<!-- AC:END -->
