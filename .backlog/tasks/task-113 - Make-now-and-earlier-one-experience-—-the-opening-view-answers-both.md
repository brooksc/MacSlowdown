---
id: TASK-113
title: Make "now" and "earlier" one experience — the opening view answers both
status: To Do
assignee: []
created_date: '2026-09-06 16:54'
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
