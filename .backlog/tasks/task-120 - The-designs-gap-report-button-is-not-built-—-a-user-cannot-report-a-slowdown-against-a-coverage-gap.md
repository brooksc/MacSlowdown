---
id: TASK-120
title: >-
  The design's gap-report button is not built — a user cannot report a slowdown
  against a coverage gap
status: To Do
assignee: []
created_date: '2026-09-17 02:31'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: high
type: feature
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-09-16 by comparing the built Overview against design **5c**, screen by screen.

The built coverage record follows 5c closely — the headline pattern, the explanatory paragraph, the hatched strip, and the three-state legend are all there, in some places word for word. **One element of 5c is missing entirely**: the button beneath the strip.

Design 5c:

> **[ Something happened then ]**  Files a report against the gap, so at least the time is recorded.

There is no occurrence of that button, or anything playing its part, anywhere in the source. The only report gesture built is `SlowdownReportPresentation.reportNowTitle` — **"It feels slow right now"** — which is present-tense only, on the Overview and in the menu bar popover.

**Why this matters more than a missing button.** It is the bridge between two things the product already treats as central:

- **S-2** is the scenario where the episode is over before anyone looks, and the coverage record exists precisely so the user can ask "what happened at 11:22". When the answer is "we weren't watching", 5c's button is the one action that turns a dead end into data.
- **FR-064** is the governing decision that the user telling us it felt slow is the next substantive feature, because a measured condition is not an experienced slowdown. A gap is the case where we have *no* measurement at all, so the user's report is not merely the better evidence — it is the only evidence there will ever be.

**The engine is already there.** `SlowdownReportTiming.recently(secondsAgo:)` exists, `SlowdownReport.make` accepts it, and a scenario test already asserts that a retrospective report is dated from the experience rather than the filing. So this is a built-but-unreachable capability of the kind `probe/SEAM-AUDIT.md` tracks, not new machinery — what is missing is the affordance and the plumbing from a specific gap to `secondsAgo`.

**One design question to settle before building.** 5c's button files against *the gap as a whole* ("so at least the time is recorded"). The retained evidence for such a report is, by definition, nothing — there were no readings. So the report must be honest that it has no samples, which `SlowdownSampleCoverage.hasSamples` already expresses and a scenario test already covers. Worth confirming the copy says so rather than presenting an empty evidence section.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A gap on the Overview coverage strip offers a way to report that something happened during it
- [ ] #2 The resulting report is dated from the gap rather than from the moment it was filed, using the existing recently(secondsAgo:) timing
- [ ] #3 The report states plainly that no readings were retained for that period, rather than showing an empty evidence section
- [ ] #4 It is counted in SlowdownDetectionOverlap as a report without a coincident detection, since by construction there can be no detection
- [ ] #5 Seen on screen — the button, and the report it produces — not inferred from a passing test
<!-- AC:END -->
