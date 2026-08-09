---
id: TASK-65.15
title: 'Screen 1o — Repeated-quit incident: evidence is lifecycle events, not curves'
status: To Do
assignee: []
created_date: '2026-08-09 02:25'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1o.png`. Existing implementation: `LifecycleTracker` and relaunch-pattern detection exist (TASK-48); there is no incident presentation for them.

**What the design specifies**

Headline: "Final Cut Pro quit unexpectedly three times in 12 minutes". Opening: "Each time it reopened by itself within about a minute. Nothing was wrong with CPU, memory or storage while this happened — so this looks like the app failing, not your Mac running out of anything."

- **What we saw** — "Measured — launches, exits and PID changes". A session bar chart rather than a metric curve, showing sessions that ended and the one still open, with quit markers at 2:07, 2:12, 2:16 and a legend distinguishing "Session that ended", "Session still open", "Exit without a quit request".
- An event list with the PID evidence spelled out: "2:07 Exited · PID 2841 disappeared · relaunched 41 s later as PID 2896" and so on, ending "2:19 Running normally since — 4 days without another quit".
- **What we found** — Measured (three exits, each followed by a relaunch under a new PID, none following a quit request from the user or from us). Calculated (session lengths 4, 5 and 3 minutes; memory reached 6.8 GB before the first exit but only 2.1 GB before the third, "so it wasn't growing towards a limit" — evidence used to *rule out* a hypothesis). "Likely, **low** confidence" (repeated quits usually mean the app hit the same problem each time — "We have no way to see why it exited, only that it did"). Ruled out (not a resource problem).
- **What we can and can't say** — the explicit statement that we can see an app quit and return because process lifecycle is visible, but "We can't tell you an app froze or beachballed — macOS reports a hung app exactly the same way it reports a healthy one, so we'd rather say nothing than guess."
- **What you can do** — Open Console ("macOS writes a crash report each time. We can't read them; Console can."), Check for an app update, Copy diagnostics, "Tell me if it happens again".

**Direct match to a proven constraint**

CLAUDE.md is unambiguous that application hangs are undetectable and that FR-046 is deliverable only as repeated-relaunch detection. This screen is exactly that delivery, and it says so to the user in as many words. It is the model for how a ruled-out capability should appear in the product rather than being quietly absent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A repeated-quit incident renders as lifecycle evidence -- sessions, exits and PID changes -- rather than as resource curves
- [ ] #2 Each exit is evidenced by the PID that disappeared and the PID it relaunched as, with the interval between them
- [ ] #3 The incident states that resource conditions were normal, using that to rule out a resource cause rather than leaving it unsaid
- [ ] #4 Confidence is labelled low where the cause cannot be seen, and the screen states plainly that we cannot see why an app exited (FR-013)
- [ ] #5 The screen states that hangs and beachballs are not detectable and does not imply otherwise (FR-046)
- [ ] #6 Suggested actions point to tools that can see what we cannot, without claiming we read crash reports
- [ ] #7 Verified on screen against design/screens/1o.png with a real repeated-relaunch sequence
<!-- AC:END -->
