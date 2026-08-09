---
id: TASK-61
title: 'Expandable process tree in Apps &amp; Processes (FR-003, FR-027)'
status: In Progress
assignee: []
created_date: '2026-08-08 23:02'
updated_date: '2026-08-09 01:24'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today the inventory shows one row per family with an aggregate figure, and the individual processes beneath it — which FR-003 requires we preserve — are not reachable from the interface at all. Helium has 18 processes and ChatGPT 25; a user can see the total but not what makes it up.

Make each family row a disclosure row: collapsed by default, showing the family name and its summed CPU and memory, expanding to the individual processes.

Why collapsed by default, and why this is the right shape. The question a user actually has is "which application is using the most", and a flat list of 800 processes buries that under helpers. The aggregate answers it; the expansion explains it. This also matches what a user can act on: window titles are unavailable without Screen Recording (measured, TASK-46), so we cannot say which renderer belongs to which tab, and the app performs no process control by design (FR-037). A user who finds Helium expensive will close tabs, not pick a renderer to kill. The tree exists to explain a number, not to offer a target.

That framing should shape the copy inside the expansion: it says what each process is and what it is using, and does not imply the user should do something to an individual row.

Depends on TASK-60 for the cases that matter most. Grouping by executable path alone leaves 25 unbundled processes as their own top-level rows — 14 zsh under Warp, 11 backlog under ChatGPT. Those are exactly the children a user would expect to find nested. Without ppid grouping, a Warp session still appears as fourteen unrelated rows.

Things that will be got wrong if not stated:
- Sorting must apply to families, and independently within an expansion. Sorting a flattened list would scatter children away from their parents.
- Expansion state is keyed on family identity, not row index. Rows reorder every sample; an index-keyed disclosure would collapse and expand the wrong rows on refresh — the same defect selection already avoids.
- The aggregate must equal the sum of the children shown, or the tree contradicts the row above it (FR-055, FR-043).
- A child whose metrics the sandbox denies stays listed with its usage marked unavailable, never as zero.
- Disclosure must be operable from the keyboard and its state announced (FR-034).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each family is a disclosure row, collapsed by default, showing summed CPU and memory
- [ ] #2 Expanding lists the individual processes with their own figures
- [ ] #3 The family total equals the sum of the children shown, including any marked unavailable
- [ ] #4 A child whose metrics are denied is listed with its usage marked unavailable, never as zero
- [ ] #5 Sorting orders families, and orders children within an expansion, never a flattened list
- [ ] #6 Expansion state is keyed on family identity and survives re-sorting and the next sample
- [ ] #7 Disclosure is operable from the keyboard and its state is announced to VoiceOver
- [ ] #8 No copy in the expansion implies the user should act on an individual process
- [ ] #9 A 'System processes' group collects every process owned by another uid, named and counted, expandable like any other family
- [ ] #10 The system group's total is the measured unattributed remainder, labelled Calculated, and no individual process inside it is ever given a number
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Measured while answering a question about ppid recycling and launchd (probe/FINDINGS.md).

A 'System processes' group is exactly well-defined. Of 828 processes, 599 are our uid and ALL are measurable; 229 are other uids and ALL are denied. The correlation is total — not one exception either way — so grouping on uid != getuid() captures precisely the set we cannot measure, with no false members.

This lets the FR-055 unattributed row become a real expandable family rather than a bare number: it can name and count its 229 members while still refusing to give any of them an individual figure. The total stays what it is today, the measured difference between host busy and the sum of what we could read, labelled Calculated.

What must not happen: dividing that remainder among the named processes. The remainder also contains kernel and interrupt time and any process that started and exited between samples, so attributing it to the 229 would be a fabricated measurement (FR-036). Name and count, never measure.

Also worth recording because it is an easy conflation: 'parented by launchd' is NOT 'unmeasurable'. 690 processes are launchd-parented and 464 of those are ours and fully measurable. Only uid decides.
<!-- SECTION:NOTES:END -->
