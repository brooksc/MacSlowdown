---
id: TASK-55.1
title: >-
  Our own resident memory reads 3-22x the FR-030 budget, and two surfaces
  disagree
status: In Progress
assignee: []
created_date: '2026-08-09 02:14'
updated_date: '2026-08-09 03:27'
labels:
  - core
milestone: m-3
dependencies: []
parent_task_id: TASK-55
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed while screenshotting the running Debug app on macOS 27. Not measured rigorously — that is the work.

TASK-55 measured the real app at **92 MB** against FR-030's 100 MB budget and closed on that. What the app displayed during this session:

- Now screen, `MacSlowdown itself:` line — **418.4 MB**, and **307.4 MB** in a sample a few minutes later.
- Apps & Processes, the `MacSlowdown` row — **2.26 GB**, with a process count of 1.

Two problems, and they should be separated:

1. **The absolute figure.** Even the smallest of these is over three times the 100 MB budget; the largest is 22x. Either something regressed since TASK-55, or 92 MB was measured under conditions the app does not normally run in. A tool that must not become part of the slowdown cannot hold 2 GB.

2. **The two surfaces disagree.** Both paths read `residentBytes` — `Presentation.selfCost` (via `MonitorStore.ownResidentBytes`) for the Now line, and `InventoryRow`'s family sum for the table row. For a family with one process those should be the same number. The samples were minutes apart so the gap is not proven to be a code difference, but a 5x spread between two readings of the same quantity needs explaining before either is trusted.

Note this was a Debug build with SwiftUI previews linked; measure Release before drawing conclusions. Do not "fix" this by changing which number is displayed — establish what the real figure is first.

Related: `MonitorStore.swift:86-101` carries the reasoning behind measuring from the app rather than the headless harness, and `isWithinMemoryBudget` compares against `FR030Budget.residentBytes`. Nothing currently surfaces when that check fails.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Resident memory of the running Release app is measured over a sustained run of at least 300 s and the figure recorded, including whether it is steady or climbing
- [ ] #2 The Now screen's self-report and the Apps & Processes row for MacSlowdown show the same value at the same moment, or the interface explains why they differ
- [ ] #3 If the measured figure exceeds FR-030's 100 MB budget, either the cause is found and fixed, or requirements.md is amended with the measured figure and a stated reason -- the budget is not left silently breached
- [x] #4 A sustained run distinguishes a fixed cost from growth over time, so this is not reported as a leak without evidence (FR-044)
- [x] #5 The result is recorded where the next person will find it, including whether TASK-55's 92 MB figure still reproduces and under what conditions
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Measured, not fixed. Full write-up in `probe/FINDINGS.md` ("Our own memory: resident size is the wrong number for FR-030"). macOS 27.0 (26A5388g), M2. All figures below are from the **Debug** build that was already running (pid 22488, up 31 min at first sample), plus a sandboxed probe.

## AC#2 — the two surfaces never disagreed

Both `Presentation.selfCost` (via `MonitorStore.ownResidentBytes`) and `InventoryRow`'s family sum read `pti_resident_size`, from the same sweep. No code path was found that makes them differ for a one-process family.

The spread was time, not code. Over a 755 s log the app's resident size read **3321 MB**, fell to **884 MB in about ten seconds** with the app doing nothing, and held at **809-874 MB** for the remaining 555 s. `phys_footprint` did not move across that event: 396 MB before, 396 MB after.

`vmmap` explains it: 3.0 GB of the 3.3 GB was mapped files under `/Library/Caches/com.apple.iconservices.store/*.isdata` (3012 regions) — clean, shared, file-backed pages the kernel evicts for free. Two honest readings of our own resident size can differ by 2.5 GB minutes apart.

**Resident size is the wrong statistic for our own budget.** `phys_footprint` is the stable one, is what Activity Monitor shows, and is readable for self even sandboxed (`proc_pid_rusage` is self-only — which is exactly why FR-043 uses resident size for *other* processes).

AC#2 left unchecked: I could not put the app on screen to see both surfaces at one moment. What is established is that no code difference exists and that the underlying quantity is unstable enough to produce the reported spread on its own.

## AC#1, AC#4 — sustained run

Debug app, 1191 s (`probe/footprintlog.sh`), and 755 s at 5 s resolution (`probe/memlog.sh`):

| Statistic | Resident size | phys_footprint |
|---|---|---|
| Range | 809 - 3323 MB | 218 - 397 MB |
| Median after t=150 s | 837 MB | **292 MB** |
| Trend | flat after eviction | flat, two discrete steps |

**Steady, not climbing.** Footprint is flat to ±2 MB over 17 minutes between two step increases (291 → 327 MB) that coincide with newly sighted applications. That is a fixed cost per application first displayed, not unbounded growth. Not a leak, and not to be described as one (FR-044).

