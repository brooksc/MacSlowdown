---
id: TASK-65.22
title: >-
  Apps &amp; Processes: names truncate, the footer is seven lines where the
  design has one, and the long tail is not aggregated
status: In Progress
assignee: []
created_date: '2026-08-09 22:53'
updated_date: '2026-09-17 18:47'
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
- [x] #1 The Name column gets the majority of the table width and ordinary application names are not truncated at the default window size
- [ ] #2 A truncated display name is distinguishable from a name truncated by p_comm's 16-byte limit (FR-002)
- [x] #3 The footer carries one explanatory sentence plus a single separated census line; the memory, disk and CPU-convention caveats move beside the figures they qualify rather than being deleted
- [ ] #4 Applications below the visible threshold are aggregated into one 'Other applications' row whose figures make the column sum honest
- [ ] #5 An expanded family collapses its sub-threshold helpers into a single counted row
- [x] #6 Verified on screen against design/screens/1d.png, or the criterion is left unchecked with the reason
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**#1, #3 and #6 done 2026-09-17; #2 already held; #4 and #5 are deliberately not built — see below.**

**#1 — names are no longer truncated at the default width.** The cause was not the Name column being too narrow but every column being equally wide: not one of the five `TableColumn`s in All processes declared a width, so SwiftUI divided the table evenly and a three-character CPU reading held as much room as a process name. Every column now states min/ideal/max and the name takes the slack. Seen at 480 pt — narrower than the default — with "Brave Browser Helper (Renderer)" and "com.apple.WebKit.WebContent.Development" whole: `design/verified/2026-09-17/previews/all-processes-480.png`. The Apps table's name column carries `min: 220, ideal: 420`.

**#2 was already satisfied** and is now confirmed by looking. A `p_comm`-truncated name is marked by `nameIsShortened` and renders with an ellipsis *in the name itself* ("mediaanalysisd…"), while a name truncated by the column is cut by the table; the two are also distinguished in the spoken label, which says "name shortened by the system". Visible in the 480 pt render.

**#3 — the footer is one sentence plus a separated census line.** It was three paragraphs rendering as five to seven lines under the table, and sixteen lines at the narrow width TASK-97 measured, where it left room for **two rows**. A footer that crowds out the table it explains has stopped explaining anything.

The short form keeps the two facts a reader will otherwise take for defects — "Applications only, and rows hold their places for 10 s while you read" — because an application-only list reads as a list that has lost its daemons, and a damped order under a column headed CPU reads as broken sorting, which is exactly what TASK-63 turned out to be. The criterion's instruction that the caveats move rather than be deleted is met by a disclosure carrying `InventoryCensus.fullExplanations`, composed from the same constants so it cannot drift. The memory and per-app-disk caveats **gain** reach: they were previously only in a `.help` tooltip, unreachable from the keyboard and invisible to anyone not hovering.

The same shape was applied to the All processes footer, which additionally held a **verbatim second copy** of `InventoryCensus.residentMemoryCaveat` — the FR-060 duplication that TASK-80 was created by. It reads the constant now.

**#4 and #5 (aggregating the long tail into "Other applications", and collapsing sub-threshold helpers) are not built, and I recommend they are not built as specified.** The reason is measured, not stylistic. Every row this would fold away is a *named, measured* process, and the product's governing honesty is that it says what it measured and what it could not. An aggregate labelled "Other applications" would be the one row on the screen whose figure is a sum the user cannot decompose — sitting directly beneath a "System processes" row that exists precisely to mark the activity we genuinely *cannot* break down. Two rows that look alike and mean opposite things is a worse defect than a long tail.

It is also not clearly a problem any more. The complaint was recorded when the footer was seven lines and names truncated at twenty characters; both are now fixed, and the tail is sorted by a 60 s mean rather than by an instant (TASK-90, TASK-95), so it no longer churns. **This needs the product owner's call** — it is a design judgement about a screen they have used and I have not.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-17 02:31
---
**Seen on screen 2026-09-16** in the running app (macOS 26.6.2, VM). Two of this task's three complaints are confirmed still open; the third has moved.

- **The long tail is still not aggregated.** Design 1d calls for an "Other applications — 16 apps, each below 12%" row. The build lists every daemon individually: trustd, BiomeAgent, WindowManager, iconservicesagen…, loginwindow, linkd, System Events, secd, deleted, bash, cfprefsd, tccd, duetexpertd, Control Center, CursorUIViewService, proactived… — sixteen visible rows, most under 1%. Confirmed open.
- **The footer is three lines**, where the design has one. Better than the seven recorded here originally, still not one. Confirmed open.
- **Truncated names**: largely fixed, but not by this task. [[TASK-117]] gave every column in the *All processes* table a declared width, and names that used to cut at about twenty characters now show whole. The Apps table's own column header still truncates — it reads "CPU, 60 s me…" rather than "CPU, 60 s mean".

**What is right, so a fix does not regress it.** The Apps · 58 / All processes · 635 segmented control matches 1d exactly, and the census footer matches its sentence structure word for word — design "20 apps · 63 of 412 processes belong to an app · 234 not measurable  Updated 1 s ago", build "58 apps · 74 of 635 processes belong to an app · 289 not measurable  Updated 1 s ago". The System processes aggregate carries a lock and a disclosure triangle, as 1d's family rows do.

**Not checked:** 1d's right-hand inspector (identity, 15-minute chart, safe actions, grouping controls). It presumably needs a selected row and the capture had none, so this says nothing about whether it is right — only that it was not looked at.

Screenshot `03-apps.png` from the 2026-09-16 VM run.
---
<!-- COMMENTS:END -->
