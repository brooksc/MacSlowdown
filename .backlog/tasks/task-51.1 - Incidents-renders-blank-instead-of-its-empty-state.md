---
id: TASK-51.1
title: Incidents renders blank instead of its empty state
status: In Progress
assignee: []
created_date: '2026-08-09 02:14'
updated_date: '2026-08-09 19:12'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-51
priority: high
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

## VERIFIED ON SCREEN 2026-08-09: STILL BLANK. THE FIX DID NOT WORK.

Run on macOS 27, built Debug app, no incidents recorded. Selecting Incidents shows the navigation title and the 7-days/30-days range picker in the toolbar, and **nothing else**. Screenshot: `screenshots/verify/03-incidents.png`.

This session's own warning was right: 'If it is still blank, the fix is wrong.' It is, and it was.

## The new evidence narrows it sharply

Since that fix, TASK-65.6 **rewrote this file completely** — different body structure, header, `DayStrip`, list, footer. The rewrite is also blank. So two independent implementations of `IncidentsView` render nothing, which eliminates almost everything specific to either one.

More telling: the current body is

```
VStack {
    if all.isEmpty { empty } else { header; Divider(); list }
    Divider()
    footer
}
```

**The `Divider()` and the `footer` are unconditional, and neither appears either.** So this is not `ContentUnavailableView` failing to draw — the entire `VStack` produces nothing. That is a much stronger clue than anything in the earlier investigation, and it rules out the empty-state view itself as the subject.

## Prime suspect: `.inspector(isPresented:)`

It is the one construct **both** implementations kept. TASK-51.1 suspected it and replaced `.constant` with a real two-way binding; TASK-65.6 rewrote everything around it and kept the same corrected binding. Neither removed it, and this is the only pane in the app that uses it.

The other three panes — Now, Apps & Processes, Storage — all render correctly in the same window on the same run, so the detail column, the split view and the window are all fine.

## What to try next, in order

1. **Remove `.inspector` entirely** and confirm the pane renders. If it does, the cause is settled and the incident detail needs a different presentation — a sheet, a navigation push, or an inspector attached at the `NavigationSplitView` level rather than inside the detail column.
2. If it still renders nothing without the inspector, bisect the body: title only, then title plus one `Text`, then the footer alone. Something is collapsing the `VStack` to zero height.
3. Note the offscreen harness in `IncidentsViewRenderTests.swift` **draws this view correctly in 16 configurations**, including a `MainWindowView` replica at the real window size. So whatever this is, it does not reproduce in an `NSHostingView` — it needs the live scene. Do not trust a green render test here.

Raised to High: three of four main surfaces work and this one shows nothing, and it is the surface the whole product exists to deliver.

## LIKELY SOLVED BY TASK-75 — do not chase `.inspector` yet

Measured immediately after the note above: with Apps & Processes selected, the main window is **1300 x 3599 points on a 1107-point screen**. The inventory table is laid out at its full intrinsic height for ~720 rows and the window grows to fit it.

That almost certainly explains this pane too. `ContentUnavailableView` **centres itself vertically**. In a detail column thousands of points tall it sits roughly 1800 pt below the fold, and the unconditional `Divider` and footer sit at the very bottom — all outside the visible slice. Every observation fits: the title and toolbar render because they belong to the window; the body looks empty; and the *unconditional* elements are missing too, which no theory about `ContentUnavailableView` alone could explain.

**The earlier investigation was right about the mechanism and wrong about the venue.** It found the persisted `NSSplitView` frames recording 6020 pt, tested exactly this, and recorded 'SwiftUI clamps. Hypothesis dead.' — but it tested in an offscreen `NSHostingView`, which *supplies* the height and therefore clamps. A real `Window` scene does not. That is why the harness draws this view correctly in 16 configurations while the running app shows nothing.

**Do TASK-75 first, then re-check this pane before touching it.** If the pane renders once the window stops growing, close the remaining criteria and drop the `.inspector` suspicion rather than pursuing it — it was a reasonable suspect but there is now a better-evidenced explanation.

General lesson worth carrying: **an offscreen render harness cannot answer a question about window sizing**, because the harness decides the size.

## TASK-75 is done, and the geometry explanation now has numbers behind it — but this still needs eyes

The over-tall window is real, measured and fixed. Offscreen, asking the content what size it *demands* rather than laying it out at a supplied size: the Apps & Processes pane inside a `NavigationSplitView` detail column demanded **9,880 pt**, and the whole `MainWindowView` demanded **1,243 pt**. After the fix, 205 pt and 320 pt. The container's own saved `NSSplitView Subview Frames` recorded 9,932 pt, written by the running app — the same figure from an entirely independent source.

**Does that plausibly explain the blank Incidents pane? Yes, and the fit is good.** A detail column thousands of points tall puts a vertically-centred `ContentUnavailableView` far below the fold, and puts the unconditional `Divider` and footer at the very bottom — which is the one observation no theory about `ContentUnavailableView` alone could account for. It also explains why sixteen offscreen configurations rendered the pane correctly: they were all given a sane height.

**But it is still a hypothesis about this pane.** Two things stop it being more than that:

- The cause was *not* the inventory table's rows, as TASK-75 assumed. It was seven paragraphs of `fixedSize`-vertical caption text in the inventory's footer answering a width-less ideal-size query with thousands of points. That is a defect in the **Apps & Processes** pane specifically. Incidents on its own demanded 0 pt and inside a split view demanded 10 pt — it never asked for height itself. It was a bystander to a window the Apps pane had already inflated, *if* the window was inflated at the moment Incidents was captured. Nobody has established that it was.
- Nothing was put on screen this session, so the pane has not been looked at since the fix.

**Next step, unchanged from TASK-75's criterion #5:** open the app with no incidents recorded, select Incidents, and look. If the empty state appears, close criteria #1–#4 here, record the cause as the window geometry, and drop the `.inspector` suspicion rather than pursuing it. If it is still blank, the `.inspector` line of enquiry is back and this note should say so plainly.

Note the window id changed from `"main"` to `"main-v2"` as part of TASK-75, to stop AppKit restoring the saved 3599 pt frame. The window will open at 900 x 600 in a default position on the first launch after that change; that is expected, not a new fault.
<!-- SECTION:NOTES:END -->
