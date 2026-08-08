---
id: TASK-60
title: Use parent PID to corroborate and extend grouping (FR-003)
status: To Do
assignee: []
created_date: '2026-08-08 22:54'
updated_date: '2026-08-08 22:55'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured, see probe/FINDINGS.md "Parent PID as a grouping signal". 831 processes, sandboxed.

`ppid` comes free with the sysctl enumeration and we already carry it on ProcessRecord, but nothing uses it. The question was whether it could group processes better than the executable path. It cannot replace the path — 82% of the table is parented by launchd, because macOS launches helpers through launchd and XPC rather than by forking from the application. Of 166 processes living in a `.app`, 107 have launchd as their parent.

It does add two things the path cannot:

1. Corroboration, which removes uncertainty markers. For 56 of 166 bundled processes the parent is in the same bundle. That is independent evidence for what the path already claims, and is exactly what is needed to promote a member from uncertain to certain. Today those rows carry a question mark saying the signature could not confirm the grouping; a parent link in the same bundle can confirm it instead.

2. Attribution the path misses entirely. 25 processes live in no bundle but were spawned by an application: 14 zsh under Warp, 11 backlog under ChatGPT, chrome-native-ho under Helium. Today each is its own standalone family, so a Warp session with fourteen shells appears as fourteen unrelated rows. Grouping them under the responsible application is both more accurate and more useful — "Warp is using 40% across 14 shells" is the sentence a user needs.

Design question this raises, and it is a real one: is a shell you started yourself part of the terminal's usage, or its own thing? Grouping zsh under Warp attributes work the user initiated to the app that hosts it. That is the honest answer to "what is making my Mac slow", but it should remain visible as a sub-list rather than silently absorbed — FR-003 keeps individual PID records beneath the aggregate.

Hazard: ppid is a bare pid with no start time. A recycled parent pid would link a process to an unrelated one. No impossible parents appeared in the probe snapshot, but the hazard is real over time. Guard: a real parent must have started strictly before its child; reject any parent whose start time is later. Same PID-reuse rule that governs identity everywhere else.

Edge case worth preserving rather than resolving: SkyComputerUseSe runs from Codex Computer Use.app but was spawned by ChatGPT. Both attributions are defensible. Disagreement between path and parent should keep the member uncertain, not pick a winner silently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A member whose parent is in the same bundle is promoted from uncertain to certain, and no longer shows an uncertainty marker
- [ ] #2 Unbundled processes are attributed to a parent application when one exists, and remain visible individually beneath the aggregate
- [ ] #3 A parent link is rejected unless the parent started strictly before the child, so a recycled PID cannot merge unrelated processes
- [ ] #4 Disagreement between path and parent leaves the member uncertain rather than silently choosing one
- [ ] #5 A process parented by launchd is unchanged by this, since ppid carries no information there
- [ ] #6 Grouping stays reversible: nothing is destroyed and a user correction still wins (FR-039)
- [ ] #7 Tests cover launchd parentage, same-bundle corroboration, an unbundled child, a recycled parent PID, and path-versus-parent disagreement
<!-- AC:END -->