Release not measured — see "still open" below.

## Cause: `NSImage.tiffRepresentation` costs 70 MB per icon

`ProcessIconCache` (`Metrics/Sources/ProcessNaming.swift:121-130`) compares `candidate.tiffRepresentation` against the generic icon's to decide whether an icon is real, which FR-002 requires. Measured by `probe/Sources/self-memory-probe.swift`, sandboxed, 117 naming bundles, each stage in its own process:

| Stage | Resident | phys_footprint |
|---|---|---|
| `sysctl KERN_PROC_ALL` (808 pids) | +0.6 MB | +0.6 MB |
| `proc_pidpath` (775 paths) | +0.2 MB | +0.3 MB |
| `Info.plist` names (113/117) | +2.3 MB | +1.2 MB |
| `runningApplications` | +0.5 MB | +0.2 MB |
| **one** `tiffRepresentation` | **+196 MB** | **+148 MB** |
| 117 × `icon(forFile:)`, pooled, retained | +18.5 MB | **+5.9 MB** |
| 117 × `tiffRepresentation`, pooled | +1698 MB | +1693 MB |
| 117 × the app's exact sequence, unpooled | +7017 MB | +7958 MB |

A single `tiffRepresentation` is **70 MB** — the icon carries representations to 1024×1024 at every scale and TIFF flattens all of them into one `Data`. Holding all 117 `NSImage`s costs 5.9 MB; the cache is not the problem, the equality test per cache miss is. Draining the autorelease pool does not return it, nor does releasing the cache (measured). The app's 292 MB steady footprint is largely malloc's large-block high-water mark — `vmmap` shows `Malloc Large (empty)` at 320 MB virtual / 103 MB resident.

## Proposed fix (measured in a probe, NOT applied)

Draw both icons into a 32×32 RGBA bitmap and compare the PNG bytes:

| Method | Agrees with `tiffRepresentation` | Footprint cost |
|---|---|---|
| `NSImage.name()` | 0/117 — does not discriminate | +0.03 MB |
| **32 pt rasterised comparison** | **117/117** | **+0.17 MB** |

