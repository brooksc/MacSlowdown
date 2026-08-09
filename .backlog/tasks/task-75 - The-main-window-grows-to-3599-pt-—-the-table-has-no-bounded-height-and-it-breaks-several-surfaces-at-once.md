---
id: TASK-75
title: >-
  The main window grows to 3599 pt — the table has no bounded height, and it
  breaks several surfaces at once
status: Done
assignee: []
created_date: '2026-08-09 18:33'
updated_date: '2026-08-09 22:55'
labels:
  - ui
milestone: m-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by the product owner and measured on screen 2026-08-09, macOS 27, built Debug app.

**`Apps & Processes` makes the window 1300 x 3599 points on a 1107-point-tall screen.** Measured via the accessibility API while the window was open. Setting the window to 860 pt high does not stick — it springs back, because the content is forcing the size.

The inventory `Table` is laid out at its full intrinsic height for ~720 rows rather than being given a bounded frame and scrolling internally. The window resizes to fit it.

## This is one cause with several symptoms

All of these were reported or observed together, and all follow from the geometry:

1. **The list cannot be scrolled.** There is no scroll view to scroll — the window itself is enormous and the user sees a slice of it.
2. **Column headers are cut off and not pinned.** They are at the top of a 3599 pt layout, above the visible slice.
3. **The sidebar disappears.** It is inside the same over-tall window. Collapsing and re-expanding does not bring it back, because the sidebar's state is not what is wrong.
4. **The segmented control, search field and census footer are unreachable** for the same reason. Screen 1m's "Show unmeasurable" toggle and the "N of M processes belong to an app" footer cannot be seen.
5. **Very probably the blank Incidents pane (TASK-51.1).** `ContentUnavailableView` centres itself vertically. In a detail column thousands of points tall, the empty state sits roughly 1800 pt below the fold and the unconditional `Divider` and footer sit at the very bottom — all outside the visible area. That matches every observation: the title and toolbar render (they belong to the window), the body appears empty, and the *unconditional* elements are missing too.

## Why two investigations missed it

TASK-51.1 found the persisted `NSSplitView` frames recording a 6020 pt height and tested precisely this hypothesis — but tested it in an offscreen `NSHostingView`, where SwiftUI clamped to the given size, and recorded "SwiftUI clamps. Hypothesis dead." The mechanism was right; the venue was wrong. **A hosting view constrains height in a way a real `Window` scene does not.**

That is the durable lesson here: an offscreen render harness cannot answer a question about window sizing, because the harness supplies the size.

## What to check

- Give the table a bounded frame so it scrolls internally instead of growing the window.
- Confirm the window then honours a set size and stops springing back.
- Re-check the Incidents pane immediately afterwards, before doing anything else to it — if this fixes it, TASK-51.1's remaining criteria close and the `.inspector` suspicion is dropped rather than pursued.
- Check whether the persisted `NSSplitView Subview Frames` / `NSWindow Frame main` entries in the container carry a bad size forward across launches, and whether a fresh container behaves differently. A saved 6020 pt frame may make this worse or make it appear to persist after a fix.
- Watch for interaction with TASK-74's ordering damping: fewer row moves will not help if the height is unbounded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The main window no longer resizes itself to the content height; a window set to a given size keeps it, verified by measuring the window on screen
- [x] #2 The inventory scrolls internally, and its column headers stay visible while scrolling
- [x] #3 The sidebar remains visible when switching to Apps & Processes, and collapse/expand works
- [x] #4 The segmented control, search field and census footer are reachable without resizing the window
- [x] #5 The Incidents pane is re-checked immediately after this fix and the result recorded on TASK-51.1, whichever way it goes
- [x] #6 Behaviour is checked against both an existing container with persisted window frames and a fresh one
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Measured, then fixed. The hypothesis was right about the mechanism and wrong about the culprit.

### How it was measured

The two earlier investigations laid the view out in an offscreen `NSHostingView` **at a supplied size** and watched it clamp. That harness can never see this bug: it decides the answer. The right question is what the content *demands*, and it is answerable offscreen — `NSHostingController` with `sizingOptions = [.preferredContentSize, .minSize, .intrinsicContentSize]`, a fixed width of 1300 pt and no height constraint, then read `preferredContentSize` / `fittingSize` / `intrinsicContentSize`. All three agreed in every measurement below.

Two traps hit on the way, both recorded in `MacSlowdown/Tests/WindowSizingTests.swift`:

- `sizeThatFits(in: .greatestFiniteMagnitude)` is useless here. Every pane returns `greatestFiniteMagnitude`, because they are all willing to fill whatever they are given. It says nothing about what they *ask* for.
- Attaching a real `NSWindow` and then tearing it down aborts inside AppKit's display cycle (SIGABRT in `__NSWindowGetDisplayCycleObserverForLayout_block_invoke`). No window is needed.

