---
id: TASK-65.23
title: >-
  Menu bar icon polish: the glyph sits off-centre in its slot and the badge is
  illegible at 16 pt
status: To Do
assignee: []
created_date: '2026-08-09 22:54'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-on from the fix committed on 2026-08-09 that made the icon render at all — `MenuBarExtra` will not draw SwiftUI shapes, so the glyph is now rasterised with `ImageRenderer`. See `screenshots/verify2/icon-fixed.png`.

It draws correctly and in the right state (three red ascending bars for an open incident, tint preserved). Two things are visibly imperfect and neither was worth blocking the fix for:

**1. The status item is 32 pt wide and the glyph is pushed to the right of it.** The glyph's own frame is 14 pt. The extra width most likely comes from the badge overlay's `offset(x: 2, y: -1)` extending the rendered bounds, so the rasterised image is wider than the glyph and the padding all lands on one side. The item should be as narrow as the content and the glyph centred in it — a status item with dead space on one side reads as a misaligned icon, and in a crowded strip it costs real room.

**2. The badge is not legible at menu bar size.** It is a 5.5 pt stroked ring offset over the tallest bar; at 16 pt against a red bar it merges into the bar rather than reading as a separate mark. The design's intent was a shape distinct enough not to be mistaken for a rendering artefact, and at this size it currently fails that test. Consider placing it clear of the bars, or using a filled dot with a contrasting halo.

Both need a person at the menu bar to judge; neither is testable offscreen, which is the same limit that let the invisible-icon defect survive in the first place.

**Also still unverified: the popover.** Clicking the status item through the accessibility API did not open it during this session, and `MenuBarExtra`'s window does not appear in the process's AX window list, so it could not be confirmed either way. Whether that is a real defect or only an artefact of synthetic clicking is unknown — check it with a real mouse click before assuming either.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The status item is no wider than its content and the glyph is centred within it
- [ ] #2 The open-incident badge is distinguishable from the bars at actual menu bar size, in both light and dark strips
- [ ] #3 The four states are each looked at on a real menu bar, including muted, and muted is confirmed not to read as normal
- [ ] #4 Clicking the status item with a real mouse opens the popover, or the failure is recorded with what was tried
<!-- AC:END -->
