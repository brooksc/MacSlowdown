---
id: TASK-107
title: Pull Claude Design's revised canvas and implement it in the app
status: To Do
assignee: []
created_date: '2026-08-31 22:10'
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
- [ ] #1 The remote canvas is fetched and becomes the repo's reference copy, with screens/*.png regenerated from it
- [ ] #2 No local canvas is ever pushed over the remote
- [ ] #3 The stashed local edits are reviewed for anything worth raising, then dropped
- [ ] #4 Claude Design's revisions are reported against the built app before any code changes
- [ ] #5 The design is implemented in the app, or each deviation is recorded with its reason per FR-060
<!-- AC:END -->
