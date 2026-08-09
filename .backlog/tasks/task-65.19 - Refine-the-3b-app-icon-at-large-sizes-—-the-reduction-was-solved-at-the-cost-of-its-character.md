---
id: TASK-65.19
title: >-
  Refine the 3b app icon at large sizes — the reduction was solved at the cost
  of its character
status: To Do
assignee: []
created_date: '2026-08-09 18:24'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Product owner decision, 2026-08-09:** clean this up. Follow-up to TASK-65.18, which shipped a working asset.

TASK-65.18 solved the real problem it was set. Direction 3b's known weakness was that the incident band vanishes below 32 pt, leaving a generic chart-line icon — and the band *is* the concept, since a slowdown is an interval rather than an instant. It fixed that properly: the band runs the full height of the tile so it survives as a silhouette, the trace rises at the leading edge and falls at the trailing one (stating the interval twice, and depicting a slowdown that **ended** rather than an ongoing alarm), and separate artwork for 16/32 px snaps every coordinate to a pixel boundary. The small sizes read well and that work should not be undone.

**What it cost.** At 1024 the icon lost the sketch's character. The full-height band plus the flattened trace reads as a squarish arch over a vertical stripe — closer to a staple or a bridge than a data trace. The sketch's settled sections had organic movement; these are nearly flat, so the shape reads as geometry rather than measurement. The amber band at 48% over the slate also goes khaki where they overlap.

That matters because 1024 is the App Store listing and Get Info — the sizes where the icon is doing the most work for a product nobody has used yet. Nobody was asked to defend the large size; the brief only named the small one.

**The likely right move** is a refined round from the designer, shown `design/icons/contact-sheet.png` and told what the reduction constraint actually requires — that is material judgement across four appearances, which a headless render cannot settle. TASK-65.18's own session reached the same conclusion for the layered version.

**Related and still open, from TASK-65.18:** the layered Icon Composer variants (light / dark / tinted / clear) required by macOS 26 do not exist; the shipped asset is a conventional `.appiconset`. And a trap worth remembering — once a `.icon` bundle exists, Xcode prefers it and regenerates the small sizes from the layered art, **discarding the hand-tuned 16 px**. Re-check 16 px after any Icon Composer work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The 1024 icon reads as a measurement rather than as a geometric arch, judged against design/icons/3b.png for character and against the reduction constraint for legibility
- [ ] #2 The 16 and 32 px renderings remain at least as legible as the current asset, checked at true size and not by scaling down the large art
- [ ] #3 The icon still depicts a slowdown that ended rather than an ongoing alarm state (FR-013)
- [ ] #4 Colour handling avoids the khaki cast where the amber band crosses the slate
- [ ] #5 Verified on screen in the Dock, the Finder sidebar and Get Info -- not only as rendered files
<!-- AC:END -->
