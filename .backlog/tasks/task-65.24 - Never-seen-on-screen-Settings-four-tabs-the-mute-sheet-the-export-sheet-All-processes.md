---
id: TASK-65.24
title: >-
  Never seen on screen: Settings' four tabs, the mute sheet, the export sheet,
  All processes
status: To Do
assignee: []
created_date: '2026-08-09 23:21'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recorded so the gap is explicit rather than assumed closed. The 2026-08-09 on-screen session audited Now, Apps &amp; Processes (Apps scope, with the inspector), Incidents (list and detail inspector), Storage, and the menu bar icon. **These were not reached:**

| Surface | Design ref | Why not |
|---|---|---|
| Settings — General | 1i | Never opened. The app menu carries `Settings…` (menu bar item 2, item 4) but the app was not frontmost and the session ran out of time. |
| Settings — Alerts | 1i | same |
| Settings — Apps (per-app rules, suppressed-detections sheet) | 1j | same. Note TASK-76's criterion #3 is waiting on exactly this. |
| Settings — Privacy (retention picker, delete-all, stored-data sheet) | 1j | same. TASK-79's on-screen half waits on it. |
| Mute alerts sheet | 1g | Confirmed to *open* — `count of sheets of window 1` returned 1 after invoking ⌥⌘M — but the capture caught the wrong window and it was never seen. |
| Export a report, with redaction preview | 1k | Never opened. The `Export…` button is present in the incident detail. |
| Apps &amp; Processes — All processes scope | 1m | The segmented control reads "All processes · 735" and switches, but the list itself was never looked at. Its "Show unmeasurable" toggle likewise. |
| Empty search in Apps | 1p | Never exercised. |
| First run | 1g | Not re-checked after TASK-65.20; needs `firstRun.completed` deleted before launching. |

**Two small defects seen in passing and worth fixing wherever they belong:**

1. **The incident timeline's axis labels overlap.** In the detail inspector the two markers under the sparkline rendered as `firstbreach` — "first" and "breach" collided. Seen at a 460 pt inspector width; may be width-dependent.
2. **A command-named subject reads as an English word.** The detail headline was literally *"yes quit unexpectedly 30 times in 1 minute"* — the `yes` shell utility. Lowercase command names at the start of a sentence need a treatment (quoting, a "the process" prefix, or monospacing) so they read as identifiers. This is the same family as FR-002's rule about never showing a `p_comm` fragment as if it were a name, and is being handled for the subject specifically under TASK-82 — but the general rule is unowned.

Do not close this task by looking at one surface. Each row above needs its own look against its design reference, and each subtask that depends on it (TASK-76 #3, TASK-79's on-screen half, TASK-65.9, 65.10, 65.11, 65.13, 65.16) should have its criterion checked at the same time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All four Settings tabs are looked at against 1i and 1j, and TASK-76 #3 and TASK-79's on-screen criterion are resolved at the same time
- [ ] #2 The mute sheet, the export sheet with its redaction preview, and the stored-data and suppressed-detections sheets are each seen
- [ ] #3 The All processes scope and the empty-search state are seen against 1m and 1p, including the Show unmeasurable toggle
- [ ] #4 First run is re-checked after TASK-65.20 with firstRun.completed cleared beforehand
- [ ] #5 The timeline axis label overlap is fixed or recorded as width-dependent with the width it appears at
- [ ] #6 A rule exists for rendering command-named subjects so a lowercase command does not read as an English word
<!-- AC:END -->
