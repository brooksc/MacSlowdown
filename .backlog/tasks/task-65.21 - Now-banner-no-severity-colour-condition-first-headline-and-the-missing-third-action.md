---
id: TASK-65.21
title: >-
  Now banner: no severity colour, condition-first headline, and the missing
  third action
status: In Progress
assignee: []
created_date: '2026-08-09 22:53'
updated_date: '2026-08-09 23:18'
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
- [ ] #2 The banner headline leads with what is happening and to which application where one is known, and carries its confidence label rather than stating a cause outright (FR-013, FR-038)
- [ ] #3 A third banner action lets the user mark the named application's load as expected, writing through the existing PolicyStore
- [ ] #4 All four metric cards are visible without scrolling at the default window size
- [ ] #5 Verified on screen against design/screens/1c.png, or the criterion is left unchecked with the reason
<!-- AC:END -->
