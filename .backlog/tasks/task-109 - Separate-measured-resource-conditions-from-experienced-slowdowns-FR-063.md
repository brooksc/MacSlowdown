---
id: TASK-109
title: Separate measured resource conditions from experienced slowdowns (FR-063)
status: Done
assignee: []
created_date: '2026-09-06 16:53'
updated_date: '2026-09-08 16:51'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**The governing finding of both product reviews, reached independently by different routes.** The product measures resource conditions and reports them as slowdowns. No amount of threshold, duration or attribution work closes that gap, because the gap is not measurement error.

The proof is S-4 in `scenarios.md`: a capped build and a real slowdown are the same measurement — same load, same duration, same attribution — and the only difference is in the user's head. Telling a person compiling that their Mac has a problem is not over-sensitivity, it is a misreading of what they were doing, said out loud. Apple's own documentation describes elevated CPU during intensive calculation as expected.

**What changes.** Copy states what was measured and over what interval, and stops there. "CPU stayed near capacity for 3 minutes" — not "Your Mac is slow", not "Severity high" as a proxy for impact, not "Xcode is slowing your Mac".

Severity describes the *measurement*. It must not be used, in wording or in emphasis, as a claim about the user's experience.

**Scope — this reaches most user-facing copy.** Notification titles and bodies; the Now headline and its banner; the popover headline; the menu bar spoken label; incident summaries and their conclusions; the incidents list subjects. Each needs reading against the question "does this assert the user was affected?"

**Not in scope:** removing severity, which is a useful ordering of measurements and drives interruption policy. Only its use as an impact claim.

Depends on nothing. Blocks nothing, but everything downstream reads better once it lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No notification, headline or summary asserts impaired responsiveness from resource measurements alone
- [x] #2 Severity wording is never used as a proxy for user impact
- [ ] #3 A user-reported slowdown and a measured condition are distinguishable wherever both appear
- [x] #4 A forbidden-phrase test covers the new class, as the existing ones cover 'crashed' and 'optimize'
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Done 2026-09-08**, commit 2c65415.

**What changed.** Every headline that asserted an experience now states a measurement:

| Was | Now |
|---|---|
| "A slowdown is in progress" | "A sustained condition is being recorded" |
| "Nothing sustained is slowing this Mac down" | "No sustained condition right now" |
| "This Mac is working hard" | "CPU has been high for the last half-minute" |
| "This Mac is heavily loaded" | "CPU has been near capacity for the last half-minute" |
| "Your Mac is running normally" | "No sustained condition right now" |
| "Your Mac was under sustained load" | "A sustained condition was recorded" |
| "Your Mac has been under strain" | "A sustained condition has been recorded" |
| "Your Mac ran short of comfortable memory" | "macOS reported memory pressure" |

The last one is worth noting separately: "comfortable" was our judgement wearing a measurement's clothes. The kernel reports a pressure level and that is all we know.

**Left alone deliberately.** "Your Mac's processors were close to fully busy", "CPU has been maxed", "Memory has been under pressure", "This Mac has been running hot" — these describe the machine's measured state, not the user's experience, and are exactly what FR-063 wants.

**`MacSlowdown/Tests/ConditionNotExperienceTests.swift`** sweeps for phrases that claim an experience across every Now and popover headline in all three severities, open and closed; every combination of incident conditions including the empty fallback; and every severity label. Written as a sweep rather than exact-string assertions on purpose — the wording belongs to design, the claim does not.

**Criterion #3 is not checked.** It asks that a user-reported slowdown and a measured condition be distinguishable wherever both appear, and user-reported slowdowns do not exist yet — that is TASK-110. Nothing to distinguish from until it lands, so the criterion is carried there rather than claimed here.

1151 passing.
<!-- SECTION:NOTES:END -->