### What it measured — before

| subject | demanded height |
|---|---|
| control: VStack of 20 x 20 pt / 500 x 20 pt | 400 pt / 10,000 pt (harness works) |
| our inventory table alone, 20 rows | 137 pt |
| our inventory table alone, 500 rows | 137 pt |
| our inventory table alone, 140 rows x 4 children | 137 pt |
| our inventory table alone, live store (491 top-level, 864 total) | 137 pt |
| **our inventory table inside a `NavigationSplitView` detail, 20 rows** | **9,484 pt** |
| **Apps & Processes pane inside a split view, empty store** | **9,529 pt** |
| **Apps & Processes pane inside a split view, live store** | **9,880 pt** |
| bare SwiftUI `Table` inside a split view | 10 pt |
| `List`, `Text().searchable`, plain `Color` inside a split view | 10 / 10 / 50 pt |
| Now / Incidents / Storage inside a split view | 10 pt each |
| **whole `MainWindowView`, live store** | **1,243 pt** |

### The cause

**Not the rows.** 20 rows and 500 rows demand exactly the same height, and the pane demands 9,529 pt with an *empty* store. The hypothesis that the `Table` reports the intrinsic height of ~140 family rows is false.

**It is the footer text.** The inventory footer is seven paragraphs of caption under `fixedSize(horizontal: false, vertical: true)` inside a `safeAreaInset(edge: .bottom)`. When a `NavigationSplitView` asks its detail column for an ideal size it proposes no width; `fixedSize` vertically then means "give me the height I need at whatever width you are proposing", every sentence wraps to roughly one word per line, and the answer is thousands of points. The pane is innocent on its own at a known width (182 pt) and guilty inside the container it ships in.

Confirmed against the mechanism in isolation, not merely inferred: a bare `Table` plus a replica of that footer demands **6,377 pt** with `fixedSize` and **46 pt** without it. The sidebar footer in `MainWindowView` has the same shape and accounted for the remaining 1,243 pt.

The hypothesis's *mechanism* — content forces the window's size, and `Window` had no `.windowResizability` — was correct, and is half the fix.

### What changed

- `MacSlowdown/Sources/MacSlowdownApp.swift` — `.windowResizability(.contentMinSize)` on the main `Window`, so it follows `defaultSize` and the user rather than its content's ideal. Window id `"main"` -> `"main-v2"` (see persistence below).
- `MacSlowdown/Sources/MainWindowView.swift` — detail column extracted to `detailPane` and bounded `.frame(minWidth: 480, idealWidth: 700, minHeight: 320, idealHeight: 480, maxHeight: .infinity)`; the same height bound on the sidebar column. Every pane scrolls, so none has a content height worth respecting.
- `MacSlowdown/Sources/ProcessInventoryView.swift` — the table extracted to a new `InventoryTable` view with `rows` injected, so its demanded height can be asked of a known row count at all; bounded `.frame(minHeight: 160, idealHeight: 420, maxHeight: .infinity)`. No behaviour change beyond the frame.
- `MacSlowdown/Tests/WindowSizingTests.swift` — new, 8 tests.

### What it measures — after

| subject | before | after |
|---|---|---|
| Apps pane in a split view, live store | 9,880 pt | **205 pt** |
| inventory table in a split view, 20 rows | 9,484 pt | **160 pt** |
| inventory table alone, 20 / 500 / 140x4 / live rows | 137 pt | **420 pt, identical for every row count** |
| whole `MainWindowView`, live store (497 rows) | 1,243 pt | **320 pt** |
| whole `MainWindowView`, empty store | 863 pt | **320 pt** |

### Persisted frames — criterion #6, half handled

Read from the container with `defaults read com.brooksc.MacSlowdown` (terminal only; the app was not launched):

```
"NSWindow Frame main" = "120 -2526 1300 3599"
"NSSplitView Subview Frames main, SidebarNavigationSplitView" = (
    "0.000000, 0.000000, 200.000000, 9932.000000, NO, NO",
    "0.000000, 0.000000, 1300.000000, 9932.000000, NO, NO" )
```

That **9,932 pt** is independent corroboration of the 9,880 pt measured offscreen — the same number, written by the running app before this session began. And `y = -2526` means the saved window sits mostly off the top of the screen.

AppKit would restore both on the next launch and the fix would appear not to work. Handled by renaming the window id to `"main-v2"`, which retires both autosave keys at once (the split view's key is derived from the window's). The cost is that a window position the user chose is forgotten once; the alternative is a window they cannot see.

### Tests

