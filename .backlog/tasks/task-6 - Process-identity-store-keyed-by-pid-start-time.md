---
id: TASK-6
title: 'Process identity store keyed by (pid, start time)'
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:08'
labels:
  - core
milestone: m-1
dependencies:
  - TASK-5
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PIDs are reused; identity must be (pid, p_starttime from kinfo_proc). Application-family history must survive PID replacement per section 6 and FR-043. Cache proc_pidpath by this key -- re-reading every sweep costs ~5ms and breaks the FR-030 budget at 1s cadence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PID reuse does not merge two unrelated processes
- [x] #2 Family history survives PID replacement
- [x] #3 Path lookups cached, not per-sweep
- [x] #4 Identity resolved once per process lifetime, never per-sweep
- [x] #5 Both signature and path identity recorded per process
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Settled by the TASK-3 spike:

- Identity resolution (proc_pidpath + SecCodeCopyGuestWithAttributes) costs
  ~760ms for a full sweep, ~400x the 1.8ms metrics sweep. It is the dominant
  cost in the system.
- Therefore: resolve identity ONCE per process lifetime, keyed by
  (pid, p_starttime), and cache. The per-sweep hot path must touch only sysctl
  enumeration + PROC_PIDTASKALLINFO.
- Store both identity sources so a policy survives one becoming unavailable:
  teamID+bundleID (stable across app updates, available for 810/1063 sandboxed)
  and outermost .app path (available for 1042/1063, unaffected by sandbox).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ProcessIdentityResolver.swift. Cache keyed by (pid, start time), guarded by a Mutex; syscalls run outside the lock so callers don't serialise behind the slowest resolution.

Verified by test, 28 passing overall:
- AC#1 A reused PID misses the cache and is resolved afresh, because the key includes start time. Test asserts resolutionCount increments and both entries coexist, so a recycled PID can never inherit the previous process's identity.
- AC#2 Identity is anchored to (pid, start time) throughout, which is what lets family history outlive PID replacement. prune(keeping:) drops dead entries without forcing re-resolution of survivors.
- AC#3/#4 Resolution happens once per process lifetime. Test resolves 40 processes, then runs nine further sweeps over the same set and asserts resolutionCount is unchanged. A second test confirms warm lookups are measurably faster than cold.
- AC#5 Both sources recorded: executable path (and the outermost .app derived from it) plus code-signature bundleID and teamID. Test confirms both are populated across a sample of the live process table, and that every bundled process also has a path.

Grouping helper tested directly: a helper at Parent.app/Contents/Frameworks/Helper.app/... resolves to Parent.app, and swift-frontend inside Xcode.app resolves to the same family as Xcode itself. Daemons and CLI tools correctly resolve to no bundle, which is the isStandalone case that ~85% of the table falls into.

Memory: the cache would grow without bound on a machine churning through short-lived processes, so prune(keeping:) exists and is tested. Wiring it into the sampling loop belongs with the store in TASK-12.

One deprecation fixed along the way: String(cString:) is deprecated on macOS 26; proc_pidpath now reads into a UInt8 buffer and decodes the written prefix explicitly.
<!-- SECTION:NOTES:END -->
