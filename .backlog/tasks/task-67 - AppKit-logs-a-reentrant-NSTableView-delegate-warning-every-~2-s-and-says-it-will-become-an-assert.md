---
id: TASK-67
title: >-
  AppKit logs a reentrant NSTableView delegate warning every ~2 s, and says it
  will become an assert
status: In Progress
assignee: []
created_date: '2026-08-09 03:35'
updated_date: '2026-08-09 07:21'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed while investigating TASK-51.1, in a file that session did not own. Not investigated.

The running app logs an AppKit warning about a **"reentrant operation in its NSTableView delegate"** roughly every 2 seconds. The source is the inventory table (`ProcessInventoryView`), not the incidents pane. AppKit's own message states that this will become an assertion in a future release — so today it is noise, and at some macOS version it becomes a crash.

Every ~2 seconds is the sampling cadence, so the likely shape is that a sweep mutates the table's data while AppKit is inside a delegate callback for the previous update. SwiftUI's `Table` is `NSTableView`-backed, which is how a SwiftUI view produces an AppKit warning.

Worth knowing before starting: TASK-56 (sortable columns), TASK-60 (parent grouping), TASK-61 (expandable tree) and TASK-65.4 (inspector, adds a selection binding and per-family history recording) have all changed this table. TASK-65.4's work is on an unmerged branch, so reproduce against the merged state rather than against `main` alone.

Two reasons this is worth doing sooner than its severity suggests: a warning at 2-second intervals is drowning the log for anything else diagnosed from it, and the whole product depends on a table that updates continuously — this is the one control we cannot afford to have an assertion in.

Do not silence the warning. Find what reenters.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The reentrancy is reproduced and its trigger identified, against the merged state of the inventory table rather than main alone
- [ ] #2 The warning no longer appears in the log during sustained normal operation, verified by watching the log across several sampling cycles rather than by a single check
- [ ] #3 The fix addresses the reentrant call itself -- suppressing, delaying or silencing the warning is not acceptable
- [ ] #4 Table behaviour is unaffected: sorting, expansion, selection and continuous updates all still work, verified on screen
- [x] #5 If the cause turns out to be a SwiftUI Table limitation rather than our own code, that is recorded with evidence and the options are stated rather than worked around silently
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Note from TASK-65.13, which added the All processes view: it did not change the Apps table's structure, but **the All processes list is a second `Table` of the same shape**, so it may exhibit the same reentrancy warning when that scope is on screen. Check both scopes when reproducing, and confirm the fix covers both.

## What reenters: row reordering in SwiftUI's `Table`

Reproduced without the screen and bisected. **No fix was made** — see criterion #5.

AppKit's exact string, extracted from the shared cache under
`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/` (the copies listed
under `/System/Library/dyld/` cannot be opened):

> WARNING: Application performed a reentrant operation in its NSTableView
> delegate. This warning will become an assert in the future.

### How it was reproduced

`MacSlowdown/Tests/InventoryTableReentrancyTests.swift` — the real view in an
`NSHostingView` inside an offscreen `NSWindow`, driven by a real `MonitorStore`
at a 1 s cadence, with fd 2 redirected to a pipe. AppKit emits this via `NSLog`,
so stderr catches it; it does **not** appear in `log show`.

Two traps, both hit:

- **A nested `RunLoop.run(until:)` does not drive the store.** The first harness
  ran 57 layout passes and reported a clean log because the sampling task never
  got a turn — the table held **zero rows** throughout. Use an `async` test and
  `await Task.sleep`. The harness now asserts the table was populated and did
  change, so a clean result cannot again mean "nothing happened".
- `xcodebuild` does not forward the shell environment to the test process. The
  probes gate on `TEST_RUNNER_TASK67_PROBE=1`, which arrives as `TASK67_PROBE`.

### The finding

Warnings per run, 8–25 s windows against one live store:

| Variant | Warnings |
|---|---|
| Frozen rows, never changed | 0 |
| New array each sample, identical rows | 0 |
| Same identities, changing values, fixed order | 0 |
| Rows rotated by **one** position each sample | 0 |
| Rows **shuffled** each sample — identical ids *and* values | **21** |
| 15 rows, re-sorted each sample | **6** |
| Shipping Apps table | **13–16** |

The shuffle is decisive: identities, values and count are identical between
updates and only the order differs. One row moving is not enough; a bulk reorder
always is. Row count is irrelevant — 15 rows reordering warns as readily as 425.

### Dead ends — each ruled out by its own variant

None is the cause and none fixes it: the `sortOrder` binding; the selection
binding; sortable `TableColumn(value:)`; `DisclosureTableRow`; icons in the cell
body; the `safeAreaInset` footer; the `onChange` per-family history recording;
`.searchable`; `Section` in the rows builder; the data-driven `Table(data)`
initialiser; `.transaction { $0.disablesAnimations = true }`; duplicate row
identities (there are none — 0 duplicates in 743 flattened rows); and adding
`Equatable` to `InventoryRow` (tried, made no difference, reverted).

**So none of TASK-56, -60, -61, -65.4 or -65.13 caused this.** They only change
how much work each update does.

Also worth recording: counting rows whose *absolute index* changed reported ~700
of 721 rows "moved" when one process appearing at the top had shifted everything
below it by one. Compare rank within the ids common to both orderings instead.

### Both scopes

