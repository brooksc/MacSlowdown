---
id: TASK-107
title: Pull Claude Design's revised canvas and implement it in the app
status: Done
assignee: []
created_date: '2026-08-31 22:10'
updated_date: '2026-09-03 18:58'
labels:
  - ui
milestone: m-3
dependencies: []
priority: high
type: task
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Written before a context compaction so the state survives it.

**Where things stand, 2026-08-31.** The product owner ran the design-revision brief through Claude Design in the web canvas, having uploaded `requirements.md`, `CLAUDE.md` and `design/live-surfaces.md` into the project as context. Claude Design finished and handed the work back with the standard "Implement: `MacSlowdown Screens.dc.html`" instruction — meaning *build this in the app*.

**I misread that as "edit this file" and revised the local canvas myself** (1c, 1o, 2d), then came within one approval of pushing my version over Claude Design's via `DesignSync.finalize_plan`. The product owner stopped it. Nothing was written; the remote is intact.

Those local edits are now in `git stash@{0}` — kept only so a specific point can be compared against Claude Design's version, not to be reapplied wholesale. **Do not push a local canvas to the remote project.** The remote is authoritative for design; this repo's copy is a reference import.

**Project:** `f2b8c5b9-f801-4287-bea3-d8cdda998adb`, reachable through `DesignSync` once `/design-login` has been run (it has been). It is `PROJECT_TYPE_PROJECT`, not a design system, and holds `MacSlowdown Screens.dc.html`, `support.js` and `uploads/{CLAUDE.md,live-surfaces.md,requirements.md}`.

**The work.**

1. `DesignSync get_file` the canvas — about 216 KB, so do it with room in the context window.
2. Replace `design/MacSlowdown Screens.dc.html` with it and re-render `design/screens/*.png`. A headless render recipe that works: extract the document's `<style>` block plus one artboard into a temp file and screenshot it with `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless --screenshot=… --window-size=W,H --force-device-scale-factor=2`. Watch for content clipped by a fixed-height artboard — that bit me.
3. Read what Claude Design produced and report where it agrees and disagrees with the built app, especially the three things the brief asked about: the Now table's column budget, the run-queue presentation, and 2d's icon reconciliation.
4. Implement it, which is what was being asked for in the first place.

