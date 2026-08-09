---
id: TASK-65.14
title: 'Screen 1n — Now, when our own sampling falls behind'
status: To Do
assignee: []
created_date: '2026-08-09 02:25'
labels:
  - ui
  - core
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1n.png`. A variant of screen 1c. Existing implementation: `MonitorStore.freshness` and a stale indicator exist (TASK-47, TASK-32/FR-032); `MainWindowView.swift:54` reads `if case .stale(let age) = store.freshness`. The full treatment does not.

**What the design specifies**

When the machine is too busy for us to sample on time, the whole screen changes register rather than showing stale numbers as if they were current.

- A banner: "**These readings are catching up** — The system is too busy to sample right now, so we're showing the last reading we trust rather than guessing. Recording is still running — nothing is being lost, it's just arriving late." with "Retrying every second".
- Metric cards carry a warning glyph and an age instead of a timestamp: CPU "97 % of 10 cores — **as of 45 seconds ago**", Memory pressure "Warning — as of 45 seconds ago". Cards that *are* current say so: Disk "204 MB/s write — current", Thermals & power "Serious — current · on battery". So freshness is per-metric, not global.
- The contributor list is headed "from the reading 45 seconds ago — not updating right now", with each row carrying its own "45 s ago".
- Footer: "Greyed values are the last complete reading, not a current one. **Nothing here is estimated forward.**"
- And the reassurance that matters: "The menu bar icon runs on a higher-priority path, so it keeps updating even while this window is behind."

**Why this screen is a requirement and not a nicety**

FR-032 and the never-fabricate rule meet here. The failure mode this prevents is the one every monitoring tool has: under the exact conditions the user bought the tool for, it silently shows numbers from a minute ago. The design's answer is per-metric age, an explicit refusal to extrapolate, and a stated guarantee that the menu bar surface stays live.

That last claim needs verifying, not assuming — whether our menu bar update path genuinely survives load better than the window is a measurement, and TASK-47 is the place to check what was already established.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When sampling falls behind, the screen states so plainly and says recording is continuing
- [ ] #2 Freshness is shown per metric, with the age of each stale reading, and metrics that are still current are distinguished from those that are not
- [ ] #3 Stale values are visually distinct and the screen states that nothing is estimated forward (FR-002, FR-032)
- [ ] #4 Contributor lists carry the age of the reading they came from
- [ ] #5 The claim that the menu bar surface keeps updating while the window is behind is verified by measurement under real load, or the claim is removed
- [ ] #6 Verified on screen against design/screens/1n.png under induced load, not by simulating a stale state in a test
<!-- AC:END -->
