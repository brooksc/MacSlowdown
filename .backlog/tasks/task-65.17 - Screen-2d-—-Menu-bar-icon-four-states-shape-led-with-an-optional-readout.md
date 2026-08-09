---
id: TASK-65.17
title: 'Screen 2d — Menu bar icon: four states, shape-led, with an optional readout'
status: To Do
assignee: []
created_date: '2026-08-09 02:26'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/2d.png`. Alternatives explored and superseded: `design/screens/2a.png` (gauge ring), `2b.png` (stacked bars), `2c.png` (silhouette swap). 2d is the recommended spec and develops 2b's silhouette. No backlog item exists for 2a-2c — they are rejected options.

Existing implementation: `MacSlowdownApp.swift` renders `Image(systemName: store.severity.symbolName)` with an accessibility label (TASK-11).

**What the design specifies**

The constraint stated up front: the icon is ~16 pt tall in a crowded, sometimes translucent strip, so colour alone cannot carry meaning.

**Four states, not three** — our severity model has three:
| State | Meaning | Colour | VoiceOver |
|---|---|---|---|
| Normal | No rule is close to firing | green | "MacSlowdown, normal" |
| Elevated | A threshold is crossed but hasn't lasted long enough to be an incident | yellow | "MacSlowdown, elevated, CPU" |
| Incident open | Sustained past the duration threshold. Badge appears | red | "MacSlowdown, severe, memory, 11 minutes" |
| Muted or paused | Still recording, just not interrupting. **Never silently invisible** | grey | "MacSlowdown, muted for 41 more minutes" |

**Elevated** is the addition that matters: it is the visible expression of FR-006's sustained-not-transient rule. Without it the icon jumps from fine to incident and the duration threshold is invisible. **Muted** must never mean "looks the same as normal".

**Optional readout**: icon only (default), with CPU percentage, or with a 60-second sparkline.

**Rules, quoted:**
- Shape carries the state; colour only reinforces it. In Increase Contrast the fills go to pure black/white outlines.
- Transitions cross-fade over 250 ms and are rate-limited to one change per 2 s, so the icon never strobes.
- No animation, ever — "a spinning menu bar icon during a slowdown is the single most irritating thing this app could do."
- The icon is drawn on the high-priority path, so it keeps updating even if the main window is busy (the claim screen 1n makes to the user).
- **Red never appears for a workload the user marked expected; that shows as yellow at most.** — the per-app rules of screen 1j reaching the menu bar.

**Gap against what we render today**

We use SF Symbols keyed to a three-value severity. Verified working: the accessibility label reads "MacSlowdown: Normal". Missing: the elevated and muted states, the shape-led custom silhouette, the incident badge, the optional readouts, the rate limiting and cross-fade, the Increase Contrast treatment, and the expected-workload cap.

Note FR-034 requires severity never be conveyed by colour alone, and TASK-15 (accessibility baseline) is parked awaiting someone with VoiceOver — the VoiceOver strings above are part of this spec and cannot be signed off without that.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The icon distinguishes four states including elevated and muted, and muted is never visually identical to normal
- [ ] #2 State is carried by shape, with colour only reinforcing it, and the treatment holds under Increase Contrast and Reduce Transparency (FR-034)
- [ ] #3 An open incident carries a badge, and severity plus duration are available to VoiceOver
- [ ] #4 State changes are rate-limited and cross-faded so the icon cannot strobe, and nothing animates
- [ ] #5 An application the user marked as expected never drives the icon to its most severe state
- [ ] #6 The optional readouts (percentage, sparkline) are available and off by default
- [ ] #7 The icon keeps updating while the main window is behind, verified under real load rather than assumed
- [ ] #8 VoiceOver strings verified by a person using VoiceOver, or explicitly recorded as not verified (see TASK-15)
<!-- AC:END -->