`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .build -only-testing:MacSlowdownTests` — **462 passing, 0 failing**. The same with `-only-testing:MetricsTests` — **391 passing, 0 failing**. 853 total against 845 before, i.e. 8 new. No load-sensitive test was run or needed.

The durable assertion is `demandedHeightDoesNotScaleWithRowCount`: 20 rows and 500 rows must demand the same height, within 20 pt, and under 900 pt. Note honestly that **it passes on the broken code too**, because row count was never the variable — it is kept because it is the property the next person will assume, and it is now true by construction rather than by luck. The assertion that would actually have caught this is `mainWindowIsBounded`: the whole `MainWindowView` over a live process table, under 900 pt. It failed at 1,243 pt before the sidebar bound went in.

Test output does not survive `xcodebuild` for an app-hosted bundle, so the figures are appended to `task75-window-sizing.txt` in the host app's temporary directory (inside its sandbox container — the only place it may write). Every number above came from there.

### Not verified — needs the screen

Nothing was put on screen. **Criteria #1, #2, #3, #4 and #6 are unverified**, and #5 is too. What should be checked, precisely:

1. **#1** — open the window, select Apps & Processes, measure it through the accessibility API. It should be at or near 900 x 600, not 1300 x 3599. Drag it to ~860 pt tall and confirm it stays. Then drag it *small*: it should stop at roughly 680 x 320 and go no smaller.
2. **#2** — scroll the process list. The list itself should scroll, with the column headings staying put at the top.
3. **#3** — the sidebar should be visible on switching to Apps & Processes, and collapse/expand from the toolbar should work.
4. **#4** — the Apps / All-processes segmented control and the search field should be visible at the top, and the census footer ("N of M processes belong to an app", freshness, the CPU convention) at the bottom, without resizing anything.
5. **#6** — the live risk. The rename to `"main-v2"` **rests on an unverified assumption**: that a SwiftUI `Window`'s frame-autosave keys really are derived from its scene id on this OS. Check by launching once and confirming a new `NSWindow Frame main-v2` appears in `defaults read com.brooksc.MacSlowdown` while `NSWindow Frame main` is left behind untouched and unused. Then check a fresh container (move the container aside) behaves the same.
6. **#5** — select Incidents with no incidents recorded and see whether the empty state appears. Record the result on TASK-51.1 either way.

### Left alone deliberately

The `fixedSize(horizontal: false, vertical: true)` calls themselves are untouched. They are correct for rendering — they are what stops the footers truncating at a real width — and the same pattern appears on many views across the app. What was wrong was letting their answer to a width-less ideal-size query escape to the window. Bounding the ideal at the container is the narrow fix; removing `fixedSize` would be a wide one with its own regressions. Worth knowing the pattern is there, though: **any `fixedSize`-vertical wrapping text inside a `NavigationSplitView` column will do this again** if a future view puts one somewhere the bound does not cover.

## VERIFIED ON SCREEN 2026-08-09 — all six criteria met

Run on macOS 27, built Debug app, measured through the accessibility API rather than judged by eye.

**Before, from the container's own persisted state:** `NSWindow Frame main = 120 -8911 1300 9984`. Not the 3599 originally reported — it had grown to **9984 pt**, positioned 8911 pt above the top of a 1073 pt screen.

**After:** window `900 x 600`, and `NSWindow Frame main-v2 = 405 236 900 600`. The `main-v2` rename worked exactly as intended — the old 9984 pt key is still in the plist, untouched and now inert, so an existing container behaves identically to a fresh one (criterion #6, which was flagged as the riskiest assumption of the day).

Criteria #2–#4 confirmed from `screenshots/verify2/04-apps.png`: the table scrolls internally with column headers pinned, the sidebar is present and the Apps/All-processes segmented control, the search field and the census footer are all reachable without resizing.

**Criterion #5 — Incidents re-checked immediately, and the answer was no.** With the window correct at 900x600 the pane was *still* blank. That killed the geometry explanation for TASK-51.1 outright, and the real cause was then found by measuring the same way: `.inspector` builds a split view inside the detail column, and that split view was **900 x 4085 at y=-1445**. Recorded in full on TASK-51.1, now closed.

So this task's own diagnosis was right about the window and wrong to expect it would carry TASK-51.1 with it — which is exactly why criterion #5 was written as "whichever way it goes".

**Bonus, measured:** the geometry bug was the dominant cost in the app's CPU use. `sample` on the pre-fix process showed half the display-cycle work in `updateConstraintsForSubtreeIfNeeded` — Auto Layout re-solving an enormous unvirtualised view tree every cycle. The app's own self-report went from **27% of one core to 3.0%** after this and TASK-74 landed.

Suite: 1011 passing, 0 failing.
<!-- SECTION:NOTES:END -->
