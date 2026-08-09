---
id: TASK-65
title: 'Design conformance: bring the UI to the Claude Design spec'
status: To Do
assignee: []
created_date: '2026-08-09 02:21'
updated_date: '2026-08-09 21:32'
labels:
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Umbrella for the gap between what the app renders today and the design produced in Claude Design. One subtask per design screen.

Source: https://claude.ai/design/p/f2b8c5b9-f801-4287-bea3-d8cdda998adb?file=MacSlowdown+Screens.dc.html ("Mac tray app design screens"). The design document contains two turns: turn 1 is sixteen application screens (1a-1p), turn 2 is four menu bar icon explorations (2a-2d) of which **2d is the recommended spec** and 2a-2c are superseded alternatives. No backlog item was created for 2a-2c deliberately: they are rejected options, not work.

Reference renders live in `design/screens/<id>.png`, one per screen, rendered headlessly from the design HTML at 2x. The design source is static HTML with inline styles and no scripting, so the renders are faithful. Current-state screenshots of the running app are in `screenshots/`.

**How to read the design.** Per the standing rule for this project, the mocks are directional: review structure, information hierarchy, copy intent and feasibility, not the placeholder machine (MacBook Pro M4 Pro, 10 cores, 36 GB) or the invented numbers. Every screen was drawn against the real sandbox constraints — the design consistently shows unattributed system activity, "not measurable" rows, and per-app disk as unavailable — so the constraints in CLAUDE.md are already respected by it. Where a screen appears to require something we proved impossible, that is a finding to raise, not a licence to approximate.

**What is already true.** Six of these surfaces exist in some form: the popover, Now, Apps & Processes, Incidents, Storage and Settings. Eight screens have no implementation at all. Each subtask states which, and names the existing task that delivered the current version so its acceptance criteria are not silently contradicted.

**Scope boundary.** This is a UI conformance effort. It must not introduce process control, per-process disk or wakeups, hang detection, or any other capability the Tier 0 probe ruled out — the design does not ask for them, and FR-037 forbids even dormant code paths.

Do not treat this parent as a single deliverable. Take subtasks individually; several are large enough to split again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every subtask is either completed, or closed with a recorded reason why the design cannot or should not be followed on that screen
- [ ] #2 No subtask introduces a capability ruled out by probe/FINDINGS.md, and any screen that appears to require one is raised rather than approximated
- [ ] #3 Each completed screen is verified on screen against its reference render, not by unit test alone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Status of the umbrella, 2026-08-09.** Every subtask is now built in code. What remains across all of them is **on-screen verification**, which no automated session can supply. Roughly two dozen acceptance criteria are deliberately unchecked for that reason, each with a written step-by-step check in its own task's notes.

Subtasks whose remaining criteria are on-screen only: 65.1, 65.2, 65.4, 65.5, 65.6, 65.7, 65.8, 65.9, 65.10, 65.11, 65.12, 65.13, 65.14, 65.15, 65.16, 65.17, 65.20.

Still genuinely open as work: **65.18** (app icon asset), **65.19** (icon refinement — needs a designer round and the owner's judgement).

**Verify in this order, because the later checks are meaningless before the earlier ones.** TASK-75 first (the window was 1300×3599 on a 1107 pt screen, which hid the sidebar, the segmented control, the search field and the census footer, and almost certainly explains TASK-51.1's blank Incidents pane). Then TASK-51.1. Then TASK-65.20 (first run, which needs its state reset before launching). Everything else can be checked in any order once the window is the right size.
<!-- SECTION:NOTES:END -->
