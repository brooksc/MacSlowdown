---
id: TASK-99
title: >-
  A scheduled scan is not an application quitting: the third hole in
  repeated-quit
status: In Progress
assignee: []
created_date: '2026-08-31 18:16'
updated_date: '2026-08-31 18:16'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on 2026-08-31 in the product owner's own `incidents.json`, not by reasoning about the code. Ten incidents recorded across nine days; **every one was `repeatedApplicationQuits`, and every one was false.** Not a single CPU, memory, thermal or storage incident in the file.

| When | Subject | Exits | Cause |
|---|---|---|---|
| Aug 23 | `swift-frontend`, `clang` | 419, 141 | fixed by TASK-86 |
| Aug 24 (×3) | `1Password-Browse…`, `Brave Browser He…` | 8–22 | fixed by TASK-86's strict revision |
| Aug 24 | `git` | 4 | fixed by TASK-86 |
| Aug 25, Aug 27 | `XProtectRemediat…` | 4, 34 | **this task** |
| Aug 26 | `MacSlowdown`, `Signal` | 6, 3 | our own rebuilds; genuine sessions |

**Why the XProtect case defeats every path rule we have.** `XProtectRemediatorAdload`, `XProtectRemediatorBundlore` and about 32 siblings live at `/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/`. That is genuinely the outermost bundle's main-executable directory, so they satisfy `isApplicationMainExecutable` honestly — on disk they *are* applications. macOS runs them briefly as a scheduled malware scan. And `p_comm`'s 16 bytes truncate every one to the same `XProtectRemediat` fragment, so 34 different programs running once each were counted as one thing quitting 34 times.

**The fix is duration, not provenance.** FR-046 is about an application the user was working in going away and coming back. A program that lived four seconds was never a session. `LifecycleTracker.minimumSessionLifetime` (default 60 s) requires the exiting process to have been running that long, measured from `(pid, start time)` — which every event already carries, so it costs arithmetic and no new plumbing. An exit we cannot date is excluded rather than assumed.

This is FR-006's sustained-not-transient rule finally applied to the right axis. The three previous attempts each measured something else: TASK-71 the exit count, TASK-84 whether the process lived in a `.app`, TASK-86 whether it was that bundle's main executable. All three were about *what* exited; none about *how long it had been there*.

**The false incidents have been cleared** from the container, backed up first to `incidents.json.false-2026-08-31.bak` in the same directory. The product owner's standing instruction is that bad data gets fixed before they are asked to test, rather than explained to them afterwards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A scan's short-lived processes form no pattern, however many of them there are
- [x] #2 An application quit and reopened across real sessions still forms one
- [x] #3 An exit with no usable start time is excluded rather than assumed to be a session
- [x] #4 The boundary is asserted either side of the configured minimum, so the default cannot move silently
- [x] #5 The container's false incidents are cleared and the previous file preserved
- [ ] #6 Verified on the real machine: a full XProtect scan produces no incident
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What changed

`LifecycleTracker.minimumSessionLifetime`, default 60 s, applied in `relaunchPatterns`. `sessionLifetime(of:)` reads `(pid, start time)` off the event — `kp_proc.p_starttime` is microseconds since the epoch — and returns nil where the kernel gave us nothing or the arithmetic is negative. Nil excludes the exit: an exit we cannot date is one we cannot call a session, and this predicate has been wrong three times by admitting the uncertain case.

## Four tests, plus a fixture correction that matters

`SessionLifetimeTests`: 34 scanners at four seconds each form nothing; three real sessions at five minutes each still form a pattern; the boundary is asserted a second either side of the configured minimum so the default cannot move silently; an undated exit is excluded.

The existing fixtures used `startTime: UInt64(index)` — 0, 1, 2 microseconds after 1970 — which made every fixture process either undated or three decades old. They now use a start an hour before the test origin, which is what a session actually looks like.

## A separate, intermittent test defect found while running this

`IncidentSummaryTests.headlineIsInformative` was failing, and not because of this change. When I made that suite's fixture default to an *open* incident (2026-08-26, so its live-attribution tests would exercise a legitimate path), this test's duration became "now minus 2023" — tens of thousands of hours — and whether the formatter also printed a minutes component depended on the time of day. It passed on the 26th by luck. It now uses a closed incident and asserts the fixture's own six minutes, which is the only kind of duration a duration assertion can be pinned to.

## Not verified

AC #6. The next XProtect scan on this machine is the real check, and it is not something to schedule — it wants noticing over the coming days.
<!-- SECTION:NOTES:END -->
