---
id: TASK-65.16
title: Screen 1p — Empty search in Apps never implies nothing is running
status: In Progress
assignee: []
created_date: '2026-08-09 02:25'
updated_date: '2026-08-09 05:07'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1p.png`. Existing implementation: search exists in the inventory (TASK-12); this empty state does not.

**What the design specifies**

The user searches "backupd" in the Apps tab and gets nothing, because `backupd` is a daemon and daemons do not belong to an application. A naive empty state would say "No results" and leave the user believing the process is not running — when it is, and is very possibly the cause of what they are investigating.

Instead:
- "**No application matches "backupd"**"
- "Only about one process in seven belongs to an application. Daemons and command-line tools — including **backupd** — run on their own and are listed under All processes."
- A button: "**Search All processes instead**"
- A count that proves the point: "**1 match in All processes** · 412 processes running"

So the empty state performs the search in the other scope, reports the hit count, and offers to switch — it knows the answer before the user asks.

**Why it belongs in the backlog rather than being folded into 1d**

This is the concrete expression of the finding CLAUDE.md records as a first-class data-model fact: only ~15% of processes belong to an application family, so a search scoped to applications will miss the majority of the process table. Every other screen states its limits; this is the one where the limit is most likely to mislead silently, because an empty list reads as an answer.

Depends on the All processes view existing (screen 1m).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An empty application search states why the result is empty in terms of how processes are grouped, never implying the searched process is not running
- [x] #2 The same search is evaluated against all processes and the number of matches is reported in the empty state
- [x] #3 A one-step route switches the search to the all-processes scope, preserving the search term
- [x] #4 The wording holds for a search that genuinely matches nothing anywhere, which must be distinguishable from one that matches only outside the current scope
- [ ] #5 Verified on screen against design/screens/1p.png with both a daemon name and a nonsense string
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`InventorySearchOutcome` (pure values, `MacSlowdown/Sources/InventorySearchOutcome.swift`) plus `InventorySearchEmptyView`, wired into `ProcessInventoryView`'s Apps branch.

The empty state runs the same predicate (`AllProcesses.matches`) over every process *before* it says anything, so the copy is derived from an answer rather than a guess. One predicate is used for both the rows shown in All processes and the count reported here; two would eventually disagree and the empty state would promise matches the other scope does not contain.

Two distinct outcomes, and the distinction is asserted:
- **Matches elsewhere** — "No application matches “backupd”" / "Only about one process in seven belongs to an application. Daemons and command-line tools — including backupd — run on their own and are listed under All processes." / button "Search All processes instead" (sets scope, leaves `query` untouched, so the term survives) / "1 match in All processes · 412 processes running".
- **Matches nowhere** — different title ("Nothing matches “xyzzy”"), no button at all, and "No matches in All processes · 412 processes running". Offering to switch to a scope that also has no answer would be a button that does nothing. The wording still states its own limits: the processes we cannot measure were searched too, by name.

Singular/plural handled at both boundaries (1 match / 1 process). The three views are combined into one accessibility element so VoiceOver hears the whole argument rather than three fragments.

The process count is taken over the whole table, never the filtered set, so "412 processes running" does not fall to 1 as the user types.

The All processes scope got the same treatment rather than an empty table: a search matching nothing there says how many processes were searched and how many of them are unmeasurable; a search matching only unmeasurable rows while they are hidden says so and points at the toggle.

Search also matches the daemon descriptor, so "Time Machine" finds `backupd`.

Tests: `Empty application search` suite, 7 tests, in `MacSlowdown/Tests/AllProcessesTests.swift`.

**AC #5 not verified** — no screen use was permitted in this session. Needs a look with both a daemon name and a nonsense string.
<!-- SECTION:NOTES:END -->