All 117 classified "real", so agreement alone is weak — the negative control settles it: `/bin/ls` and `/usr/bin/true` are *generic* under both methods, and a non-existent path is *real* under both (IconServices returns the generic **document** icon, which is neither method's reference). The cheap method discriminates.

Not applied because `Metrics/Sources/ProcessNaming.swift` was owned by a concurrent session (TASK-57.1) and this task's brief excluded it. **This is the handoff: whoever owns that file should make the swap, and it should then be re-measured against the running app.**

## AC#3 — fix versus amend

**Recommendation: fix, and then amend the wording — not amend the number.**

- The 100 MB budget looks achievable. The sampling path alone is 20.7 MB (`probe/overhead/run.sh 300`, this machine, this day: `cpu 0.830% steady state OK / memory 20.7 MB resident +13.0 MB growth OK / disk 0.00 MB/hour OK`). Holding every icon is 5.9 MB. The 292 MB is dominated by one avoidable allocation pattern, so there is no evidence yet that 100 MB is the wrong target.
- What **does** need a spec amendment is *which quantity the budget names*. FR-030 says "resident memory ≤100 MB". Resident size for this process swings between 809 MB and 3323 MB with no change in behaviour, so as written the budget is untestable. Proposed wording, **for the user to approve — `requirements.md` not edited**:

  > Resident memory ≤100 MB, measured as the application's own `phys_footprint` (`proc_pid_rusage`, available for self), sampled over a run of at least 300 s and judged on the median. Resident size (`pti_resident_size`) is reported for *other* processes because footprint is not readable for them; it is not the statistic this budget is held against, because it counts clean shared file-backed pages the kernel evicts for free.

- Until the fix lands the budget is breached at **292 MB median footprint (Debug)** and should be recorded as breached, not quietly re-baselined.

## AC#5 — does TASK-55's 92 MB reproduce?

**Not currently.** The running Debug app was at 292 MB footprint / 837 MB resident. 92 MB is consistent with a reading taken before the inventory had been opened, since the icon cost is incurred per application *first displayed* — but that is a hypothesis fitting the evidence, not a measurement. TASK-55 did not record which build or which screens had been opened, which is why the figures cannot be reconciled. The FINDINGS.md entry states the rule so the next figure is comparable: build, screens opened, and ≥300 s.

## Also observed, outside this task's scope

The running Debug app used **12.2% of one core** averaged over 755 s, against FR-030's 1% budget. Heavily confounded — I was building and running probes throughout, the app raises its cadence under load, and I could not see whether its window was open. Recorded so it is not lost; it needs its own clean measurement, not a conclusion from this one.

## Still open (needs a human with the app on screen)

1. **Release build, sustained run.** Not measured. Launching an `LSUIElement` app puts an item in the menu bar; the session was explicitly barred from using the screen.
2. **AC#2 as literally written** — both surfaces observed at the same moment.
3. **Post-fix figure.** Whether the 32 pt comparison brings the app under 100 MB can only be confirmed against the running app.
4. Nothing surfaces to the user when `isWithinMemoryBudget` is false. Still true; not changed here.

## Files

Added `probe/Sources/self-memory-probe.swift` (modes `stages` / `icons` / `tiff` / `asapp` / `cheap`), `probe/build-probe.sh` (builds any probe source sandboxed — `build-sandboxed.sh` hardcodes the Tier 0 source), `probe/memlog.sh`, `probe/footprintlog.sh`. Appended to `probe/FINDINGS.md`. No product source changed.

Tests: `AllTests` Debug — **386 passing**, 2 failing (`EndToEndIncidentTests.realSlowdownProducesOneIncident`, `cadenceRisesUnderLoad`). Both pass in isolation on a quiet machine (`-only-testing:MetricsTests/EndToEndIncidentTests` → both ✔). They are load-sensitive: they synthesise a slowdown and expect recovery, and the user's app plus concurrent builds kept the machine busy. Not a regression from this work, which touched no product code. Baseline was 382; the count rose because other sessions added tests concurrently.

## Handoff update — ProcessNaming.swift ownership released (not yet acted on)

TASK-57.1's session replied on thread `processnaming-ownership` declining the change and releasing the file. Its reasoning, which I agree with: the change belongs to TASK-55.1's acceptance criteria, so landing it inside a TASK-57.1 commit would separate the measurement, the notes and the code; and it has neither the before-figure nor the harness to re-measure with, so it would only hand back an unverified change.

**Not applied in this session.** The brief for this session named `Metrics/Sources/ProcessNaming.swift` as off-limits. A peer releasing its own claim does not by itself widen that instruction, and the verification loop cannot be closed here regardless — confirming the fix means seeing the running app's footprint, which needs the screen. Landing an unverified change to a shipping file to close a budget breach would be the same error FR-050 warns against: treating a plausible fix as a measured outcome. Raised with the user for a go-ahead instead.

**Merge hazard to handle before editing, reported by that session:** `ProcessNaming.swift` has changed substantially on worktree `agent-a62dd287a59f27be1`, commit `fa10b6e`, not yet merged to main — roughly 90 lines added to the `ProcessNaming` enum (`isVersionNumber`, `isBundleIdentifier`, `isNonName`, `unidentified`, `installationName`, `declaredName`) and `resolve`, `labelled` and `accessibilityLabel` rewritten. `ProcessIconCache` was **not** touched, so the icon-comparison hunk does not overlap textually, but branching from an older main gives a conflicting file-level history. Rebase onto or merge `fa10b6e` first, then edit `ProcessIconCache` in isolation.

**Relevant to re-measurement:** that change makes `resolve` do slightly more work per process on the cache-miss path only (a `lastPathComponent` and two string classifications; no new syscalls, no filesystem access). Identity resolution is still cached by `(pid, start time)`, so steady state should be unchanged — but if the 292 MB median footprint moves after rebasing, rule that out first before attributing the shift to the icon change.

Deprioritised 2026-08-08, not abandoned. The product owner deferred FR-030's numeric budget: overhead is measured and reported, but does not gate work on functionality or UX. `requirements.md` FR-030 and `CLAUDE.md` both record this.

What this changes: criterion #3 ('either the cause is fixed or requirements.md is amended') is now **satisfied by the deferral itself** — the budget was amended, by the product owner, with the measured evidence recorded. The 292 MB footprint median is no longer a breach to clear.

What survives regardless, because it is a measurement finding rather than a budget question:
- Resident size is not a testable quantity here (809-3323 MB over one run vs 218-397 MB footprint, the difference being evictable icon-cache mappings). Any future budget must name `phys_footprint`, median over >=300 s.
- The headless harness is not representative of the app; it runs no SwiftUI.
- The premise that two surfaces disagreed was DISPROVED. Both read `pti_resident_size` from the same sweep; the spread was elapsed time, not code. Do not re-open that as a defect.

The `NSImage.tiffRepresentation` icon comparison (~+148 MB per cache miss, verified 32x32 replacement at +0.17 MB agreeing 117/117 with a negative control) is still worth landing on correctness grounds -- it is a large avoidable allocation, cheap to remove -- but it is no longer urgent.

## Fix landed — 32 pt icon fingerprint (commit 3b4fed0)

Coordinator authorised editing `Metrics/Sources/ProcessNaming.swift` after TASK-57.1 released it. Rebased onto `fa10b6e` first; the only conflict was an additive one in `probe/FINDINGS.md` (both sessions appended sections), resolved by keeping both. `ProcessIconCache` was untouched by `fa10b6e` as reported.

**Change:** `ProcessIconCache` compares a 32×32 raster instead of `NSImage.tiffRepresentation`. The comparison **fails closed** — an icon that cannot be fingerprinted is treated as generic, so the interface omits an icon rather than claiming a placeholder is the application's own (FR-002).

**Before/after, measured against the shipping class.** `probe/Sources/icon-cost-probe.swift` is compiled together with `Metrics/Sources` via the new `probe/build-with-metrics.sh`, so it runs the real `ProcessIconCache` rather than a reimplementation that could drift; the `before` arm reproduces the old comparison over the same bundles. One process per arm — malloc does not return large blocks promptly, so measuring both in one process charges the second for the first's high-water mark. Three consecutive pairs, 105 bundles classified in every run:

| Pair | Before, growth | After, growth | Before, peak | After, peak |
|---|---|---|---|---|
| 1 | +5659.1 MB | **+8.6 MB** | 7779.4 MB | **11.3 MB** |
| 2 | +8555.4 MB | **+7.7 MB** | 8593.3 MB | **10.4 MB** |
| 3 | +8552.4 MB | **+8.2 MB** | 8590.3 MB | **10.8 MB** |

Roughly **700× less**. The peak now sits inside FR-030's 100 MB budget where it previously exceeded it by 85×.

**Correctness.** An `agree` arm runs both classifications over the same 105 bundles in one process: **0 disagreements**. The negative control is the one that matters — every bundle on this machine classifies as real, so zero disagreements alone would also be scored by a comparison that never says "generic". `/bin/ls`, `/usr/bin/true` and `/usr/sbin/notifyd` come back *generic* under both methods. That control is kept in `Metrics/Tests/ProcessNamingTests.swift`, not only in the probe, as the coordinator asked.

**FR-030 harness not re-run.** `OverheadHarness.swift` contains no reference to icons, so this change cannot move its figure; the earlier 300 s run stands at `0.830% CPU steady state OK / 20.7 MB resident OK / 0.00 MB/hour OK`. Re-running it now would measure contention, not the app — load average was 18.6-22.5 throughout, from other sessions' test spinners.

**Tests: 399 passing, 3 failing**, all three environmental and all three verified:
- `CPUWorkloadTests.singleCoreWorkload` — passes in isolation.
- `EndToEndIncidentTests.cadenceRisesUnderLoad` — passes in isolation.
- `EndToEndIncidentTests.realSlowdownProducesOneIncident` — fails at `EndToEndIncidentTests.swift:72`, which is the suite's **own** `Issue.record("Skipped: baseline CPU is ...")` guard declining to run because baseline CPU exceeded 60% of the machine. Confirmed against `uptime`: load average 22.49 on 8 cores, with six `yes` spinners and `syspolicyd` at 96% from concurrent sessions. Not a regression — the test is reporting the machine's state, which is what that guard exists to do.

The count rose from 386 because `fa10b6e` brought in TASK-57.1's tests and this change adds two.

**Still not verified, and left unchecked:** whether the app's 292 MB median footprint now falls under 100 MB. The probe shows the icon path fell from ~8.5 GB to ~8 MB, but the app-level figure needs the running app on screen. AC#1, AC#2 and AC#3 remain unchecked for that reason.

### Note on the FR-030 deferral vs this worktree

The deprioritisation note above says `requirements.md` FR-030 now records the deferral. **That edit is not in this worktree** (`agent-ada86c029670a3a6b`, based on `fa10b6e`): FR-030's acceptance criteria here still read "Idle CPU median ≤1% of one core on reference hardware; resident memory target ≤100 MB; disk writes ≤10 MB/hour absent incidents; thresholds may be revised with documented evidence." So the spec change lives on a branch not yet merged here.

I have therefore left AC#3 unchecked rather than checking it on the strength of a note I cannot verify in my own tree. Whoever merges should confirm the FR-030 wording once the branches are together, and check AC#3 then if the deferral does cover it.

One thing the deferral does **not** dispose of: FR-030's acceptance criteria as written still say "resident memory", and resident size is not a testable quantity for this process (809-3323 MB over a single run, the difference being evictable icon-cache mappings). If a numeric budget is ever reinstated, it needs to name `phys_footprint` and a median over ≥300 s, or it will be untestable again. The proposed wording is in the AC#3 section above.
<!-- SECTION:NOTES:END -->
