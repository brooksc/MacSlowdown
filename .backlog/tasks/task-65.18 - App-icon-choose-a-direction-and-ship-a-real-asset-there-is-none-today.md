---
id: TASK-65.18
title: 'App icon: choose a direction and ship a real asset (there is none today)'
status: In Progress
assignee: []
created_date: '2026-08-09 03:26'
updated_date: '2026-08-09 03:42'
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
- [x] #1 A direction is chosen and the reasoning recorded, including how the chosen icon avoids duplicating the menu bar state glyph
- [ ] #2 Finished artwork exists -- not a rendered design sketch -- in the format the target macOS versions require, with the appearance variants those versions expect
- [ ] #3 The icon is legible at 16 pt in the Dock and Finder sidebar, checked at that size and not only scaled down on screen
- [x] #4 The icon does not depict a permanent alarm or severity state, so it does not overstate condition (FR-013)
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

IMPLEMENTED 2026-08-08 (worktree agent-a4d868401db993ca3, commit 0a70a61).

## The 16 pt reduction, which was the actual work

Three changes to the sketch, each verified by rendering to PNG at 16/32/64/128/256/1024 and inspecting the rasters -- not by scaling on screen:

1. **The band runs the full height of the tile.** In 3b it is a small inset rectangle floating behind the trace. A detail is the first thing a 16 px raster destroys; edge to edge it is a silhouette, and the tile visibly divides into three columns even when nothing else survives.
2. **The trace rises and falls on the band's two edges.** 3b's trace steps up inside the band and stays up. It is now settled, rises at the leading edge, elevated across the interval, falls at the trailing edge, settled again. The interval is stated twice, by the column and by the shape, so neither alone has to carry it. This also fixes criterion #4 for free: the icon depicts a slowdown that ended, not an ongoing alarm.
3. **Band contrast roughly doubled**, ~26% amber in the sketch to 48%/38%. Chosen by rendering 16 px at 0.26 / 0.42 / 0.55 and comparing; 0.26 is legible but faint, 0.55 makes the tile read brown rather than slate.

A **distinct simplified artwork** is drawn for 16 and 32 px (standard practice, not a compromise): below 64 px the large trace's undulation is noise and eats the contrast the band needs. `icon-small.svg` is laid out entirely on multiples of 64 units, so at 16 px every edge lands exactly on a pixel boundary and the 2 px trace / 6 px band are not smeared across two rows. That pixel-snapping is most of why they still read. Evidence: `design/icons/zoom-16.png`, `zoom-32.png`, `contact-sheet.png`.

Crossover is at 32/64 px. Almost every display is Retina, so 16 pt is drawn from the 32 px asset and 32 pt from the 64 px one: 16 pt simplified, 32 pt and up detailed. The seam is 32 px at 1x (non-Retina 32 pt), accepted given the macOS 26 / Apple Silicon target.

## Menu bar glyph (criterion #1)

No shared form with design 2d, and the icon is drawn in the past tense -- an interval that began, lasted and ended. It reports nothing about the machine now, so it cannot be mistaken for the live state indicator at any size.

## Format, and what is in the built bundle

Researched before producing. Full-bleed, fully opaque, **no squircle baked in**: macOS 26+ applies its own mask, and decides an icon is 'legacy' from its edge alpha -- alpha <= 252 gets shrunk inside a grey squircle instead of clipped (measured behaviour reported on Apple Developer Forums thread 797971; reverse-engineered, not documented by Apple). `build.sh` flattens every render to a PNG with no alpha channel at all, and the corner pixel of the compiled `.icns` was checked to confirm alpha 1.0 survives actool.

Shipped: a conventional `AppIcon.appiconset` with all ten macOS entries, sources as SVG in `design/icons/`.

Built bundle checked from the terminal: `Contents/Info.plist` carries both `CFBundleIconName` and `CFBundleIconFile` = AppIcon; `Contents/Resources/AppIcon.icns` exists; `xcrun assetutil --info` on `Assets.car` lists ten `Icon Image` entries for AppIcon at 16/32/32/64/128/256/256/512/512/1024. The 16 px image extracted back out of the built `.icns` was compared against the source PNG (`magick compare -metric AE` -> effectively zero), so the hand-tuned small artwork survives the toolchain rather than being regenerated from the large one.

## What a human still has to do in Icon Composer

No `.icon` bundle was faked -- Icon Composer is a GUI app and a `.icon` cannot be authored or validated from the command line. `design/icons/README.md` records the procedure step by step, and `design/icons/layers/1-band.svg` and `2-trace.svg` are the full-canvas, unmasked layer exports to import (per WWDC25 session 361: never include the mask; add flat backgrounds in Icon Composer). Background is a 135 degree gradient #5E6D90 -> #242C3C; band layer opacity 48%. Two warnings recorded there: (a) once a `.icon` exists Xcode prefers it over the `.appiconset` and regenerates the small sizes from the layered art, which would discard the hand-tuned 16 px artwork -- re-check 16 px before keeping it; (b) the dark and tinted appearances need a person to look at them, since tinted discards colour and the band's whole job is a colour contrast.

## Files

Created: `design/icons/{README.md,icon-large.svg,icon-small.svg,build.sh,contact-sheet.png,zoom-16.png,zoom-32.png}`, `design/icons/layers/{1-band.svg,2-trace.svg}`, `MacSlowdown/Resources/Assets.xcassets/**` (Contents.json plus 7 PNGs). The designer's `3a.png`-`3f.png` were untracked in the working tree and are now committed. Modified: `Project.swift` (a `resources:` glob on the app target and `ASSETCATALOG_COMPILER_APPICON_NAME`). Nothing under `MacSlowdown/Sources/` or `Metrics/Sources/` was touched.

## NOT VERIFIED -- what needs the user's eyes

- **#6, and the on-screen halves of #3 and #5.** Nothing was looked at in the Dock, the Finder sidebar or Get Info; the agent had no permission to use the screen. What was done instead: every size was rasterised to PNG at its true pixel size and inspected as an image, including 8-16x nearest-neighbour magnifications of 16 and 32 px. Stronger than eyeballing a scaled preview, but it is not the Dock.
- **#2 left unchecked** even though finished (non-sketch) artwork now exists in a shippable format: the criterion also asks for the appearance variants macOS 26 expects, and light/dark/tinted/clear were not produced. It becomes true when someone runs the Icon Composer steps above.
- **#5 left unchecked** for the same reason -- the wiring is done and the asset is provably in the built bundle, but 'appears in Finder and the Dock' was not seen.
- Whether macOS actually applies the rounded clip rather than the grey squircle fallback. The edge-alpha precondition is satisfied and confirmed in the compiled asset, but the outcome needs a person to look.

## Recommendation on a refined designer round

Not needed for this stage. The reduction problem is solved and the fix is testable by rendering, so another round would cost a trip to re-derive what the renders already settle. A designer round **is** worth requesting for the layered Icon Composer version: deciding where specular highlight and depth sit across four appearances is judgement about material, which is exactly what headless renders cannot answer.
<!-- SECTION:NOTES:END -->
