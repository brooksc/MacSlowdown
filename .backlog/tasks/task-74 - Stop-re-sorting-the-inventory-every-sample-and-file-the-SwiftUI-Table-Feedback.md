---
id: TASK-74
title: >-
  Stop re-sorting the inventory every sample, and file the SwiftUI Table
  Feedback
status: To Do
assignee: []
created_date: '2026-08-09 18:23'
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
- [ ] #1 The inventory does not re-rank on every sample; the ordering settles and changes only when a rank change is material or the user asks for it
- [ ] #2 Clicking a column header still re-sorts immediately -- damping applies to data churn, never to user intent
- [ ] #3 Selection and expansion survive across samples, without encoding position into row identity (FR-027)
- [ ] #4 The reentrancy warning's frequency is measured before and after, using TASK-67's harness, and the figures recorded
- [ ] #5 Both the Apps and All processes tables are covered
- [ ] #6 The existing reentrancy test is updated to match the new behaviour rather than deleted, and still fails loudly if the warning returns to its old frequency
- [ ] #7 A Feedback is filed with Apple including the reproduction, and its number is recorded here
<!-- AC:END -->