**Related decisions already recorded:** FR-046 amendment 5 demotes repeated relaunch (TASK-102), FR-006's run-queue amendment is proposed and unvalidated (TASK-103), and FR-057–062 now govern the live surfaces.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The remote canvas is fetched and becomes the repo's reference copy, with screens/*.png regenerated from it
- [x] #2 No local canvas is ever pushed over the remote
- [x] #3 The stashed local edits are reviewed for anything worth raising, then dropped
- [x] #4 Claude Design's revisions are reported against the built app before any code changes
- [x] #5 The design is implemented in the app, or each deviation is recorded with its reason per FR-060
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**The canvas is in, whole — but not via the MCP.** `DesignSync get_file` caps at 256 KiB and the revised canvas is 298,585 bytes, so the fetch came back truncated at exactly 262,144, cut mid-attribute. The product owner exported the project to `~/Downloads/MacSlowdown.zip` instead. The truncated fetch verified as a clean byte-prefix of the export, so it is the same document. **If this file needs fetching again, ask for an export; the MCP cannot deliver it.**

**1o is deleted, not annotated.** The old canvas had 1a-1p; the new has 1a-1n and 1p. 1o was "Repeated-crash incident — evidence is lifecycle events, not curves", and FR-046 amendment 5 makes it unreachable. 4c replaces it with a lifecycle record inside the process inspector.

**Turn 3 (3a-3f, the six app-icon directions) is new to the repo's copy**, though the renders already existed in `design/icons/`.

**The older turns were edited.** Diffed artboard by artboard; four changed, every one a correction toward something already settled here:
- 1j: "Stored encrypted in the app's own container" → "In MacSlowdown's own container, which no other app can read." CLAUDE.md explicitly forbids the first wording; the design had carried it since the first pass.
- 1f: repeated-quit row gone, "quit unexpectedly" gone, 9 incidents → 8, retention copy corrected.
- 1n, 2d: the "higher-priority path" claim replaced with the measured truth.

So the design now agrees with the repo's settled facts rather than contradicting them. Nothing in the older turns needs arguing with.

**Renders.** All 30 artboards regenerated from the canvas into `design/screens/`, autocropped to content against the `#dcd9d2` ground, each checked for content touching the bottom edge (the fixed-height clipping that bit an earlier session). None clipped, none blank. `design/screens/1o.png` removed.

Render recipe that works, for next time: extract the document's `<style>` block plus one `.dv-opt` block into a temp file, take `max(width:NNNpx)` found in the block as the artboard width, screenshot at that width + 80 with `--window-size=W,3200 --force-device-scale-factor=2`, then autocrop with PIL against the background colour and warn if the content bbox reaches the bottom edge. Chrome intermittently drops one screenshot per batch — check the file exists and retry the misses.

Committed as 7f652a3. No code changed.

**Implementation, 2026-09-03.** Four of Claude Design's five artboards are now built or deliberately deferred with a written reason (FR-060 discipline, criterion #5).

- **4a, the four-column table** — built (56f3eed). Seven columns to four; the two CPU columns collapse to one, which is the 60 s mean and the visible sort key. The instant survives as the sparkline's live end and in the accessibility label. PID and Started move to the inspector; the process count becomes a caption under the name. Narrows the table's minimum width from ~644 pt to ~504 pt, which bears on TASK-97.
- **4a, the state tiles** — built (fbc2798). `NowPresentation.stateHold` on memory pressure and thermals, stamped in `didSet` because pressure has two writers. Keeps the honest case separate: a state held for the whole watch says "At this state for the 22 min we have been watching" rather than dating a change we never saw.
- **4c, the lifecycle demotion** — built via TASK-102 (b0e9e27). 4c's *richer* inspector treatment (per-generation timeline, the "what this does and doesn't say" panel, Copy lifecycle record) is **not** built and is not claimed.
- **4d, the menu bar icon** — the build was already right, as 4d says. One real gap closed (fbc2798 precursor): severe was separated from an ordinary open incident by **colour alone**, which FR-034 forbids. Severe now fills the badge; ordinary keeps the ring. Derived from `tint` so fill and colour cannot drift.
- **4e's corrections** — already true in the app. Checked rather than assumed: no "encrypted", no "quit unexpectedly", no higher-priority-path claim anywhere in `MacSlowdown/Sources` or `Metrics/Sources`. The app had these right before the design did.
- **4b, run-queue** — **not built, deliberately.** TASK-103's measurement refutes its numbers; see that task. The vocabulary, lane graphic and never-list remain correct and are buildable once a threshold exists.

**Criterion #3.** Stash reviewed and dropped. Nothing was worth extracting: the 2d recolour I had made is settled by 4d endorsing the build's template-except-severe rule, 1o is deleted from the canvas outright, and 1c is superseded by 4a.

**Criterion #2 held throughout** — nothing was ever pushed to the remote.

**Two things left for the product owner**, both flagged rather than decided:
1. **A copy defect in 4b.** Its legend reads "Running now — 8" and "Waiting for a turn — 88", but two allowed phrasings say "12 threads per core **waiting**". 96/8 = 12 includes the running thread; waiting is 11 per core. The unit 4b actually chose is depth-including-running, which is what makes "keeping up is 1" coherent — so the arithmetic is fine and the word "waiting" is wrong on those two lines. Exactly the FR-057 failure the design exists to prevent.
2. **The unattributed footer band.** 4a moves the unattributed row from a pinned list item into the footer band, revising work completed on the owner's own instruction. Held rather than done.

1141 passing at the close.
<!-- SECTION:NOTES:END -->
