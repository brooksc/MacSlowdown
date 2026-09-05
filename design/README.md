# Design reference

The UI design produced in Claude Design, imported for reference. **This is a design
input, not a specification of behaviour** — `requirements.md` still governs (see its
§11 and the Authority section of `CLAUDE.md`).

The mocks are **directional**. The placeholder machine (a MacBook Pro M4 Pro with 10
cores and 36 GB, or a MacBook Air M4 with 8) and every figure on the screens are
invented. The structure, the information hierarchy and the copy intent are the
requirement; the numbers are not.

## The cloud project — where the design actually lives

| | |
|---|---|
| Project name | *Mac tray app design screens* |
| Project UUID | `f2b8c5b9-f801-4287-bea3-d8cdda998adb` |
| URL | <https://claude.ai/design/p/f2b8c5b9-f801-4287-bea3-d8cdda998adb?file=MacSlowdown+Screens.dc.html> |
| Type | `PROJECT_TYPE_PROJECT` (**not** a design system) |
| Reached by | the `DesignSync` MCP, after `/design-login` |

**The remote is authoritative. This directory is a reference import.** Never push a
local canvas over the remote — a session once came within one approval of destroying
Claude Design's revisions that way (TASK-107). If the local copy and the remote
disagree, the remote is right and the local copy is stale.

Files in the project: `MacSlowdown Screens.dc.html`, `support.js`, and
`uploads/{CLAUDE.md, live-surfaces.md, requirements.md}` — the three documents
uploaded as context so the design is produced against the spec rather than against a
brief. When any of those three changes materially, re-upload it before asking for
design work.

### Fetching it — the MCP cannot do this on its own

`DesignSync get_file` **caps at 256 KiB and the canvas is 298,585 bytes**, so a fetch
returns a file truncated mid-attribute with no error. Verified 2026-08-31: the
truncated fetch was a clean byte-prefix of the real document, and the missing tail was
four artboards.

**Ask the product owner to export the project instead** (it arrives as
`~/Downloads/MacSlowdown.zip`). If you do fetch through the MCP, check the byte count
against 262,144 before trusting it.

## Contents

- `MacSlowdown Screens.dc.html` — the design document, whole, from the export.
- `support.js` — the Claude Design runtime the document loads. Not needed to render
  these screens: the document is static HTML with inline styles and carries no
  `data-dc-script`, so a browser renders it without the runtime.
- `screens/*.png` — one render per artboard, autocropped, 2x.
- `icons/` — app-icon renders and their notes.
- `live-surfaces.md` — the document proposing FR-057 to FR-062, now folded into the
  spec. Kept because it carries the argument, which the requirements table does not.

## The screens

Turns are newest first in the document. Turn 4 is the current word wherever it
contradicts an earlier turn.

### Turn 4 — revision after two weeks of real use (2026-08-31)

The turn that followed running the built product on a real machine. Notable for
retracting three of its own earlier claims.

| | | Status |
|---|---|---|
| 4a | Now, revised — four columns, no profiles, windowed sort key, run-queue condition present | Table and state tiles **built**; run-queue tile blocked on TASK-103 |
| 4b | Run-queue pressure — the unit, the graphic, the popover, the spoken label | **Not built.** Vocabulary is right; its numbers are refuted, see below |
| 4c | Lifecycle record in the process inspector — replaces the repeated-quit incident | Demotion **built** (TASK-102); the richer inspector treatment is not |
| 4d | Menu bar icon reconciled — the build is right, 2d was wrong | **Built**, including the severe filled badge |
| 4e | Corrections to shipped screens — three things it drew that measurement forbids | Already true in the app; verified rather than assumed |

**4b's numbers are refuted and 4b's copy has a defect.** `probe/FINDINGS.md`
(TASK-103) measures an ordinary build at a median of 2.87 runnable threads per core,
which breaches 4b's threshold through most of every compile. Separately, its legend
says "Waiting for a turn — 88" while two allowed phrasings say "12 threads per core
*waiting*" — 96÷8 = 12 includes the running thread, so the word "waiting" is wrong on
those two lines. **Do not implement 4b's figures.** Its never-list, lane graphic and
spoken label are sound and survive.

### Turn 3 — app icon, six directions

| | |
|---|---|
| 3a | Level meter — the menu bar glyph, promoted |
| 3b | Trace with an incident band |
| 3c | Dial at redline |
| 3d | Lens over the trace — diagnosis, not measurement |
| 3e | Attribution split — the honest one |
| 3f | Stopwatch — the felt experience |

`TASK-65.18` chooses a direction and ships a real asset; `TASK-65.19` refines 3b at
large sizes. There is still no app icon in the build.

### Turn 2 — menu bar icon explorations

**2d was the recommended spec and is now superseded by 4d**, which endorses the built
app over it: template in every state but severe, because colour should be an event
rather than a status. 2a (gauge ring), 2b (stacked bars) and 2c (silhouette swap) are
alternatives that were not taken and carry no backlog item.

### Turn 1 — application screens, first pass

| | |
|---|---|
| 1a | Menu bar popover — nothing wrong |
| 1b | Menu bar popover — live incident (the triage moment) |
| 1c | Main window — Now (triage first, numbers underneath) |
| 1d | Apps & processes — family grouping expanded, with an inspector |
| 1e | Incident detail — the evidence room |
| 1f | Incidents — history and patterns |
| 1g | Notification, mute sheet, and first run |
| 1h | Incident we can't attribute — the honest hard case |
| 1i | Settings — Alerts |
| 1j | Settings — per-app rules, and Privacy |
| 1k | Export a report — redaction preview |
| 1l | Storage — capacity, trend, and what can't be read |
| 1m | All processes — the peer view |
| 1n | Now, when our own sampling falls behind |
| ~~1o~~ | **Deleted 2026-08-31.** Was the repeated-quit incident screen. FR-046 amendment 5 makes it unreachable; 4c replaces it |
| 1p | Empty search in Apps |

Four of these were **edited** in the 2026-08-31 revision, each a correction toward
something already settled in this repo:

- **1j** said "Stored encrypted in the app's own container" — a claim CLAUDE.md
  explicitly forbids. Now "In MacSlowdown's own container, which no other app can
  read." The app never carried the wrong wording; the design did.
- **1f** drops the repeated-quit row and "quit unexpectedly"; the week's count falls
  from 9 incidents to 8.
- **1n** and **2d** drop the claim that the icon updates on a higher-priority path.
  It does not — both read the same store on the same actor, and the icon's rate
  limiter puts it up to 2 s further behind.

## Regenerating the renders

```sh
# Extract the document's <style> block plus one .dv-opt block into a temp file,
# take max(width:NNNpx) in that block as the artboard width, then:
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --hide-scrollbars --force-device-scale-factor=2 --window-size=$((W+80)),3200 \
  --default-background-color=dcd9d2 --screenshot=screens/4a.png "file://…/4a.html"
# then autocrop against #dcd9d2 with PIL, and warn if the content bbox reaches the
# bottom edge — that means a fixed-height artboard clipped the content.
```

Two traps, both of which have cost a session: Chrome intermittently drops one
screenshot per batch, so check each file exists and retry the misses; and a render
that looks fine can be silently clipped, which is why the autocrop step doubles as the
clipping check.

## Backlog

`TASK-65` is the conformance umbrella with one subtask per screen. `TASK-107` records
the import of the 2026-08-31 revision and what was built from it.

**Reading a render is not verifying a screen.** Rendering turn 4 caught three defects
that reading its HTML had not. Looking at the *app* is a further step again, and
`CLAUDE.md` is explicit that a UI criterion is never met by a passing unit test.
