---
id: TASK-65.14
title: 'Screen 1n — Now, when our own sampling falls behind'
status: In Progress
assignee: []
created_date: '2026-08-09 02:25'
updated_date: '2026-08-09 21:13'
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
- [x] #1 When sampling falls behind, the screen states so plainly and says recording is continuing
- [x] #2 Freshness is shown per metric, with the age of each stale reading, and metrics that are still current are distinguished from those that are not
- [x] #3 Stale values are visually distinct and the screen states that nothing is estimated forward (FR-002, FR-032)
- [x] #4 Contributor lists carry the age of the reading they came from
- [x] #5 The claim that the menu bar surface keeps updating while the window is behind is verified by measurement under real load, or the claim is removed
- [ ] #6 Verified on screen against design/screens/1n.png under induced load, not by simulating a stale state in a test
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## The on-screen check criterion #6 still needs (nobody has looked)

1. `./run-menubar.sh`, open the main window on **Now**, and leave it open.
2. Induce the load in a terminal: `for i in $(seq 1 $(sysctl -n hw.logicalcpu)); do yes > /dev/null & done` plus two extra spinners so nothing is left idle for us. Leave it 60 s or more. `killall yes` to stop.
3. **What must appear.** The "These readings are catching up" banner at the top of Now with "Retrying every 1 s" on its right (cadence rises to investigation under load, FR-031). CPU, Disk and Thermals & power cards greyed, each with a warning triangle and "as of N seconds ago" where N *increases every second while nothing arrives*. Memory pressure card **not** greyed, reading "current · reported when it changes". The contributor list headed "Contributors — from the reading N seconds ago — not updating right now", every row carrying an "N s ago" column. Two footnotes at the bottom: "…Nothing here is estimated forward." and the menu bar sentence.
4. **What counts as a failure.** (a) The ages freeze while the banner is up — the one-second clock is not running and the screen is lying again. (b) The banner appears but the cards still say "current" — card freshness is not wired. (c) No banner at all under full saturation — either the threshold is too loose or the loop is genuinely keeping up; check `lastUpdate` before concluding. (d) Any figure changes while its card says "as of N seconds ago" — that would mean something is being estimated forward. (e) The extra caption row per card and the extra row column reintroduce TASK-75's height blow-up; the window sizing suite still passes, but confirm by eye.
5. **Against the mock.** Two deliberate divergences from `design/screens/1n.png`, neither of which is a defect: Disk is greyed here (it comes from the same sampling pass, so calling it current would be false), and the footer's menu bar sentence is the opposite of the mock's promise (criterion #5).
6. While the load runs, watch the menu bar icon. It must **not** look more responsive than the window. Seeing it lag by up to 2 s is the expected behaviour, not a bug.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Which metrics can genuinely be stale independently

Determined by reading `MonitorStore.run()`, not by assumption. One pass of the loop assigns `attribution`, `families`, `contributionIndex`, `enumeration`, `memoryPressure`, `thermalState`, `power`, `swapUsage`, `pagingRates`, `diskRates` and `lastUpdate` in sequence with no await between them. **Those all share one age exactly**, so giving them separate per-metric ages would be an invented distinction. Design 1n draws Disk as "current" while CPU is stale; that is not true of this app, and the card now says what is true here instead (the mocks are directional).

There are exactly two clocks genuinely independent of that pass:

1. **Memory pressure.** `MemoryPressureMonitor` is a `DispatchSourceMemoryPressure` on a global queue; the kernel pushes a transition the moment it happens. Until now the store only *copied* `pressureMonitor.level` on the next sweep, so the published value was as late as everything else. It now adopts the push directly — which is what FR-007's two-second requirement asks for anyway, and is what entitles the pressure card to read "current · reported when it changes" while every other card carries an age.
2. **Storage / volume capacity** (`lastStorageCheck`), on its own 30 s cadence — up to 30 s behind the sample even when sampling is healthy. Not a Now card, so not surfaced here, but it is the other real clock.

Thermal state and power *could* be made event-driven (`NSProcessInfoThermalStateDidChange`, IOPS notifications) but are not subscribed today, so they are reported with the sampling pass. Left alone: claiming an independence we have not wired would be the same fabrication in the other direction.

## A defect found on the way

`MonitorStore.freshness` can only be recomputed **when a sample arrives**. A loop that has stopped arriving therefore leaves it reading `.current` indefinitely — during exactly the stall this screen exists to describe. The Now screen no longer reads it; it derives each age at render time from `lastUpdate` against a one-second clock of its own (`NowView.tickAgeClock`, cancelled with the view). Sampling cadence and UI refresh stay separate (DR-03). `store.freshness` is untouched and the popover still uses it.

## Criterion #5 — the menu bar claim is FALSE, and is removed

Design 1n promises: *"The menu bar icon runs on a higher-priority path, so it keeps updating even while this window is behind."* There is no such path.

Evidence, all structural:
- `MonitorStore` is `@MainActor @Observable`. `run()` is main-actor isolated and `task = Task { await self?.run() }` is created in a main-actor method, so the sampling loop **runs on the main actor**. `sampler.snapshot()` and `FamilyGrouper.group` are synchronous calls, so their cost (2.90 ms warm, 819 ms cold per CLAUDE.md) occupies the main actor inline.
- `MenuBarIconLabel(store: store)` and `MainWindowView(store: store)` read **the same `@Observable` store on the same actor**. Neither has a separate sampling path, queue or QoS. There is exactly one place a new reading comes from.
- TASK-65.17's `MenuBarIconModel` adds `MenuBarIconRateLimiter`, one state change per 2 s. So the icon is not merely no fresher than the window — it is permitted to be **up to two seconds behind it**. Pinned by the test `The menu bar icon may lag the window by up to the rate limit`.

No measurement can make an architecturally impossible claim true, so the criterion's "or the claim is removed" branch is the correct one and no harness was written. The footer says what is true instead: *"The menu bar icon is drawn from this same reading, on the same update path, so it is never more up to date than this window."* A test asserts that "higher-priority" and "keeps updating" do not appear, so the reassurance cannot be quietly restored without first making it true.

## What changed

- `NowPresentation.swift` — new `MetricFreshness` (`noReadingYet` / `current(age:)` / `stale(age:)` / `reportedOnChange`) with caption, glyph, spoken form and row caption; `metricFreshness(observedAt:now:cadence:)`; `staleThreshold(cadence:)` = `max(2×cadence, cadence+2 s)` so a 1 s investigation cadence does not read stale between samples; `ageInWords`, `intervalInWords`, `catchingUpBanner`, `contributorHeaderNote`, `staleFootnotes`.
- `MainWindowView.swift` — `NowView` gains the `now` clock and `sampleFreshness` / `memoryFreshness`; the old `staleBanner` is replaced by design 1n's banner including "Retrying every 1 s"; all four `MetricCard`s take a freshness and render a caption line (glyph + words) with the value greyed only *in addition to* that; the contributor list gains a stale title line; `ContributorRow` gains a per-row age; the stale footnotes lead the footnote block.
- `MonitorStore.swift` — three small edits only: added `memoryPressureIsLive`; `start()` now passes an `onChange` to `pressureMonitor.start` that adopts the transition on the main actor and sets the flag; `stop()` clears the flag.
- Tests: 11 in `NowPresentationTests.swift` (`NowFreshnessTests`), 2 in `MonitorStoreWiringTests.swift` (`MemoryPressureLivenessTests`).

## FR-034

Greying is never the only signal. Every stale figure carries `exclamationmark.triangle` plus the words "as of N seconds ago", and `MetricCard.accessibilityLabel` speaks `freshness.spoken` immediately after the value ("not current, as of 45 seconds ago"). Contributor rows append "from the reading 45 s ago".

## Tests

Baseline on this worktree at `main` (5b1d84a): **981 passed, 4 failed, 5 skipped** — `EndToEndIncidentTests.realSlowdownProducesOneIncident` (busy machine, expected) and three `MemoryPressureMonitorTests` that assume the machine starts at `.normal` pressure and fail when it is genuinely at `.warning`. That third case is a pre-existing machine-state sensitivity worth knowing about, not a regression.

After: **1003 passed, 0 failed, 5 skipped** (the four baseline failures had aborted the rest of their suites, which is most of the difference). All 13 new tests pass, confirmed in isolation with `-only-testing:MacSlowdownTests/NowFreshnessTests -only-testing:MacSlowdownTests/MemoryPressureLivenessTests`.

## Not verified

**Criterion #6 is deliberately unchecked.** It requires a person at the screen under induced load and this was terminal-only work. The precise check to run is recorded in the plan field. Nothing about the on-screen appearance — layout of the extra caption row, whether the ages visibly tick, whether the banner reads well at window width — has been seen.
<!-- SECTION:NOTES:END -->