Both tables are susceptible — shuffling `AllProcessesRow` warns **21** times,
exactly like the Apps rows, so the row type is irrelevant. But the real All
processes view measured **0 warnings across five 25 s runs**: nearly every one of
its ~720 rows ties at zero CPU and is held in place by the name tie-break, while
the Apps table's ~425 family rows carry aggregated CPU that jitters, so ranks
swap every sample. It is latent there, not absent.

### Criteria

- **#1 met** — reproduced against the merged state (rebased onto `main`, which
  now carries TASK-65.4 and TASK-65.13) and the trigger identified.
- **#2 not met** — the warning still appears. No fix was made.
- **#3 not applicable yet** — nothing was suppressed, delayed or silenced.
- **#4 not verified** — needs the screen; not attempted. No production code was
  changed, so there is nothing new to regress, but that is an argument, not a
  verification.
- **#5 met** — a SwiftUI `Table` limitation, recorded with evidence, options
  stated rather than worked around.

### Options — the product owner's call, not mine

1. **Accept and file a Feedback with Apple.** Noise today; AppKit says it becomes
   an assert, which is a crash in a shipping build on some future macOS.
2. **Stop re-sorting on every sample** — hold the order and re-rank on a slower
   beat, or only when a rank changes materially. A sample that moves nothing warns
   not at all, so this reduces frequency but does not eliminate it. It is a
   behaviour change (arguably an improvement: a list that reshuffles every 2 s is
   hard to read), not a bug fix.
3. **Replace `Table` with `NSTableView` behind `NSViewRepresentable`**, where the
   update batching is ours. The only option that removes the reentrant call; means
   rebuilding sorting, disclosure, selection and accessibility by hand.
4. **Rejected: making row identity encode position.** Avoids the move path by
   replacing every row, and destroys selection and expansion stability across
   samples, which FR-027 requires.

### Files

- `MacSlowdown/Tests/InventoryTableReentrancyTests.swift` (new) — harness and the
  reproduction, which asserts the warning **is** present so whoever fixes it gets
  told.
- `MacSlowdown/Tests/InventoryTableBisectProbe.swift` (new) — the variants above.
- `probe/FINDINGS.md` — the finding, the harness traps, and the options.

No production source changed. Suite green at **671** (baseline 670 plus one
always-on harness guard); the slow probes are gated off by default. Re-run:

```
TEST_RUNNER_TASK67_PROBE=1 xcodebuild test -workspace MacSlowdown.xcworkspace \
  -scheme AllTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build \
  -only-testing:MacSlowdownTests/InventoryTableBisectProbe
```

Leaving status **In Progress**: the cause is settled but the decision is not.

CAUSE SETTLED, FIX IS A DECISION. Investigation merged; **no production code changed**, nothing silenced. Task stays In Progress because the choice below is the product owner's.

**What reenters: row reordering in SwiftUI's `Table`. Nothing of ours.** The decisive control was a *frozen* array of rows shuffled between samples — identical identities, identical values, identical count, only the order differing — producing 21 warnings in 25 s, where the same array left alone produces 0. A rotation by a single position produces 0; a bulk reorder always warns. Row count is irrelevant: 15 re-sorted rows warn as readily as 425.

**Ruled out, each by its own variant:** the `sortOrder` binding, the selection binding, sortable `TableColumn(value:)`, `DisclosureTableRow`, icons in the cell body, the footer inset, the `onChange` history recording, `.searchable`, `Section` in the rows builder, the data-driven `Table(data)` initialiser, `disablesAnimations`, duplicate identities (0 in 743 flattened rows), and `Equatable` on `InventoryRow`. **So none of TASK-56, TASK-60, TASK-61, TASK-65.4 or TASK-65.13 caused this.**

**Both tables are susceptible** — shuffled `AllProcessesRow`s warn identically, so the row type is irrelevant. But the real All processes view measured **0 warnings across five 25 s runs**, because nearly all its ~720 rows tie at zero CPU and are held still by the name tie-break. Latent there, not absent.

**How it was reproduced without the screen**, worth reusing: the real view in an `NSHostingView` in an offscreen `NSWindow`, driven by a real store at 1 s cadence, with fd 2 redirected to a pipe. AppKit emits this through `NSLog`, **not** os_log — which is why `log show` looked clean. Two traps: a nested `RunLoop.run(until:)` does not drive the store (the first harness ran 57 layout passes over an empty table and reported a clean result), and `xcodebuild` does not forward shell env, so probes gate on `TEST_RUNNER_TASK67_PROBE=1`.

## The decision

1. **Accept and file Feedback with Apple.** Noise now; a crash when AppKit makes it an assert.
2. **Stop re-sorting every sample** — re-rank on a slower beat, or only on material rank changes. Reduces frequency, does not eliminate. A behaviour change, but arguably an improvement: a list that reshuffles every 2 s is hard to read.
3. **Replace `Table` with `NSTableView` via `NSViewRepresentable`.** The only option that removes the reentrant call. Means rebuilding sorting, disclosure, selection and accessibility by hand.
4. **Rejected already:** encoding position into identity — it would destroy selection and expansion stability, which FR-027 requires.

Suggested order, for the owner to accept or overrule: do 2 now (it is a readability win on its own terms and cuts the frequency), file 1 in parallel, and hold 3 in reserve until Apple makes it an assert.
<!-- SECTION:NOTES:END -->
