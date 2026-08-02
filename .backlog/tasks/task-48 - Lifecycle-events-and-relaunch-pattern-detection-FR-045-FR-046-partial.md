---
id: TASK-48
title: 'Lifecycle events and relaunch-pattern detection (FR-045, FR-046 partial)'
status: Done
assignee: []
created_date: '2026-08-02 04:17'
updated_date: '2026-08-02 06:54'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replaces the unresponsiveness half of FR-046, which TASK-27 measured as unavailable: no public API exposes hang state, and the system's hang reports are unreadable from the sandbox.

What IS deliverable, and fully: process lifecycle. sysctl gives name, pid, ppid and start time for every process including ones whose CPU we cannot read, so launches, exits, PID replacement and repeated relaunch are all observable.

Scope:
- Record lifecycle events by diffing consecutive snapshots on (pid, start time).
- Detect a relaunch pattern: the same executable identity exiting and restarting repeatedly within a window.
- Attach these to incidents so a contributor that vanished before the user looked is still explained (FR-045).

Do NOT claim hang detection. An app that freezes without exiting is invisible to us, and saying otherwise would be an unsupported claim under FR-038.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Launches, exits and PID replacements are recorded with timestamps
- [ ] #2 A relaunch loop in a test fixture appears as related events, not unrelated incidents
- [ ] #3 Uncertain attribution is labeled
- [ ] #4 No UI or copy anywhere claims an app was unresponsive or hung
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LifecycleEvents.swift: LifecycleEvent, RelaunchPattern, LifecycleTracker.

- AC#1 Launches and exits derive from diffing consecutive snapshots on (pid, start time), each timestamped. Because identity includes start time, a PID reused by a different process correctly reads as one exit plus one launch rather than as continuity -- tested directly.
- AC#2 Repeated exits of one command group into a single RelaunchPattern rather than three unrelated events. Tested that three exits become one pattern, that an ordinary single restart does not qualify, that exits outside the window are excluded, that different applications form separate patterns, and that launch events are not miscounted as exits.
- AC#3 Uncertain attribution is labeled. p_comm is truncated to 16 bytes by the kernel, so a name at that limit could be several different executables; those patterns carry .low confidence rather than .moderate. Tested with a short name and a truncated one.
- AC#4 No copy claims a hang, asserted rather than reviewed. Event descriptions and pattern summaries are checked against: hung, hang, froze, frozen, unresponsive, beachball, crashed, stopped responding. Summaries also avoid 'because' and 'caused', since we observe that a process exited but never why.

RelaunchPattern.limitation states the boundary explicitly and names the thing we cannot detect: 'We cannot see why it exited, and we cannot tell whether an app has stopped responding -- macOS reports a stalled app exactly as it reports a healthy one.' A test asserts it names the hang case, so the caveat cannot quietly lose the part that matters.

One deliberate guard: if either snapshot's enumeration failed, no events are emitted at all. Diffing a full table against an empty one would report every process on the machine as having exited, which would be catastrophic nonsense and precisely the FR-002 failure TASK-49 exists to prevent.
<!-- SECTION:NOTES:END -->
