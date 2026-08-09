# Design reference

The UI design produced in Claude Design, imported for reference. **This is a design
input, not a specification of behaviour** — `requirements.md` still governs (see its
§11 and the Authority section of `CLAUDE.md`).

Source project: *Mac tray app design screens*
<https://claude.ai/design/p/f2b8c5b9-f801-4287-bea3-d8cdda998adb?file=MacSlowdown+Screens.dc.html>

## Contents

- `MacSlowdown Screens.dc.html` — the design document, as imported.
- `support.js` — the Claude Design runtime the document loads. Not needed to render
  these screens: the document is static HTML with inline styles and carries no
  `data-dc-script`, so a browser renders it without the runtime.
- `screens/*.png` — one render per screen, trimmed, 2x.

## Screens

Turn 1 — application screens:

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
| 1o | Repeated-crash incident — lifecycle events, not curves |
| 1p | Empty search in Apps |

Turn 2 — menu bar icon explorations. **2d is the recommended spec**; 2a (gauge ring),
2b (stacked bars) and 2c (silhouette swap) are superseded alternatives and carry no
backlog item.

## Regenerating the renders

```sh
# split the document into one page per screen, then:
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --hide-scrollbars --force-device-scale-factor=2 --window-size=1400,1600 \
  --screenshot=screens/1c.png "file://…/1c.html"
magick screens/1c.png -bordercolor '#dcd9d2' -border 20 -trim +repage \
  -bordercolor '#dcd9d2' -border 24 screens/1c.png
```

## Backlog

`TASK-65` is the conformance umbrella, with one subtask per screen (`TASK-65.1` …
`TASK-65.17`). Each names the reference render, the current-state screenshot in
`screenshots/` where one exists, and the task that delivered the current version.

The mocks are directional: the placeholder machine (MacBook Pro M4 Pro, 10 cores,
36 GB) and the invented figures are not requirements. The structure, the information
hierarchy and the copy intent are.
