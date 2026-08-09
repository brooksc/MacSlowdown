---
id: TASK-71
title: >-
  A repeated-quit episode can never open an incident, so screen 1o is
  unreachable
status: To Do
assignee: []
created_date: '2026-08-09 07:11'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-65.15 while building the repeated-quit incident screen (design 1o). The screen is built, tested and merged — and as shipped **nothing can ever show it**.

`IncidentCondition` has no case for repeated quits. Incidents are opened by resource conditions: CPU saturation, memory pressure, low storage and so on. But 1o's entire premise is **an application failing while the machine is fine** — "Nothing was wrong with CPU, memory or storage while this happened, so this looks like the app failing, not your Mac running out of anything."

So the exact episode the screen exists to explain opens no incident, and the section renders inside an incident's detail that will never occur for that reason. TASK-65.15 could not fix it because `Incident.swift` was owned by another session, and correctly built the presentation rather than silently widening the model.

What is already in place: `LifecycleTracker` is wired into `MonitorStore` (TASK-66), `relaunchPatterns` is exposed, `RelaunchPattern` exists and is tested, and `RepeatedQuitReport` renders sessions, exits, PID pairs and a resource verdict. The evidence is all there; only the trigger is missing.

What is needed: a lifecycle condition the detector can raise, plus the wiring in `MonitorStore`, so a relaunch pattern opens and closes an incident of its own.

Design constraints that must survive, all already honoured by the presentation:

- **Confidence is low and cannot rise.** We see that an app exited, never why. `RepeatedQuitReport` enforces this — a high pattern confidence still yields a low cause confidence.
- **`ResourceVerdict.notObserved` means the resource cause is not ruled out** — "we did not observe a problem, not that there was none". Do not let a new detector path convert that into an assertion of health.
- **Hangs remain undetectable.** `RelaunchPattern.limitation` is the single source for that copy and the view reuses it rather than copying it, so the app and framework cannot drift. FR-046 is deliverable only as repeated-relaunch detection and must never be presented as hang detection.
- An incident opened for this must not claim a quit request was absent on the user's side: we can only prove *we* did not request one, having no process control at all.

Note this interacts with FR-006's sustained-not-transient rule. A single unexpected quit is not an incident; the pattern threshold in `RelaunchPattern` is what makes it one, and the incident's duration is the span of the episode rather than a breach duration. Confirm the shape against FR-011, FR-045 and FR-046 before building.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A repeated-relaunch pattern opens an incident of its own, and closes when the pattern stops, without any resource condition being breached (FR-045, FR-046)
- [ ] #2 The incident appears in the incidents list alongside resource incidents, and opening it shows the repeated-quit evidence rather than an empty resource timeline
- [ ] #3 A single unexpected quit does not open an incident; the threshold that makes a pattern is stated and tested (FR-006)
- [ ] #4 Cause confidence remains low regardless of how strong the relaunch pattern is, and the interface never claims to know why an application exited
- [ ] #5 The screen continues to state that hangs and beachballs are not detectable, from the single shared source rather than a copy (FR-046)
- [ ] #6 Verified on screen with a real repeated-relaunch sequence, or the on-screen criterion is left unchecked with what staging one would take
<!-- AC:END -->
