# The running app, seen — 2026-09-16

Five screens of the **running** application, captured on macOS 26.6.2 (25G83) in a
`tart` VM, at 1400×940. Not previews: the real app, sampling the real machine,
with a real window server.

This is the first time most of these have been looked at. `CLAUDE.md` had carried
"the largest live risk is unverified UI" for weeks, on the grounds that looking
meant launching a menu bar app onto the owner's display while they were working.
The VM removes that constraint entirely.

| File | Screen | Design reference |
|---|---|---|
| `01-overview.png` | Overview, with a real coverage gap | `5c` |
| `02-now.png` | Now | `1c` (not exported), `4a` |
| `03-apps.png` | Apps & Processes | `1d`, superseded in part by `4a` |
| `04-incidents.png` | Incidents, empty state | `1f` |
| `05-storage.png` | Storage | `1l` |

## How they were taken

The app is `LSUIElement`, so launching it opens nothing, and SwiftUI's
accessibility tree is not walkable by System Events on macOS 26 — clicking the
sidebar from a script silently does nothing. Both are why this had never been
done. `UIVerificationLaunch` (Debug-only) takes `-ui-open main -ui-section <name>`
and makes it deterministic: relaunch per section, wait ~45 s so the sparklines and
the 60 s mean have something real in them, then capture.

Screenshots are taken through `osascript`, which already holds a screen-recording
grant in this VM. Capturing directly from the SSH session raises a consent dialog
that lands *in the frame* — which is what the first two attempts produced.

## What they showed

Three defects, all filed, none of which any test had caught:

- `TASK-118` — Now's "System processes" row crushes its subtitle and badge to about
  one character per line. Primary screen, and the TASK-75 failure mode returning.
- `TASK-119` — two CPU numbers side by side on Now, which the 2026-09-03 decision
  ruled out; the footer calls 1 s the "normal cadence" where FR-031 says 2–5 s; and
  "1 readings over 1 minute".
- `TASK-120` — design 5c's "Something happened then" button, which files a report
  against a coverage gap, is not built. The engine already supports it.

And several confirmations worth as much as the defects, because they were assumed
rather than known:

- The **coverage record matches 5c closely**, in places word for word — the
  headline pattern, the three-state legend, the hatched gap that does not heal.
- **Incidents renders its empty state** (`TASK-51.1`, previously blank).
- **Storage labels every figure** Measured / Calculated / Estimate, and says
  purgeable space "is an estimate, not space you have" (FR-038).
- The incident retention sentence uses the required phrasing exactly: "saved in
  MacSlowdown's own container, which no other app can read" — never "encrypted".
- The census sums honestly on every screen.

The macOS onboarding banner in the top right of each shot is the VM's, not ours.
