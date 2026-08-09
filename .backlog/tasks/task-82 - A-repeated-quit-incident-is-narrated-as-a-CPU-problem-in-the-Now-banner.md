---
id: TASK-82
title: A repeated-quit incident is narrated as a CPU problem in the Now banner
status: To Do
assignee: []
created_date: '2026-08-09 22:54'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed on screen 2026-08-09 within minutes of TASK-71 landing, on a real incident (`screenshots/verify2/02-now.png`).

The banner headline read **"Repeated unexpected quits for 3 minutes, 15 seconds"** and the body underneath read:

> Calculated. 38% of busy CPU could not be attributed to any process we are permitted to measure…
> Likely, moderate confidence. Xcode was the largest measurable contributor while this was happening, peaking at 380% of one core…

That is a CPU narrative attached to a lifecycle incident. TASK-71's premise is precisely the opposite — 1o exists to say *an application is failing while the machine is fine* — and the task explicitly required that a new detector path must not convert `ResourceVerdict.notObserved` into an assertion either way.

TASK-71 did handle this, but only in `IncidentDetailView`, which "suppresses the unattributed-CPU narrative for an incident with no resource condition". The **banner** goes through `IncidentSummarizer.summarize`, which was not changed. So the same incident is described correctly on one screen and misleadingly on another — and the banner is the one the user sees first.

Two related observations from the same run, both worth deciding on rather than assuming:

- **"Bring Xcode forward" / "Bring claude forward" was offered as the action.** For a repeated-quit episode the leading CPU contributor is not the failing application, so the action names the wrong app. The relevant subject is the command that kept exiting.
- **The incident opened within roughly one minute of launch, twice, on an ordinary developer machine** (once attributed to Xcode, once to `BackgroundShortc…`). Three exits and matched relaunches inside the tracker's 15-minute window is easy to hit while builds are running. Whether that is a true positive or too eager a threshold is a judgement worth making against FR-006 with real observation, not by adjusting a number until it feels right. Record the reasoning either way.

Also seen in the incidents list: the row read **"Repeated unexpected quits — BackgroundShortc…"**. TASK-81 wired `ProcessNaming.nameIsTruncatedCommand` into the two inventory tables but not into incident rows, so a `p_comm` fragment is presented here as if it were the application's name (FR-002).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An incident whose only condition is repeated quits is not described in terms of CPU attribution on any surface, including the Now banner (FR-013, FR-038)
- [ ] #2 The summariser and the incident detail derive that decision from one shared rule, so the two surfaces cannot disagree again
- [ ] #3 notObserved is still never converted into an assertion that resources were fine
- [ ] #4 The banner's action names the application that was quitting, not the largest CPU contributor
- [ ] #5 The repeated-quit threshold is re-examined against FR-006 with the two real episodes observed on 2026-08-09, and the conclusion is recorded whether or not the threshold changes
- [ ] #6 An incident row shows a p_comm-truncated command as such rather than as the application's name (FR-002)
<!-- AC:END -->
