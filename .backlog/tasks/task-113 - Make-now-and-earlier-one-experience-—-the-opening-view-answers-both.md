---
id: TASK-113
title: Make "now" and "earlier" one experience — the opening view answers both
status: In Progress
assignee: []
created_date: '2026-09-06 16:54'
updated_date: '2026-09-09 17:39'
labels:
  - ui
milestone: m-3
dependencies: []
priority: high
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both reviews converged here. The first question on opening the app is usually **"is it still happening?"** and the second is **"what happened earlier?"** — and those belong in one place, not on two screens joined by navigation.

**What the opening view should answer, in one glance:** the current observed condition and how long it has held; whether monitoring actually covered the period the user is asking about; and the last significant episode. Incidents become the *detail behind* that summary rather than a separate destination.

This absorbs S-6 (`scenarios.md`), which is what almost every visit looks like and has never been designed for. The requirement it has to satisfy is that reassurance be worth something: **a green light that would look identical if we had stopped working an hour ago is worth nothing on the day it says something else.** "No sustained condition observed while monitoring since 11:22" is defensible; "nothing is wrong" is not, given what we cannot see.

**Coverage is the new concept.** History has to remain accessible even where nothing crossed a threshold, and the user must be able to tell "we watched and nothing happened" from "we were not watching". That is a real design and data question, not a copy change.

One caution from the second review, worth keeping: the goal is a **fast, trustworthy answer when opened** — not to encourage daily inspection of a healthy machine. Do not build for engagement.

Supersedes the framing in `design/live-surfaces.md`, which argued the same point from the honesty side. Needs a design pass; see the Claude Design brief.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The opening view states the current condition, how long it has held, and the last significant episode without navigation
- [ ] #2 A user can distinguish 'watched, nothing crossed the line' from 'not watching'
- [ ] #3 Recent history is reachable even where no condition was ever detected
- [ ] #4 No surface claims the machine is fine in absolute terms
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Started 2026-09-09**, in a worktree, against the finished design.

The specification is `design/screens/5a.png` (nothing wrong), `5b.png` (condition present), `5c.png` (coverage gap) and `6c.png` (30-day scale). Turn 5 answered the two things the task could not: what the healthy state should contain, and how coverage should be drawn.

**Coverage is the new and genuinely hard part**, and the design settled its shape: a strip under the chart rather than a badge, because "we were watching" is a claim about a *period* and a period needs a length — a badge can only say yes, which is the useless green light. A gap does not heal, and sleep, shutdown and the retention boundary are all drawn as gaps with their reason.

5c's three-state grammar is the acceptance criterion in prose: watched-and-nothing-crossed is a real result the headline may state; watched-and-something-crossed puts the episode on the trace; not-watched makes no claim in either direction.

Also settled by the design and worth recording: **the sidebar loses Now and Incidents.** Incidents stop being a destination — the healthy state shows the last one inline and the live state shows the current one. The argument is FR-060: one count, in one place, so a summary and a list cannot disagree about the same episode. That is a bigger structural change than this task originally assumed.

Built on branch `worktree-agent-ad803e36e23de73f4` (not merged).

**What exists now.** A new `Overview` screen is the window's opening section (designs 5a/5b/5c and the 30-day scale of 6c). It carries: a measurement-first headline in three states, a coverage strip over the window, the retained CPU curve on its own axis, a "Right now" card, the last condition recorded inline with links into Incidents, the contributor table (the *same* `ContributorRow` the Now screen uses) while a condition is open, and the two controls only the person can operate — "It feels slow now" (FR-064) and "Heavy load is expected for X" (FR-016).

**The coverage data model.** `Metrics/Sources/Coverage.swift` — a `CoverageLog` of `CoverageInterval`s (`began`, `lastObserved`, `precededBy`), with gaps derived as the complement. Recorded from the sampling pass at the same `sampledAt` the retained series uses, extended while readings arrive within `tolerance(cadence:) = max(cadence*4, 20 s)`, and persisted schema-versioned to `coverage.json` (`CoverageStore`), throttled to one write a minute and forced on stop and on sleep. Retention is pruned on every sample; pruning stamps the truncated interval `.beyondRecord` so the 30-day strip stops at the boundary rather than appearing to begin at a quiet moment.

Gap reasons are established, never guessed: `appNotRunning` (the first observation of a launch follows the gap by construction), `systemAsleep` (only from an observed `NSWorkspace.willSleepNotification`), `noReadings` (the honest fallback), `beyondRecord`. There is deliberately no "relaunched after an update" — 5c's wording is a fact no public API gives us.

A single reading claims **no** stretch of coverage, so a crash between flushes reads back as a gap: the record under-claims rather than over-claims, which is the only tolerable direction for this one.

**The deviation the product owner should confirm.** Designs 5a/5c draw a CPU trace across the whole day. `MetricsHistory` retains ~15 minutes and is deliberately not persisted, so a day-long curve could only be invented. The coverage strip covers the whole window (coverage is a few timestamps a day and is kept for the full retention period); the curve sits in its own panel under it, stating the span it covers. `OverviewPresentation.traceScopeNote` is the sentence.

**Not done.** 6c's "Your reports" panel (reports matched against conditions) is left to TASK-110, which owns `SlowdownReport*`; `OverviewPresentation.Inputs.reportCount` exists and is unused. `Now` and `Incidents` remain sidebar destinations — Overview leads and links into them rather than replacing them, which is a call worth confirming.

**Tests.** 15 in `Metrics/Tests/CoverageTests.swift`, 13 in `MacSlowdown/Tests/OverviewTests.swift`, plus the Overview added to `WindowSizingTests.everyPaneIsBounded`. Full run 1227 passing; the only failure was `CPUWorkloadTests.workloadIsAttributed`, which passes in isolation (machine-measuring test, busy machine).

**Every acceptance criterion is left unchecked: nothing has been seen on screen.** No session looked at this window, and CLAUDE.md is explicit that a UI criterion is not met by a passing test.

**On the sidebar losing Now and Incidents.** The earlier note records that the design settled this. It is *not* done here, deliberately: Now is the only home for the FR-002/FR-032 freshness surfaces (the catching-up banner, per-metric ages, the enumeration-failure banner), and Incidents is the only route to the incident detail. Removing both destinations before the Overview absorbs those surfaces would leave built capability unreachable, which is the defect `probe/seam-reachability.sh` exists to catch. So Overview leads and links into them, and folding them in is the next step rather than something this branch guessed at.
<!-- SECTION:NOTES:END -->
