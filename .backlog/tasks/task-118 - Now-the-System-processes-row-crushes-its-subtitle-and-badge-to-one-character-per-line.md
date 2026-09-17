---
id: TASK-118
title: >-
  Now: the System processes row crushes its subtitle and badge to one character
  per line
status: To Do
assignee: []
created_date: '2026-09-17 02:30'
labels:
  - ui
milestone: m-1
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Seen on screen 2026-09-16**, in the real running app on macOS 26.6.2 in a VM — not a preview, not inferred from a test.

On the **Now** screen, the app table's "System processes" row renders its subtitle and its badge as near-vertical text, roughly one to three characters per line:

```
>  🔒  Sy…   286      Ca
              pro-     n't
              cess-    be
              es       bro
                       ken
                       do
                       wn
```

The name truncates to "Sy…", "286 processes" stacks as `286 / pro- / cess- / es`, and the "Can't be broken down" badge stacks as `Ca / n't / be / bro / ken / do / wn`. The row becomes several times the height of an ordinary row as a result, and it is the second row on the app's primary screen.

**This is the TASK-75 failure mode again.** There, a `NavigationSplitView` proposed no width, caption text under `fixedSize(horizontal: false, vertical: true)` wrapped to about one word per line, and the view answered with a height in the thousands of points. Same shape here: a cell is being offered almost no width, and text that is allowed to grow vertically takes the offer. The fix is likely the same family — give the name column a real minimum width, and stop the subtitle and badge from being compressible to nothing.

Worth checking whether this is the same root cause as [[TASK-117]], which was the All processes table drawing nothing at all below ~560 pt because **no column declared a width**. The Now table's columns should be audited the same way: Now, Last minute, Resident memory, Retained history and Age are all present and none was checked.

**Why it was not caught earlier.** The row only appears when there is an unmeasurable aggregate to show, and it needs a live machine with other-uid processes — so no unit test constructs it, and the previews added so far cover `AllProcessesView` rather than the Now table.

Screenshot: `02-now.png` from the 2026-09-16 VM capture run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The System processes row on Now renders its name, its process count and its badge on single lines at the default window size
- [ ] #2 The row's height matches an ordinary app row rather than expanding to fit vertical text
- [ ] #3 Every column in the Now table declares a width, as the All processes table now does after TASK-117
- [ ] #4 Checked at the window's 480 pt minimum as well as the 900 pt default, and neither produces vertical text or a blank table
- [ ] #5 Verified by looking — a rendered preview or a VM screenshot is attached, not a passing test
<!-- AC:END -->
