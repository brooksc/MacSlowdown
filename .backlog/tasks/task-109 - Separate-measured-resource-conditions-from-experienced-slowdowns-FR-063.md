---
id: TASK-109
title: Separate measured resource conditions from experienced slowdowns (FR-063)
status: To Do
assignee: []
created_date: '2026-09-06 16:53'
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
- [ ] #1 No notification, headline or summary asserts impaired responsiveness from resource measurements alone
- [ ] #2 Severity wording is never used as a proxy for user impact
- [ ] #3 A user-reported slowdown and a measured condition are distinguishable wherever both appear
- [ ] #4 A forbidden-phrase test covers the new class, as the existing ones cover 'crashed' and 'optimize'
<!-- AC:END -->
