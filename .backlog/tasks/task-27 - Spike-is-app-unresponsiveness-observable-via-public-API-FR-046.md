---
id: TASK-27
title: 'Spike: is app unresponsiveness observable via public API? (FR-046)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 04:17'
labels:
  - spike
milestone: m-2
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Untested Tier 3 metric. Suspect no public API exists. Per spec, omit rather than approximate if unreliable.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ANSWER: a hang that does not exit is UNDETECTABLE from a sandboxed App Store build. FR-046 is only partially satisfiable.

Measured sandboxed, launched via `open`:
- NSRunningApplication exposes no responsiveness state whatsoever. isActive, isHidden, isTerminated, ownsMenuBar, activationPolicy -- a beachballing app reports identically to a healthy one.
- AXIsProcessTrusted = false. Sandboxed apps cannot obtain accessibility trust, so the usual "is this app answering events" route is closed.
- /Library/Logs/DiagnosticReports is unreadable, and ~/Library/Logs/DiagnosticReports redirects into our own container, so the system's own hang reports are unreachable even by absolute path.
- Process lifecycle via sysctl IS available: name, pid, ppid and start time for every process.

FR-046 rescoped rather than dropped. The requirement reads "publicly observable unresponsive state, REPEATED RELAUNCH, or similar failure signals", so the relaunch half is deliverable in full: repeated exit-and-restart is completely visible through lifecycle tracking, including for processes whose CPU we cannot read. Direct hang detection is not deliverable, and per the spec's own instruction the app must omit it rather than approximate.

Created TASK-48 to implement the relaunch-pattern half in m-2. FR-046's "unresponsive state" clause should be treated as unavailable on this platform.

Design implication: screen 1f's "Final Cut Pro stopped responding" cannot be produced. The nearest honest incident is "Final Cut Pro quit and relaunched three times in ten minutes", which is a narrower and different claim -- it says the app failed, not that it froze. The 'pending feasibility' marker on that row should become a scope change, not a maybe.
<!-- SECTION:NOTES:END -->
