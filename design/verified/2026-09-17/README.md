# The running app and its sheets, seen — 2026-09-17

Two kinds of evidence, and the difference between them matters.

**`0*.png` are the running application**, captured on macOS 26.6.2 (25G83) in the
`tart` VM at 1400×940 by `probe/vm-capture.sh` — the real app, sampling the real
machine, with a real window server. The script is committed this time; the
2026-09-16 run was done by hand and nothing survived it but the pictures.

**`previews/*.png` are rendered `#Preview`s**, offscreen, through Xcode's
`RenderPreview`. They answer layout, truncation and copy at a stated width. They
answer nothing about the running application — presentation, focus, `LSUIElement`
behaviour, the real restored window frame — and none of them is offered as
evidence for those.

The division is not a preference. A VM capture cannot reach a sheet, because
reaching one means clicking, and SwiftUI's accessibility tree is not walkable by
System Events on macOS 26. So the window goes in front of a camera and the sheets
go through previews.

## The running app

| File | Screen | Design reference | Verdict |
|---|---|---|---|
| `01-overview.png` | Overview, with four real coverage gaps | `5c` | **Match**, and 5c's missing button is now built |
| `02-now.png` | Now | `1c` (not exported), `4a` | **Match** after today's fixes |
| `03-apps--processes.png` | Apps & Processes | `1d`, superseded in part by `4a` | Partial — see below |
| `04-incidents.png` | Incidents, empty state | `1f` | Match |
| `05-storage.png` | Storage | `1l` | Match |
| `06-first-run.png` | First run, opened by the launch seam | no artboard | Renders correctly |
| `07-first-run-cold.png` | First run, **cold launch, no arguments** | no artboard | See TASK-65.20 below |

## What they settle

**TASK-118 is fixed where it was found.** `02-now.png` shows "System processes ·
281 processes · Can't be broken down" on one line at ordinary row height. On
2026-09-16 the same row rendered its subtitle and badge at about one character
per line and stood several times an ordinary row's height.

**TASK-119's two CPU columns are one**, headed "CPU, 60 s mean" — the same
heading Apps & Processes carries, so the 2026-09-03 decision now holds on both
tables rather than one.

**TASK-120 is on screen.** `01-overview.png` shows **"Something happened then"**
beneath the coverage strip with design 5c's caption beside it, word for word:
"Files a report against the gap, so at least the time is recorded." That is the
task's fifth criterion, which no test could have supplied.

**TASK-65.20 is verified, with one residual that the capture is the only way to
see.** `07-first-run-cold.png` is a cold launch with **no launch arguments at
all** and `firstRun.completed` cleared — the shipping path, not the seam — and
the window is visible and frontmost over the Terminal without intervention. But
the menu bar still reads **Terminal**: the window comes to the front without the
application becoming active. So a first click on that window activates rather
than acts. Recorded rather than smoothed over; `06-first-run.png`, which *does*
go through `activate(ignoringOtherApps:)`, shows the same thing, so the
activation call is not doing what it appears to promise under `LSUIElement`.

## What is still divergent

**Apps & Processes against 1d.** The long tail is not aggregated: design 1d ends
the list with a single "Other applications · 16 apps, each below 12%" row and the
build lists every daemon individually. That is TASK-65.22 #4 and #5, and it is
**deliberately not built** — the reasoning is in that task, and it needs the
product owner, because every row it would fold away is a named, measured process
sitting directly beneath a "System processes" row that exists to mark activity we
genuinely cannot break down. Two rows that look alike and mean opposite things is
a worse defect than a long tail.

**No artboard exists** for first run, for the Settings tabs as built, or for the
mute and export sheets in their current form. Their previews are recorded here as
a baseline rather than compared against a reference.

## The sheets and screens, as previews

| File | What it settles |
|---|---|
| `previews/mute-sheet.png` | The footer sentence that stops "mute" reading as "stop watching" is legible — the reason this is a sheet and not an `NSMenu` |
| `previews/export-defaults.png` | Every figure labelled Measured or Calculated; the redaction visibly applied; "Nothing is uploaded" |
| `previews/export-redacted.png` | The preview pane changes when the controls do, so they are not decoration |
| `previews/incident-detail-820.png` | Every claim labelled Measured / Calculated / Likely, the unattributed remainder stated, "no action was recorded" |
| `previews/incident-detail-480.png` | The densest surface reflows at the window minimum |
| `previews/first-run.png` | The copy, independent of whether the window comes forward |
| `previews/menu-bar-popover.png` | The healthy state: "Taking the first reading…", Disk "Unavailable", no fabricated figure |
| `previews/settings-{general,alerts,rules,privacy}.png` | The four tabs, three of which had never been looked at |
| `previews/now-table-{900,480}.png` | TASK-118 at both ends |
| `previews/now-table-two-badges.png` | The worst name cell the product can produce |
| `previews/all-processes-{480,140}.png` | TASK-117 at the window minimum, and TASK-97 at the width the inspector leaves |

**The incident timeline's axis labels were found here, not in a test.**
"conditions cleared" and "closed" are a minute apart on a fourteen-minute axis
and overstruck into an unreadable smear, at exactly the point the screen was
saying when the machine recovered. Fixed, and now asserted at stated widths by
`TimelineLabelTests`.

**Settings › Privacy and Settings › Alerts each closed an open criterion.**
Privacy states both retention bounds — "kept for the period above or the 200 most
recent, whichever comes first" — so the count cap is not being explained as a
time window (TASK-79 #2), and it uses the required container phrasing exactly,
never "encrypted". Alerts quotes its own CPU threshold with the caveat that the
option moves the detection line and not merely the announcement rule (TASK-111
#4).

## One thing in the frames that is not ours

The macOS onboarding banner in the top right of every VM shot is the virtual
machine's, not the app's.
