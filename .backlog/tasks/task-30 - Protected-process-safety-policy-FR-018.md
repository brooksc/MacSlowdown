---
id: TASK-30
title: Protected-process safety policy (FR-018)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:09'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Protected fixtures cannot be targeted by unsupported control actions
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SafetyPolicy.swift. Non-overridable by construction: the type's only initialiser takes no arguments, so no user preference can weaken it. A test asserts that, and stops compiling if a settings parameter is ever added.

- AC#1 Protected fixtures cannot be targeted by control actions. Three categories: kernel (pid <= 1), critical services (WindowServer, launchd, coreaudiod, loginwindow, Dock and others named explicitly rather than inferred), and anything owned by another uid. Tested against the LIVE process table, asserting every other-uid process is protected -- that is the bulk of the protection and the part that must not regress silently.

A judgement worth recording: protection withholds only activate and revealInFinder, because those are the only actions that touch the process at all. Copy diagnostics and open Activity Monitor stay available for protected processes. Refusing to let a user copy measurements about WindowServer would be safety theatre rather than safety, and it would leave a protected process with nothing useful offered at all. Tested that a protected process still offers something.

The explanation is category-level per FR-018 and offers what remains rather than simply refusing: 'This is part of macOS... MacSlowdown will not act on it, but you can still see what it is doing and open Activity Monitor for more detail.'
<!-- SECTION:NOTES:END -->
