---
id: TASK-60
title: Use parent PID to corroborate and extend grouping (FR-003)
status: Done
assignee: []
created_date: '2026-08-08 22:54'
updated_date: '2026-08-09 01:24'
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
- [x] #1 A member whose parent is in the same bundle is promoted from uncertain to certain, and no longer shows an uncertainty marker
- [x] #2 Unbundled processes are attributed to a parent application when one exists, and remain visible individually beneath the aggregate
- [x] #3 A parent link is rejected unless the parent started strictly before the child, so a recycled PID cannot merge unrelated processes
- [ ] #4 Disagreement between path and parent leaves the member uncertain rather than silently choosing one
- [x] #5 A process parented by launchd is unchanged by this, since ppid carries no information there
- [x] #6 Grouping stays reversible: nothing is destroyed and a user correction still wins (FR-039)
- [x] #7 Tests cover launchd parentage, same-bundle corroboration, an unbundled child, a recycled parent PID, and path-versus-parent disagreement
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done. 366 tests passing (from 350). Verified against the live process table, not only fixtures.

On this machine, 844 processes: Warp absorbed 13 shells, ChatGPT 12 backlog processes, Helium 1 native-messaging host. Those 26 rows used to be 26 unrelated entries. Uncertainty markers dropped to 11, all of them crashpad handlers and updaters whose signature genuinely does not match their host bundle.

ParentIndex is the seam. It refuses launchd and the kernel outright, since 82% of the table is parented by pid 1, and it rejects any parent that started after its child — the PID-reuse guard, which matters because macOS wraps allocation at 99999 and this machine had already wrapped inside 12 days of uptime.

Added FamilyMembership.byParent rather than reusing .certain or .uncertain. Lineage is a different kind of evidence from location: the executable lives outside the bundle entirely, and the association rests on who forked whom. It is not uncertainty, so it does not trip hasUncertainMembers, but it is not the same claim as a binary sitting inside the bundle either.

Caught while checking real output: the reason string first read 'started by stable' and 'started by codex', because Warp's executable is named stable and ChatGPT's is codex. It now uses the resolved display name. A label naming the parent's internal binary would have been worse than no label.

Criterion #4 is NOT checked, because the behaviour I built deliberately differs from how I wrote it, and the criterion was wrong. It said disagreement between path and parent should leave a member uncertain. In the real case — SkyComputerUseSe running from Codex Computer Use.app, spawned by ChatGPT — the signature already confirms the path. Another application launching this one is ordinary, not contradictory, and marking it uncertain would put a warning on a correct grouping. What the criterion was protecting against is real and is enforced: a process is never moved into its parent's family, so nothing is silently rechosen. Where the signature CANNOT confirm the path, a parent pointing elsewhere leaves the claim exactly as unconfirmed as before — the parent link only ever promotes, never rescues a claim it disagrees with. Both behaviours have tests.

Unverified: not seen on screen. The grouping is confirmed against live data through a probe, but no view was rendered.
<!-- SECTION:NOTES:END -->
