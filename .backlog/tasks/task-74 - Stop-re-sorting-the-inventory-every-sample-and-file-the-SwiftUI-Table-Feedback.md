---
id: TASK-74
title: >-
  Stop re-sorting the inventory every sample, and file the SwiftUI Table
  Feedback
status: In Progress
assignee: []
created_date: '2026-08-09 18:23'
updated_date: '2026-08-09 19:48'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Product owner decision, 2026-08-09**, on the options recorded in TASK-67. Take option 2 now, file option 1 in parallel, hold option 3 in reserve.

TASK-67 proved the cause: **SwiftUI's `Table` performs a reentrant `NSTableView` delegate operation whenever rows are reordered.** Nothing of ours causes it — a frozen array shuffled between samples, with identical identities, values and count, produces 21 warnings in 25 s; the same array left alone produces none. AppKit says the warning becomes an assert in a future release.

## What to do

**Stop re-ranking on every sample.** Hold the displayed order and re-rank on a slower beat, or only when a rank changes materially. A sample that moves nothing warns not at all, so this cuts the frequency sharply without eliminating it.

Treat this as a **readability change first and a warning-frequency change second** — that is the honest framing. A list of ~425 application rows that reshuffles every 2 seconds is genuinely hard to read: the row a user is reaching for moves under the pointer. The design's inventory (screen 1d) shows a stable ordering, so this brings us closer to it rather than away.

**Also file a Feedback with Apple**, with TASK-67's reproduction attached — it is small, self-contained and decisive, which is exactly what makes a Feedback actionable.

## Constraints

- **Do not silence, delay or suppress the warning** to make it go away. TASK-67's criterion #3 stands: any change must act on the reordering, not on the reporting.
- Ordering must stay **correct**, only less twitchy. A user who clicks a column header gets an immediate re-sort — the damping applies to data-driven churn, not to user intent.
- Selection and expansion must survive the change (FR-027). Do not reach for position-encoded identity; TASK-67 already rejected it for exactly this reason.
- The All processes table is latent rather than clean: its ~720 rows mostly tie at zero CPU and are held still by the name tie-break. Whatever damping is chosen should cover both tables.
- `MacSlowdown/Tests/InventoryTableReentrancyTests.swift` currently asserts the warning **is** present, so whoever fixes it gets told. Update that expectation deliberately with the behaviour — do not delete the test.

Reversal is safe: if damping proves worse to use than the churn it prevents, revert it and fall back to accepting the warning until Apple acts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The inventory does not re-rank on every sample; the ordering settles and changes only when a rank change is material or the user asks for it
- [ ] #2 Clicking a column header still re-sorts immediately -- damping applies to data churn, never to user intent
- [ ] #3 Selection and expansion survive across samples, without encoding position into row identity (FR-027)
- [x] #4 The reentrancy warning's frequency is measured before and after, using TASK-67's harness, and the figures recorded
- [x] #5 Both the Apps and All processes tables are covered
- [x] #6 The existing reentrancy test is updated to match the new behaviour rather than deleted, and still fails loudly if the warning returns to its old frequency
- [ ] #7 A Feedback is filed with Apple including the reproduction, and its number is recorded here
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The code half is done. The Feedback is drafted, not filed.

### The damping rule, exactly

`MacSlowdown/Sources/StableOrder.swift`. The displayed order is **held** between
samples and changes for exactly three reasons:

1. **The user asked.** A column heading clicked, a search term changed, a scope
   switched -> `reset()`, and the next refresh adopts the ranking whole,
   immediately. Damping applies to data churn and never to user intent.
2. **A row appeared or disappeared.** Departures are dropped and arrivals are
   inserted at their ranked position straight away, so the *set* on screen is
   always current -- a settled order is not a licence to show a dead process or
   hide a new one. That is an insert/remove, not a reorder: the rows already on
   screen keep their order relative to each other.
3. **The settle interval has passed.** `OrderStability.settleInterval = 10 s`.
   A changed ranking replaces the held order only once 10 s have passed since the
   order last changed. A ranking that has *not* changed is free and does not
   restart the clock, so a quiet table adopts its next real change at once.

**Why 10 s and not a magic number.** It is an upper bound on how out of date the
*order* may be, chosen as roughly five sampling intervals: long enough to see a
row, move to it and click it without it moving out from under the pointer, short
enough that nobody reads a stale ranking for long. It is stated to the user, not
buried: `OrderStability.explanation` appears in both tables' footers -- "Rows keep
their places while you read: the numbers update every sample, and the list
re-ranks at most once every 10 seconds. Processes that start or stop are added and
removed straight away; sorting or searching re-ranks it at once." A test asserts
the sentence carries the interval the code actually uses, so the two cannot drift.

**Framing, honestly:** this is a readability change first. ~500 application rows
reshuffling every 2 s is hard to read, and the design's inventory (screen 1d)
shows a settled list. The warning frequency follows from it; it is not the
justification. Nothing about logging, os_log or asserts was touched.

### The values stay live -- this was the trap to avoid

`StableOrder` holds **positions, never rows.** Every `settle` call is given the
freshly ranked rows and emits *those* rows, only re-sequenced. It never caches a
row and re-emits it later. Emitting a remembered row would put a stale reading on
screen as though it were current, which FR-002 and FR-032 forbid; the test
"Held order still shows the newest values" pins it.

### Selection and expansion

