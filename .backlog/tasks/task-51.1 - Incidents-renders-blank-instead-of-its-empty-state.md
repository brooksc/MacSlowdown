---
id: TASK-51.1
title: Incidents renders blank instead of its empty state
status: In Progress
assignee: []
created_date: '2026-08-09 02:14'
updated_date: '2026-08-09 03:35'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-51
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression against TASK-51's acceptance criterion #4, which was implemented and verified on screen.

Observed on macOS 27 in the built Debug app with no incidents recorded: selecting Incidents in the sidebar shows the navigation title "Incidents" and **nothing else** — an entirely blank detail pane. Captured twice, in separate runs, roughly two seconds after selection, so it is not a transition artefact. Screenshot: `screenshots/04-incidents.png`.

The code looks correct. `MacSlowdown/Sources/IncidentsView.swift:36-45` defines a `ContentUnavailableView` reading "No slowdowns recorded" plus copy that distinguishes monitoring-running from monitoring-stopped, and `body` selects it whenever `all.isEmpty`. So the branch is being taken and the view is not appearing, rather than the copy being missing. Suspects worth checking first: the `Group` wrapper combined with `.navigationTitle` and the always-attached `.inspector(isPresented:)` at lines 26-31, and whether `ContentUnavailableView` renders inside a `NavigationSplitView` detail column on this OS version.

Why it matters beyond cosmetics: a blank pane is exactly the failure mode TASK-51's criterion was written to prevent. "Nothing here" reads as "the app is broken" — and the user cannot tell the difference between no incidents and no monitoring.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With no incidents recorded, the Incidents pane shows the empty-state heading and description on screen in the running app
- [ ] #2 The empty state still distinguishes monitoring-running from monitoring-stopped, as TASK-51 criterion #4 requires
- [ ] #3 The pane is checked both with and without an open incident, so the fix does not break the populated list
- [ ] #4 The cause is recorded in the task notes, so the next person does not re-derive why a correct-looking view rendered nothing
- [x] #5 A test covers the empty branch to whatever extent SwiftUI allows, with anything only verifiable on screen stated as such
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Not reproducible offscreen — read this before re-deriving it

**The blank pane is real.** `screenshots/04-incidents.png` was scanned
programmatically: every sampled pixel of the detail column below the toolbar
(x 526–2616, y > 87) is pure white. Only the toolbar title row and the window
edge carry ink. It is not a faint-grey-on-white artefact of the screenshot.

**The view is correct in isolation.** `IncidentsView` was laid out offscreen in
sixteen configurations and drew its empty state in every one. The window used is
never made key, ordered front or shown. What was tried:

- bare `ContentUnavailableView`; the same inside a `NavigationSplitView` detail
- plus `.navigationTitle`; plus the `Group` wrapper; plus
  `.inspector(isPresented: .constant(false))`; plus `.inspectorColumnWidth`
- the real `IncidentsView` with a real empty `MonitorStore`
- at 900x600, at 1200x300, and at the real window's 1316x876
- inside an `NSHostingController` with a unified toolbar, i.e. the way a SwiftUI
  `Window` scene hosts a split view — not just an `NSHostingView`
- a byte-for-byte `MainWindowView` replica: sidebar `List` with
  `navigationSplitViewColumnWidth`, `switch` in the detail, section preset to
  Incidents
- with a parent republishing 10x a second, to imitate the live store
- the populated branch with three real `Incident` values, with and without the
  `navigationDestination`

**Ruled out by evidence, not by argument:**

- *Layout collapse.* The app's own prefs record
  `NSSplitView Subview Frames main, SidebarNavigationSplitView` as exactly two
  columns, 200 pt and 1300 pt. The detail column was full width, and no inspector
  column existed. So the pane was correctly sized and its content drew nothing —
  which points at empty content, not at a squeezed column.
- *An over-tall pane hiding a centred view.* Those persisted frames record a
  height of 6020 pt in a 1073 pt window, which looked like a strong lead: a
  `ContentUnavailableView` centres itself, so at 6020 pt it would sit ~3000 pt
  below the fold, and every other pane in the app is top-aligned inside a
  `ScrollView` and would survive. Tested directly by laying the pane out 6020 pt
  tall and sampling only the top 1073 pt: **the empty state still appears.**
  SwiftUI clamps. Hypothesis dead.
- *State restoration.* The container has no
  `Data/Library/Saved Application State`. Nothing was restored.
- *A SwiftUI runtime complaint.* `log show` over the app's whole session shows no
  SwiftUI, navigation or inspector diagnostics. (It does log an AppKit
  "reentrant operation in its NSTableView delegate" warning every ~2 s, which is
  the inventory table, not this pane — worth its own task.)
- *A recent regression in this file.* `IncidentsView.swift` has one commit,
  `a44c503`, and has not been touched since. Nothing committed afterwards touches
  the incidents path. The empty state may simply never have been seen: TASK-51's
  sign-off screenshot is of a **populated** list, and its AC#4 note reads like it
  was taken from the source rather than the screen.

## What was changed, and why it is defensible without a reproduction

Two constructs here are unsupported on their own terms, and each can put nothing
in a detail column. Both are gone.

1. `inspector(isPresented: .constant(selection != nil))`. `.constant` is a
   read-only binding. `inspector(isPresented:)` writes back through it when the
   inspector is dismissed, and those writes are discarded, so SwiftUI's
   presentation state and the view's can disagree about whether a trailing column
   exists. Replaced with a real two-way binding that clears `selection`.
2. `navigationDestination(for: Incident.ID.self) { _ in EmptyView() }`. This
   registered a destination on the detail column's stack whose entire content was
   *nothing*. A `List(selection:)` whose selection type has a registered
   destination is SwiftUI's "selection pushes a screen" pattern, so selecting a
   row could replace the column with an empty view instead of opening the
   inspector. Nothing in the app pushes an incident. Removed.

**Stated plainly: that either of these caused the captured blank pane is a
hypothesis, not a measurement.** They are the only unsupported constructs in the
file and the only ones capable of the exact symptom, and `IncidentsView` was the
only view in the app using either — and the only pane that rendered blank. That
is a strong correlation, not a proof.

## Tests

`MacSlowdown/Tests/IncidentsViewRenderTests.swift`, 5 new tests: an ink-vs-paper
control for the harness itself, the empty state at three window sizes, and the
populated list. Each lays the real view out in a window that is never shown and
asserts the detail column is not one flat colour.

Two harness traps, both hit while writing it, both documented in the file:
composite over white (the hosting view has no opaque ground, so an uncomposited
read collapses every pixel to a single value and a perfect render reports blank),
and remember `NSHostingView` is flipped (take the top as `height - visible` and
you sample the bottom, which is blank for an uninteresting reason). The first one
produced a false reproduction of this very bug; the second produced a false
confirmation of the over-tall hypothesis.

Full suite: **392 passing, 0 failing** (387 before this task). `MetricsTests`
"A real slowdown produces one incident that closes after recovery" is flaky under
concurrent build load — it failed once mid-session and passed on the unmodified
baseline and on every re-run. Unrelated to this change.

## Not verified

Criteria 1–4 are **not verified**. Nothing was put on screen: the user was
working on the machine and CLAUDE.md forbids launching the app, driving the UI or
taking screenshots without permission. A person still needs to open the app with
no incidents recorded, select Incidents, and confirm the empty state appears —
and, if it does not, re-open this task with the offscreen dead ends above already
crossed off. Criterion #4 is left unchecked deliberately: the investigation is
recorded, but the cause was not established.
<!-- SECTION:NOTES:END -->
