---
id: TASK-65.22
title: >-
  Apps &amp; Processes: names truncate, the footer is seven lines where the
  design has one, and the long tail is not aggregated
status: To Do
assignee: []
created_date: '2026-08-09 22:53'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by comparing a real screenshot against `design/screens/1d.png` on 2026-08-09 (`screenshots/verify2/04-apps.png`), taken after TASK-75 so the window was a correct 900x600 and the table scrolled properly.

**1. The Name column is far too narrow and truncates almost everything.** Observed: "System…", "MacSlo…", "iStat Me…", "Amphet…", "1Passwo…". The design gives Name roughly half the table width; we give it about 120 pt because CPU, Memory, PID, Started and Processes each take a fixed share. The name is the one column that carries the meaning, and it is the one being cut. Note this compounds an FR-002 problem TASK-81 already touched: a truncated *display* is not the same as a truncated `p_comm`, and the user cannot tell which they are looking at.

**2. The footer is seven paragraphs; the design has one sentence.** Ours stacks the census, freshness, the "this view lists applications only" explanation, the CPU convention, the P/E core note, the resident-memory caveat, the per-app-disk caveat and a how-to line — roughly 180 pt of a 600 pt window, more vertical space than the table gets. The design keeps **one** sentence in the footer ("This view lists applications only…"), puts the census on a single separated bottom bar ("20 apps · 63 of 412 processes belong to an app · 234 not measurable   Updated 1 s ago"), and moves the memory and disk caveats **into the inspector**, where they sit beside the number they qualify. None of the copy should be deleted — it should be relocated, and this is where the FR-030-style "say it where it applies" rule actually pays.

**3. The long tail is not aggregated.** The design ends the list with a single "Other applications · 16 apps, each below 12% · 73% · 3.4 GB" row. We list all 66. The aggregate row is what makes the column sum honest without a 66-row scroll.

**4. Expanded families list every child.** The design collapses small helpers into "19 more helpers below 1%". We show all of them.

**5. The scope control is in a row of its own below the toolbar; the design puts it in the toolbar** beside the title, with search to its right. That is a whole row of vertical space in a window that is short on it.

**6. Sort affordance.** The design marks the sorted column "CPU ↓" in the accent colour. We use a chevron. Cosmetic, recorded for completeness.

Verified working and not to be re-opened: the segmented control, search field, census and internal scrolling are all reachable and correct since TASK-75, and column headers stay pinned.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Name column gets the majority of the table width and ordinary application names are not truncated at the default window size
- [ ] #2 A truncated display name is distinguishable from a name truncated by p_comm's 16-byte limit (FR-002)
- [ ] #3 The footer carries one explanatory sentence plus a single separated census line; the memory, disk and CPU-convention caveats move beside the figures they qualify rather than being deleted
- [ ] #4 Applications below the visible threshold are aggregated into one 'Other applications' row whose figures make the column sum honest
- [ ] #5 An expanded family collapses its sub-threshold helpers into a single counted row
- [ ] #6 Verified on screen against design/screens/1d.png, or the criterion is left unchecked with the reason
<!-- AC:END -->