Untouched, and untouchable: rows are matched by their own `id` (`pid:startTime`
or the family id) and nothing about position enters identity. Selection and
expansion are keyed on the same ids, so they survive every reorder (FR-027).
TASK-67 rejected position-encoded identity for exactly this reason and this change
does not go near it. Test: "Identity never carries position". **Not verified on
screen** -- see below.

### Before/after, criterion #4

TASK-67's harness, `InventoryTableReentrancyTests`, 20 s windows, real store at
1 s cadence, ~500 rows. Command:

```
TEST_RUNNER_TASK67_PROBE=1 nice xcodebuild test -workspace MacSlowdown.xcworkspace \
  -scheme AllTests -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build \
  -only-testing:MacSlowdownTests/InventoryTableReentrancyTests
```

| | warnings per 20 s |
|---|---|
| **Before** (production sources stashed back to `main`) | **12, 14** |
| **After** | **2, 2, 1**, and 1 again on a fourth confirming run |

About an 85% reduction, and about what the arithmetic predicts: ~2 re-ranks per
20 s instead of ~20, one warning per reorder. The before figures sit inside
TASK-67's recorded 13-16, so the machine was behaving comparably then and now.
**The machine was busy with other agents' builds throughout.** That load should
not distort these figures -- the harness counts events, not time, and the before
and after runs were minutes apart under the same conditions -- but they were not
made on a quiet machine.

Note for whoever repeats this: **`tuist xcodebuild` swallows test `print` output.**
Run raw `xcodebuild` against `MacSlowdown.xcworkspace` or the counts are invisible.
The first attempt reported a clean-looking run with no numbers in it at all.

### The existing test, criterion #6

`inventoryScopeStillReenters` -> `inventoryScopeReordersRarely`. Not deleted; its
expectation moved with the behaviour. It used to assert the warning *was* present.
It now asserts the **frequency**: at most `2 * (1 + 20/settleInterval)` = 6 in a
20 s window -- the reorders a settled order permits (first paint plus two), doubled
for headroom, still less than half the old 12-14. If the table goes back to
re-ranking every sample it fails loudly and says so in those words. Zero warnings
is reported as news rather than asserted either way, since that would mean Apple
had fixed it.

### Both tables, criterion #5

Apps (`ProcessInventoryView`, including each expanded family's children, which
jitter for the same reason the aggregate does) and All processes
(`AllProcessesView`, measurable and unmeasurable sections damped separately).
TASK-67 measured 0 warnings in the All-processes scope because nearly every row
ties at zero CPU and is held by the name tie-break -- latent, not absent -- so it
is covered by the same rule rather than left to luck.

### Tests

- New: `MacSlowdown/Tests/StableOrderTests.swift`, 12 tests over the pure rule --
  hold, adopt after the interval, user intent, departures, arrivals in rank,
  several arrivals, children, live values, identity, the clock, and the sentence.
- `-only-testing:MacSlowdownTests`: **485 passing, 0 failing.** (The brief's ~462
  baseline was not re-measured on this tip; 12 of the difference is the new suite.)
- Reentrancy suite re-run with the new assertion: passed, 1 warning.
- `MetricsTests` not run -- nothing under `Metrics/` was touched.

### Not verified, and the checks that would settle it

**Nothing was seen on screen.** No launch, no screenshots.

- **Criterion #2 left unchecked.** A header click calls `reset()` and re-ranks on
  the same turn, and a unit test covers the rule, but "re-sorts immediately" is a
  claim about what a person sees. The check: run the app, click the CPU heading,
  and confirm the list rearranges in that instant rather than up to 10 s later;
  then type in the search field and confirm the same.
- **Criterion #3 left unchecked.** Identity is position-free and tested, so the
  second half of the criterion holds in code; the first half is on-screen
  behaviour. The check: expand a family, select a row, leave it for a minute
  across several samples and a re-rank, and confirm the selection, the expansion
  and the scroll position are where you left them while the numbers change.
- Whether 10 s is the right interval **in use** is a judgement, not a measurement.
  It is one constant in one place; the footer copy and the test bound both derive
  from it, so changing it needs no other edit. If the settled order proves worse
  to use than the churn it prevents, reverting this branch restores the old
  behaviour exactly.

### Criterion #7 -- not done, and not mine to do

Filing needs the product owner's Apple account. The Feedback is written out in
full -- title, area, steps, expected/actual, configuration, TASK-67's bisection
table, and a single-file self-contained reproduction that shuffles 25 identical
rows in a `Table` -- at **`probe/feedback-swiftui-table-reentrancy.md`**. Filing
it should be copy-paste. Record the Feedback number here afterwards.

The draft says plainly that our damping is a workaround and not a fix: SwiftUI
still reenters whenever rows genuinely move, and `NSViewRepresentable`
(TASK-67's option 3) remains the only complete escape. TASK-67 itself can now
close on the decision, but its criterion #2 ("the warning no longer appears") is
still **not** met and will not be met by this work.

### Files

- `MacSlowdown/Sources/StableOrder.swift` (new) -- the rule, pure and testable
- `MacSlowdown/Sources/ProcessInventoryView.swift`, `AllProcessesView.swift` --
  wiring and footer copy
- `MacSlowdown/Sources/InventoryRow.swift`, `AllProcessesRow.swift` -- conformance
- `MacSlowdown/Tests/StableOrderTests.swift` (new),
  `MacSlowdown/Tests/InventoryTableReentrancyTests.swift`
- `probe/feedback-swiftui-table-reentrancy.md` (new), `probe/FINDINGS.md`

Branch `worktree-agent-a532fc0854a32cbed`, committed, **not merged**.
<!-- SECTION:NOTES:END -->
