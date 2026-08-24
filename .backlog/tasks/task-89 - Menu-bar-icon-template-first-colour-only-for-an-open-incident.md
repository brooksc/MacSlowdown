---
id: TASK-89
title: 'Menu bar icon: template-first, colour only for an open incident'
status: To Do
assignee: []
created_date: '2026-08-24 04:03'
labels:
  - ui
  - decision
milestone: m-3
dependencies: []
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised by the product owner on screen, 2026-08-23: the icon reads as a static red alarm, and every other item in their real menu bar is monochrome.

**What is actually happening is correct and dynamic** — four states per design 2d, shape-led: normal 1 bar green, elevated 2 bars yellow, incident open 3 bars red plus a ring badge, muted 0 bars grey plus a diagonal slash. Red meant an open incident, not high CPU. FR-034 is satisfied: the bar count and the badge carry the state, so colour is reinforcement.

**Two things are still wrong.**

1. `MenuBarIconView.swift:46` maps the tints to raw system `Color.red` / `.green` / `.yellow`. Design 2d renders them as muted, desaturated tones. System red in the menu bar is about as loud as a colour gets.
2. Design 2d was drawn against a mockup strip. In a real menu bar every other icon is a template image, so a permanently-tinted icon is off-convention — and the state the user sees 99% of the time is *normal*, which under the current rule is a standing green light.

**Direction agreed with the product owner, 2026-08-23:** template (monochrome) in normal and elevated; colour permitted only for an open incident. This is a deliberate deviation from design 2d and should be recorded as one — the mocks are directional, and this is a case where the real environment contradicts the mock.

Note `MenuBarGlyphRenderer.image` already sets `image.isTemplate = !treatment.usesTint`, so the template path exists and is exercised under Increase Contrast; this changes which states take it.

**macOS 27 context, checked 2026-08-23:** Golden Gate walks back Tahoe's menu item icons — `NSMenu` hides symbol images by default for apps linked on macOS 26+, with `NSMenuItem.preferredImageVisibility` to override, and the HIG now says to use menu item icons "sparingly and with purpose". That is about menu *items*, not status item tint, so it does not settle this question — but it is the direction of travel and is worth noting in the deviation record. Also relevant: the beta reworked menu bar rendering and broke Bartender, Ice, Hidden Bar and others, so menu bar oddities on this OS are not automatically ours.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Normal and elevated render as template images and adopt the menu bar's own foreground colour
- [ ] #2 An open incident may use colour, and the tint is the design's muted tone rather than raw system red
- [ ] #3 Shape still distinguishes all four states with colour entirely absent, and a test asserts it
- [ ] #4 The deviation from design 2d is recorded with its reason
- [ ] #5 Verified on screen in a real menu bar alongside other template icons, in both light and dark
<!-- AC:END -->
