---
id: TASK-65.18
title: 'App icon: choose a direction and ship a real asset (there is none today)'
status: In Progress
assignee: []
created_date: '2026-08-09 03:26'
updated_date: '2026-08-09 03:28'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**The app currently has no icon at all** — no asset catalog, no `.icon` file, no `AppIcon` reference in `Project.swift`. It ships with the generic placeholder.

That is no longer only a branding gap. TASK-11.1 makes the Dock icon a real navigation route: with the menu bar item hidden, clicking the Dock icon is the *only* way back into the app. A generic placeholder is now part of a functional path, not just a first impression. It is also required for the Mac App Store, Finder, Settings and Spotlight.

## Design input

Six directions in turn 3 of the Claude Design project ("App icon — six directions"), rendered to `design/icons/3a.png` … `3f.png`, each showing the 1024 pt icon with its 32 pt and 16 pt reductions:

| | Direction | Designer's stated risk |
|---|---|---|
| 3a | Level meter — the menu bar glyph, promoted | Duplicates the state indicator |
| 3b | Trace with an incident band | Band vanishes below 32 pt, leaving a common chart-line icon |
| 3c | Dial at redline | Gauges are the most-used metaphor in the category; least distinctive |
| 3d | Lens over the trace — diagnosis, not measurement | — |
| 3e | Attribution split — the honest one | Abstract enough to read as a generic list until you know the app |
| 3f | Stopwatch — the felt experience | — |

**The designer's own caveat, which governs how these are used: "These are vector sketches, not rendered artwork — treat them as direction-setting rather than finished icons."** Do not ship a sketch. They set direction; artwork is a separate step.

Two constraints the brief states, both of which must survive whatever is chosen:
- The icon must NOT duplicate the menu bar glyph, which is a live state indicator (see TASK-65.17 / design 2d), not a brand mark.
- It must not read as a generic "system utility gear", the category default.

## Where the product owner is

Likes **3b** and **3c**. Neither is settled, and the following points were raised and are unresolved — they need a decision before artwork begins:

1. **3b's concept lives in the element that disappears.** The shaded band is the app's actual thesis — a slowdown is an interval, not an instant — and it is the first thing lost at small sizes. Either the band earns enough contrast to survive 16 pt, or the concept does not reach the user at the size the icon is usually seen.
2. **3c is drawn permanently at redline.** An icon showing an alarm state contradicts a product whose discipline is not overstating severity (FR-013), and it competes with the menu bar glyph, which is the thing that legitimately signals state. A dial at rest was proposed instead.
3. **3c collides with the current build.** The menu bar symbol today is `gauge.with.dots.needle.33percent` — the same metaphor. Choosing 3c means changing one of the two.
4. **3e was raised as an outside candidate**: the hatched third bar depicts unattributable system activity, the ~40% of load the sandbox cannot break down. It is the only direction depicting something a competitor could not truthfully draw, and it reduces cleanly. Not chosen; recorded so it is not lost.

A hybrid round was suggested and not yet requested: 3b's band with more contrast, and 3c's dial pulled back from redline.

## Platform notes for whoever implements

Target is macOS 26 and 27. macOS 26 introduced a layered icon format authored in Icon Composer, with light, dark, tinted and clear appearances rather than a single flat image — check the current requirement before producing a legacy `.appiconset`. The design places the artwork inside a 1024 squircle; the system applies its own masking and material effects on 26+, so baking the squircle into the asset is usually wrong. Verify against Apple's current guidance rather than following the mock literally on this point.

The icon must be added to `Project.swift` — Tuist manifests are the source of truth.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A direction is chosen and the reasoning recorded, including how the chosen icon avoids duplicating the menu bar state glyph
- [ ] #2 Finished artwork exists -- not a rendered design sketch -- in the format the target macOS versions require, with the appearance variants those versions expect
- [ ] #3 The icon is legible at 16 pt in the Dock and Finder sidebar, checked at that size and not only scaled down on screen
- [ ] #4 The icon does not depict a permanent alarm or severity state, so it does not overstate condition (FR-013)
- [ ] #5 The asset is wired into Project.swift and appears on the built app in Finder and the Dock
- [ ] #6 Verified on screen at real sizes; anything not looked at is recorded as not verified
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DECISION 2026-08-08, product owner: **3b — trace with an incident band**. Reference render `design/icons/3b.png`.

3e was considered and rejected: the three bars read as a bar chart, which is worse than the designer's stated 'generic list' risk, because a bar chart implies we are charting categories rather than showing a split of one quantity.

3c was not chosen. The objections raised against it stand on the record and do not need re-litigating: it is drawn permanently at redline (overstates condition, competes with the menu bar state glyph), and it duplicates the current build's `gauge.with.dots.needle.33percent` symbol.

**The known problem with 3b is now the work.** The designer's own risk note: the shaded band vanishes below 32 pt, leaving a common chart-line icon. The band is the concept -- a slowdown is an interval, not an instant -- so an implementation that loses it at 16 pt has shipped a generic squiggle. Solving the reduction is the design task here, not an afterthought to asset production. Acceptable answers include raising the band's contrast against the slate, widening it, letting the trace and band share an edge, or drawing a distinct simplified form for the small sizes (which is normal practice, not a compromise).

Still open and NOT decided by this: whether to ask the designer for a refined 3b round before artwork is cut. The implementer may recommend it.
<!-- SECTION:NOTES:END -->
