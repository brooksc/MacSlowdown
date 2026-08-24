---
id: TASK-89
title: 'Menu bar icon: template-first, colour only for an open incident'
status: In Progress
assignee: []
created_date: '2026-08-24 04:03'
updated_date: '2026-08-24 04:41'
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
- [x] #1 Red appears only for a severe incident — critical memory pressure, critical thermal state, or three conditions at once
- [x] #2 Every other state, including a high or moderate open incident, renders as a template image in the menu bar's own foreground colour
- [x] #3 Shape distinguishes all four states with colour entirely absent, asserted by a test
- [x] #4 The deviation from design 2d is recorded with its reason
- [ ] #5 Verified on screen in a real menu bar alongside other template icons, in both light and dark
- [ ] #6 Verified on screen: a severe incident does turn it red
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The rule

Product owner, 2026-08-23, declining all three offered options and stating the principle instead: **"red should be a rare event e.g. something is really wrong on the machine."**

That maps exactly onto a line the detector already draws. `IncidentDetector.severity` returns `.severe` for critical memory pressure, critical thermal state, or three conditions breaching at once — the machine genuinely in trouble, not the machine working hard. So:

    tint = (state == .incident && incidentSeverity == .severe) ? .red : .none

Everything else is a template image. No green, no yellow, no grey.

## Why colour had to leave the state

`MenuBarIconState.tint` was a property of the state alone, so it could not see severity. It is deleted; the tint is now computed in `MenuBarIcon.tint(state:inputs:)` and carried on `MenuBarIconPresentation`, which is the value that already knows everything. `MenuBarIconTint` collapses from `green/yellow/red/grey` to `none/red`, and `.none` renders as `nil` rather than a colour, so "no colour" is a state the type can express rather than a grey that happens to look neutral.

`MenuBarGlyphRenderer` now sets `isTemplate` whenever no colour is actually in use — which is every state but a severe incident, and every state at all under Increase Contrast. The badge and the mute slash take `Color.primary` when untinted so they survive the template render; the badge still appears for **every** open incident, severe or not, because "an episode is being recorded" is a fact we are not allowed to withhold.

The system red is kept rather than design 2d's muted tone, deliberately: a colour this rare has to be worth looking at when it finally appears.

## Deviations from design 2d, recorded

1. Normal is not green, elevated is not yellow, muted is not grey. In a real menu bar the state a user sees essentially always is *normal*, so the design's rule amounted to a permanent green light beside a strip of template icons.
2. Red no longer marks any open incident, only a severe one. An alarm that is on most of the time is not an alarm.

The design's own precedent supports this shape: 2d already withholds red for a workload the user marked expected. That cap is untouched and composes — a capped incident is `.elevated`, so it was never a candidate for colour.

## Tests

`MenuBarIconTintTests`, 5 tests: only severe is red; quiet and elevated use no colour; muting a severe incident takes the colour with it but keeps the badge; **all four states remain distinguishable with colour entirely absent**; and an uncoloured incident is still badged. The last two are the ones that matter — they assert that nothing was lost.

`mutedIsNeverIdenticalToNormal` lost its colour assertion; its two shape assertions are what the design's requirement actually rested on.

`-only-testing:MacSlowdownTests`: one failure, the pre-existing TASK-91 container-isolation issue.

## Not verified

Both on-screen criteria. Nobody has seen the template render in a real strip, in either appearance, and a severe incident has not been produced to see the red.
<!-- SECTION:NOTES:END -->
