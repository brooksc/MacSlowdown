---
id: TASK-65.21
title: >-
  Now banner: no severity colour, condition-first headline, and the missing
  third action
status: In Progress
assignee: []
created_date: '2026-08-09 22:53'
updated_date: '2026-08-09 23:41'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by comparing a real screenshot against `design/screens/1c.png` on 2026-08-09 (`screenshots/verify2/02-now.png`). The window was correct at 900x600, so these are content differences, not layout accidents.

**1. The banner carries no severity treatment.** The design draws it on an amber field with a filled orange warning disc and an amber `HIGH · 6 MIN` chip. We draw flat `.quaternary` grey with a plain SF Symbol triangle and a grey chip. The design is FR-034-safe — the word "HIGH" is present, so colour only reinforces — and dropping the colour loses the at-a-glance triage the whole screen is organised around. Severity colour must be added *with* the word, never instead of it.

**2. The headline names the condition; the design names the application.** Design: "Xcode is using most of the CPU". Ours: the joined condition labels, e.g. "Repeated unexpected quits for 3 minutes, 15 seconds". The design's form answers the user's actual question first. Any change must keep the attribution honest — "Xcode is using most of the CPU" is a heuristic claim and needs its confidence to survive, which is exactly what the summariser already computes.

**3. The third action is missing.** Design has "Builds are normal for Xcode" beside "Open incident" and "Bring Xcode forward" — the per-app policy of screen 1j reaching the banner, so a user can mark a workload expected at the moment it annoys them. We show only two buttons. `PolicyStore.setPolicy` already exists and is wired, so this is presentation only.

**4. The card grid wraps at the default window size.** `LazyVGrid(.adaptive(minimum: 190))` fits three cards across a 900 pt window, so "Thermals &amp; power" drops to a second row below the fold. The design shows four across. Either the minimum comes down, or the default window is wider, or the grid is a fixed four-column layout that compresses.

**5. Card status dots.** Design puts a small coloured square beside each card title; we use an SF Symbol. Both carry non-colour meaning, so this is cosmetic — recorded for completeness, not as a defect.

Note what is *not* a difference and must not be "fixed": the disk card's "no history retained" note and the per-row "Not retained" cells are deliberate honesty about what `MetricsHistory` keeps, and the design's sparklines there would be fabricated. See `SparklinePresentation.perFamilyHistoryExplanation`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The incident banner conveys severity with colour AND a word, and the treatment holds under Increase Contrast and Reduce Transparency (FR-034)
- [x] #2 The banner headline leads with what is happening and to which application where one is known, and carries its confidence label rather than stating a cause outright (FR-013, FR-038)
- [x] #3 A third banner action lets the user mark the named application's load as expected, writing through the existing PolicyStore
- [ ] #4 All four metric cards are visible without scrolling at the default window size
- [ ] #5 Verified on screen against design/screens/1c.png, or the criterion is left unchecked with the reason
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch `worktree-agent-a1b87f5923549c5c5` (commit eaa667e). Files: `MacSlowdown/Sources/NowPresentation.swift`, `MacSlowdown/Sources/MainWindowView.swift`, new `MacSlowdown/Tests/IncidentBannerTests.swift` (12 tests). Full suite: 1044 passing, 0 failing, 5 skipped.

**1. Severity treatment.** `NowPresentation.BannerTreatment.resolve(increaseContrast:reduceTransparency:)` on the `MenuBarIconTreatment` pattern: default = faint tinted fill; Increase Contrast = no tint at all, neutral field with a foreground-colour border; Reduce Transparency = opaque field with a solid tinted border (a wash is exactly what that setting asks us not to show). Contrast wins when both are on. Hue is moderate/high/severe -> yellow/orange/red, and the **glyph shape now differs per severity** (circle/triangle/octagon) so the three levels stay distinct with every colour deleted. The chip still carries the word. Read from `@Environment(\.colorSchemeContrast)` and `@Environment(\.accessibilityReduceTransparency)` rather than NSWorkspace, so the banner redraws when a setting is switched with the window open.

**2. Headline.** `NowPresentation.bannerHeadline(incident:conditionHeadline:)`. Subject comes from the incident's **recorded** attribution, never live state — the live leader is whatever is busy now and would put a passer-by's name on the episode. Confidence travels with it as a caption under the headline ("Likely · high confidence"), built from `Evidence.heuristic.label` + `Confidence.label`, and folded into the accessibility label. Judgement made: "X is using most of the CPU" is a claim about a majority, and the observed incident had a leader at 380% of 500% total with 38% unattributable — so the design's wording is used only when leaderShare > 0.5 of the recorded peak total, and otherwise the headline still leads with the app but reads "X is the largest measurable use of the CPU". No application known -> the summariser's condition headline stands, unqualified (a measured statement carries no confidence).

**3. Third action.** "Heavy load is expected for X" writes an `ApplicationPolicy(classification: .expected)` keyed on the recorded contributor's bundleID/bundlePath through `store.policies.setPolicy`, then **reads the store back** and reports from that — `setPolicy` returning is not evidence a rule exists (FR-017/FR-050). Failure wording claims nothing happened. The button is offered only where the incident attributed itself to an application: "heavy load is expected" is meaningless for a repeated-quit episode and there would be nothing to key the rule on.

**4. Card grid.** `.adaptive(minimum:)` cannot express "four cards, four across" — it packs as many columns as fit, which gave three at 900 pt and would give six columns for four cards at 1250 pt. Replaced with `ViewThatFits(in: .horizontal)` over 4/2/1 flexible columns (minimum 150). `memoryDetails` is now read once and passed in, because ViewThatFits builds all three candidates to measure them and that property calls `host_statistics64`.

**Not verified on screen** (no screen use this session; the machine was in use). Precise checks left for whoever can look, at the default 900 pt window with an open incident:
- #1: the banner draws on a tinted field matching severity, with the severity word still present; then toggle System Settings > Accessibility > Display > Increase Contrast (expect all colour gone, plain field, 2 pt foreground border) and Reduce Transparency (expect an opaque field with a solid tinted border, no wash). Compare against `design/screens/1c.png`.
- #4: all four cards — CPU, Memory pressure, Disk, Thermals & power — on one row without scrolling at the default window size; then narrow the window and confirm it steps to two columns rather than clipping.
- #5: side-by-side against 1c.
Criteria #2 and #3 are checked on the strength of the pure rules being tested and the wiring being in the view; their *rendering* is part of the unchecked #5.
<!-- SECTION:NOTES:END -->
