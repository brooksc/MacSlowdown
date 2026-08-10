---
id: TASK-84
title: >-
  The repeated-quit condition fires on ordinary process churn — 28 subjects
  qualify in one 15-minute window
status: In Progress
assignee: []
created_date: '2026-08-09 23:56'
updated_date: '2026-08-10 01:34'
labels:
  - core
  - decision
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured while re-examining the threshold for TASK-82 criterion #5. **This is not a threshold that is slightly too eager. The predicate is wrong, and no value of the count fixes it.**

## What was measured

An approximation of `LifecycleTracker` at a 2 s cadence over one **901 s** window (the tracker's own 900 s window), on the same developer Mac where both real false positives were seen on 2026-08-09. Snapshots of the full process table, disappearances grouped by basename truncated to 16 bytes, exactly as `p_comm` is.

**28 commands reached `minimumExits = 3`** in that single window (26 of them own-uid). Discounting `ps`, which was the sampler itself, 27.

| command | exits | exits with a later relaunch | median session life |
|---|---|---|---|
| swift-frontend | 112 | 110 | 2 s |
| swift-plugin-ser | 63 | 62 | 2 s |
| mdworker_shared | 61 | 61 | 51 s |
| yes | 60 | 52 | 3 s |
| zsh | 42 | 39 | 13 s |
| xcodebuild | 19 | 18 | 9 s |
| ugrep, SWBBuildService, head | 16-17 | 15-16 | 9-11 s |
| … 19 more at 3-12 exits | | | |

## What this means for the three dials

1. **Raising `minimumExits` does not work.** `yes` reached 60 exits and `swift-frontend` 112. A threshold high enough to exclude them excludes every genuine case FR-046 exists for — a user relaunching a failing app three or four times before giving up.
2. **Requiring a matched relaunch barely helps: 23 of 28 survive.** A build spawns the same compiler over and over, so an exit is almost always followed by another launch of the same command. This was the obvious fix and the measurement kills it.
3. **Requiring a median session lifetime ≥ 60 s leaves 3 of 28** — `caffeinate`, `ibtoold`, `sleep`. Still false positives, but a 90% reduction.
4. **Applying FR-046's own noun leaves 0.** Exactly one of the 28 lives in a `.app` bundle: MacSlowdown itself, being rebuilt. Every other subject is a compiler, a CLI tool, a daemon or a helper.

## Why this is severe, not cosmetic

`SystemObservation.breaches(.repeatedApplicationQuits)` is true if *any* finding is inside the quiet period, and the quiet period is refreshed by the next piece of churn. On a Mac that is building, the condition therefore **breaches continuously** — one incident that opens within a minute and never closes, whose subject is whichever compiler happens to have the highest exit count. That is exactly the two episodes observed on 2026-08-09.

## The FR-006 argument

TASK-71 argued that `minimumExits = 3` is FR-006's sustained-not-transient guard, and that a second clock would count the same evidence twice. The second half of that is right. The first half defends against the wrong transient. FR-006's acceptance criterion is "no alert for a single transient spike **shorter than the configured duration**" — one event that did not last. The observed false positives are not one event that was too short; they are **many events that were each entirely normal**. Multiplicity is not duration, and three normal exits do not compose into one abnormal episode.

## What FR-046 actually asks for

The statement is "repeated **application** failure". The objective is "explain **application** failures that occur without aggregate resource saturation". The outcome is "distinguish a repeatedly failing **application** from a system-wide CPU or memory incident". The detector does not implement that noun; it implements "three processes sharing a 16-byte `p_comm` disappeared inside 15 minutes".

## The decision to make

Restrict the condition's subject to a process that resolves to an outermost `.app`. On the measured window that produces **zero** findings and loses nothing real.

It is a product decision because it has a genuine recall cost — a daemon or a CLI tool that really is failing repeatedly would no longer open an incident — and because it is not free to build: `LifecycleTracker` works from `ProcessSnapshot.records`, which carry no executable path. Identity resolution is cached separately by `(pid, start time)` and would have to be handed in, which is wiring in `MonitorStore`.

## Separately: "unexpected" is a claim we cannot support

`LifecycleEvent.exited` is derived from a process vanishing between two snapshots. There is no exit status, no signal, and crash reports are unreadable under the sandbox (FR-046's own notes). A clean exit and a crash are identical to us. `IncidentCondition.repeatedApplicationQuits.label` says "Repeated unexpected quits" and the report copy says "quit unexpectedly". FR-046 forbids claiming an application was unresponsive on exactly this reasoning, and FR-002 forbids stating what was not measured. Design 1o's copy is the product owner's, so this is raised rather than changed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision is recorded on whether the repeated-quit subject is restricted to processes resolving to an application bundle, with the recall cost stated
- [ ] #2 If restricted, the measurement is repeated on a building developer Mac and the qualifying-subject count is recorded
- [ ] #3 A decision is recorded on the words "unexpected" and "quit unexpectedly", which assert an exit status we cannot read (FR-002, FR-046)
- [ ] #4 Whatever is decided, the predicate and its evidence are stated in LifecycleTracker's own documentation rather than in a task note
<!-- AC:END -->
