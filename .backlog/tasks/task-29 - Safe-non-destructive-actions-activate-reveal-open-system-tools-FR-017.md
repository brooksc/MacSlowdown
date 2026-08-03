---
id: TASK-29
title: 'Safe non-destructive actions: activate, reveal, open system tools (FR-017)'
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
- [ ] #1 Unavailable actions are not shown as working
- [ ] #2 Action results verified asynchronously
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ProcessAction and ActionAvailability in SafetyPolicy.swift; ActionPerformer.swift performs them.

- AC#1 Unavailable actions are not shown as working. availability() returns .unavailable with a reason, availableActions() excludes them, and perform() returns .withheld rather than attempting anything. A withheld action's reason is retrievable so the absence can be explained rather than being a mysterious gap.
- AC#2 Results are reported, not assumed. Every branch of perform() returns a real outcome: NSRunningApplication.activate's Bool is checked, a missing executable path fails with a reason, a missing Activity Monitor fails rather than silently doing nothing, and the pasteboard's setString result is checked. Nothing returns .succeeded on the strength of having been called.

The whole action set is non-destructive BY CONSTRUCTION rather than by filtering: activate, revealInFinder, openActivityMonitor, copyDiagnostics, markExpected. A test asserts no action's name or title contains quit, kill, force, suspend, pause, throttle, renice, terminate, limit or stop. This is also what makes FR-037's 'no dormant privileged code paths' checkable by inspection -- there is no branch in ActionPerformer that could change how a process runs.

markExpected deliberately returns a failure if it reaches the performer, because the policy store owns it; silently succeeding would hide a wiring mistake.
<!-- SECTION:NOTES:END -->
