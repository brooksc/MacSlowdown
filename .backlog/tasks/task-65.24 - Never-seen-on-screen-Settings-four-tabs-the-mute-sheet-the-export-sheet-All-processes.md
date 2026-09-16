---
id: TASK-65.24
title: >-
  Never seen on screen: Settings' four tabs, the mute sheet, the export sheet,
  All processes
status: To Do
assignee: []
created_date: '2026-08-09 23:21'
updated_date: '2026-09-16 03:06'
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

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-16 03:06
---
**Three of the four Settings tabs have now been seen, 2026-09-15** — rendered offscreen via Xcode 27's `RenderPreview` (previews added at the bottom of `SettingsView.swift` under `#if DEBUG`, because the tab views are `private` to that file). No display was taken over.

**Alerts** — renders correctly. Worth noting for [[TASK-108]]: the sensitivity control the owner could not find is prominent and legible, headed "How sensitive should I be?" with a Relaxed / Balanced / Sensitive segmented control, and the explanation states the actual threshold in words ("a condition starts once total CPU stays above 85% of this Mac's capacity for 3 minutes") and is explicit that the dial moves the line itself, not just what is announced. If TASK-108's complaint is discoverability, the defect is not that this control is hard to read — it is that nobody opens this tab. "Quiet during Focus — Held by macOS" states honestly that we cannot read Focus.

**Rules** — renders correctly, including the empty state, which does not imply the feature is broken: "No rules yet. Add an application and the one condition whose alerts you don't want from it." FR-016 amendment 1 is stated in the interface itself ("Every rule names one condition, and no rule silences another… Suppressed slowdowns still appear in Incidents, marked 'not alerted'"). The "Stop telling me…" button is correctly disabled with its reason given rather than left mysteriously grey.

**Privacy** — renders correctly and fits without clipping. Uses the required phrasing exactly: "saved in MacSlowdown's own container, which no other app can read", never "encrypted". "Nothing has left this Mac" leads the tab.

**No defects found in these three.** Recording that explicitly, because "seen and correct" is a result worth having and these criteria have been unchecked for weeks.

**Not yet seen, so still open on this task:** the mute sheet (`MuteAlertsView`, needs a `MonitorStore`), the export sheet (`ExportReportView`, needs an `ExportReportModel` built from an incident), and General. All processes was seen separately and produced [[TASK-117]].

**One caution on method.** Content ran past the bottom of the frame in the Alerts and Rules renders. That is the preview's frame, **not** a defect: every tab is inside a `Form`, which scrolls. Checked before filing rather than after.
---
<!-- COMMENTS:END -->
