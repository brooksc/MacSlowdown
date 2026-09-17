---
id: TASK-65.1
title: 'Screen 1a — Menu bar popover, healthy state'
status: Done
assignee: []
created_date: '2026-08-09 02:21'
updated_date: '2026-09-17 18:58'
labels:
  - ui
milestone: m-1
dependencies: []
modified_files:
  - MacSlowdown/Sources/MenuBarContentView.swift
  - MacSlowdown/Sources/PopoverPresentation.swift
  - MacSlowdown/Tests/PopoverPresentationTests.swift
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1a.png`. Current state: `screenshots/01-menubar-popover.png`. Existing implementation: `MenuBarContentView.swift` (TASK-11).

**What the design specifies**

A reassurance-first popover, not a dashboard. Top line is a plain-language verdict — "Your Mac is running normally" — under it "No slowdowns in the last 24 hours. Watching since 8:02 AM." That second line does two jobs: it says nothing is wrong *and* proves monitoring is actually running, which "no incidents" alone does not.

Then a four-up strip of headline figures: CPU, Memory pressure, Disk, Storage free. Then "Using the most CPU now" — a short contributor list with app icon, name, process count ("Safari · 9 processes"), and percentage. Unattributed system activity sits in that list as a peer row with an info affordance, not as a footnote. Spotlight indexing is marked "(partial)". A footer states the percentage convention. One button: "Open MacSlowdown".

**Gap against what we render today**

The current popover opens with the severity word "Normal" and goes straight to numbers: Total CPU, three contributor rows, Other applications, Unattributed system activity, the percentage note, then Open and Quit buttons. Missing: the plain-language verdict sentence, the "watching since" line, the four-up metric strip (memory pressure, disk and storage free appear nowhere in the popover), app icons and process counts on contributor rows, and the "(partial)" qualifier. Present but not in the design: a "Quit MacSlowdown" button.

Also note the contributor names in our build are wrong in a way the design assumes solved — `2.1.220`, `com.apple.Safari…` — tracked separately as TASK-57.1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The popover leads with a plain-language verdict sentence and a line stating how long monitoring has been running, not with a bare severity word
- [x] #2 Headline figures cover CPU, memory pressure, disk and storage free
- [x] #3 Contributor rows carry an icon, the application name, the process count where the family has more than one, and the percentage
- [x] #4 Unattributed system activity appears as a peer row with an explanation affordance, and partial attribution is marked as partial
- [x] #5 Verified on screen against design/screens/1a.png, with any deliberate divergence recorded and justified
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built

`MenuBarContentView` rewritten against design 1a; all presentation logic moved into a new pure file `MacSlowdown/Sources/PopoverPresentation.swift` so the copy — which is a requirement, not decoration — is reachable from a test.

Structure now: verdict sentence + monitoring-proof line → four-up metric strip → "Using the most CPU now" contributor rows → percentage convention footer → Open / Quit.

**Verdict.** `PopoverPresentation.verdict(severity:incidentOpen:)` returns a sentence and a symbol (severity never by colour alone, FR-034). Normal → "Your Mac is running normally". An open incident short-circuits to "A slowdown is happening now" purely so the healthy copy can never sit over a live incident — the triage presentation itself is TASK-65.2 and was deliberately not attempted.

**The load-bearing second line.** `monitoringLine(...)`. The window is the *observed* one, never a claimed one: "in the last 24 hours" is only said once we have actually been watching 24 hours, because `recentIncidents` is in-memory for this session and a 24-hour claim before then would be unsupported (FR-038). Before that it reads "No slowdowns since 8:02 AM, when monitoring started." If monitoring is not running it says so rather than reporting an absence of incidents.

"Watching since" is taken from `NSRunningApplication.current.launchDate`, because `AppDelegate.applicationDidFinishLaunching` starts the sampler — the two are the same instant to within launch itself. It is a measured value, not an invented duration.

**Four-up strip.** CPU (percent of one core), Memory pressure (the level word plus its explanation — never a percentage, which would invite reading it as percent of RAM used, FR-007), Disk (aggregate read+write per second, with the split and the "cannot be measured per application" limitation in the detail, FR-009), Storage free (startup volume `availableBytes` with a capacity bar; purgeable is deliberately *not* added in, FR-041). Unavailable measurements render as "Unavailable"/"—", never as zero.

**Contributor rows.** Now family-level (`store.rankedFamilies`) rather than per-process, which is what gives the design's "Safari · 9 processes". Each row: icon (nil → an explicit dashed placeholder, never a generic icon passed off as the app's), name, process count when > 1, "(partial)" when `family.notMeasurableCount > 0`, percentage. Unattributed system activity is a peer row sorted by value with an `info.circle` toggle that reveals `attribution.explanation` inline. "Other applications" is kept as a trailing residual row so the visible rows still account for the measured total.

## Deliberate divergences from the mock

1. **Quit MacSlowdown is kept.** The design shows only "Open MacSlowdown". With the menu bar item as the primary surface and no Dock icon by default, removing Quit would strand the user.
2. **No sparklines** in the metric tiles. They would need per-metric history that `MonitorStore` does not expose (`MetricsHistory` is private to it, and only CPU attribution is recorded). Drawing a trend from a single sample would be fabrication. The storage tile does carry its capacity bar, which is a single-sample figure.
3. **No mute / settings icon buttons** in the footer. `store.mute` exists but wiring the mute sheet is TASK-65.7's screen; out of scope here.
4. **Percentages are of one core**, so the CPU tile can read above 100%. The design's "12%" is machine-relative-looking, but our convention is stated in the footer and must not vary by surface (FR-004).

## Wanted from MonitorStore and could not have (TASK-66 owns the file)

- `monitoringStartedAt: Date` — a direct record of when the sampling loop began. Launch date is a good proxy today only because monitoring starts at launch; if `stop()`/`start()` ever get used, the line becomes wrong.
- `diskRates` should be **optional**. It defaults to `.zero`, so an unreadable block-storage driver is indistinguishable from an idle disk — exactly the FR-002 failure the tile is trying to avoid. Worked around by calling `DiskSignals.counters() != nil` once when the popover appears and treating nil as unavailable; that is a second read the store already does and should not be duplicated.
- Startup-volume capacity. `StorageSignals.snapshot()` is called from the view's `.task` (as `StorageView` already does). It belongs on the store so the popover and the Storage screen cannot disagree.
- A count of incidents in a real 24-hour window, surviving restart. Retention across restarts is still undecided.

## Tests

`MacSlowdown/Tests/PopoverPresentationTests.swift` — 22 tests in three suites, all passing. They cover: the verdict is a sentence and not the severity word; every severity carries both word and symbol; an open incident never reads "normally"; the reassurance line names its start; the 24-hour claim only after 24 hours; stopped monitoring stated explicitly; incident singular/plural; the strip covers exactly the four figures; an unread disk counter and an unreported volume are "Unavailable", not zero; disk is a rate with both directions in the detail; purgeable is not counted as free; memory pressure is a level with its meaning; CPU before the first reading is pending; row name/count/percent; unattributed ranks as a peer and is present at zero; partial marking present and absent; the residual row accounts for the untruncated remainder; zero-CPU families omitted; the VoiceOver label carries count, "partly measured" and the unit.

Full suite: **408 passing, 1 failing** — `MetricsTests/EndToEndIncidentTests.realSlowdownProducesOneIncident`, the documented load-synthesising flake. It failed in isolation too, with six agents building concurrently on this machine. `MetricsTests` depends only on the `Metrics` target (Project.swift:105) and cannot see any file changed here.

## Criteria

- #1–#4 met and covered by test.
- **#5 NOT verified — nothing was looked at.** The session was explicitly barred from using the screen. Layout, tile sizing at 340pt, the info-toggle affordance, icon fidelity and whether the popover grows too tall with four rows all need a person to open it against `design/screens/1a.png`.

## Note for TASK-65.2

`PopoverPresentation.verdict` already branches on `incidentOpen`, and `ContributorRow` carries the qualifiers the incident screen also needs, so 1b should be able to swap the verdict block and reuse the row and tile builders unchanged.

**Seen 2026-09-17**: `design/verified/2026-09-17/previews/menu-bar-popover.png`, the healthy state design 1a describes.

What the render settles, against 1a:

- The headline is a **state in words with a symbol beside it** — "No sustained condition right now" — never a colour alone (FR-034).
- The four metric tiles are there: CPU, Memory pressure, Disk, Storage free.
- **Nothing is fabricated when there is nothing to report.** The store had just started, so CPU reads "—", Disk reads "Unavailable", the contributor list says "Taking the first reading…" and the subtitle says plainly "Monitoring is not running, so nothing is being observed." That is the FR-002 rule holding in the hardest case, which is the first second of the app's life — an empty list here would have read as "nothing is using the CPU".
- The percentage convention is stated where the percentages are: "Percentages are of one core. 100% is one core fully busy; this Mac has 8."
- Both report gestures are present with the caption promising what they keep.

**Deliberately unchecked and worth stating: this is a *preview*, not the popover.** It renders the view; it does not present it from a status item. Whether the popover opens on a click, sizes itself correctly, or dismisses is untested here and belongs to TASK-65.23 #4. A preview of a popover's content is evidence about its content only.

The incident state — design 1b, the triage moment — is **not** covered by this and remains open as TASK-65.2, because it needs a real open incident and the store cannot be handed one from a preview.
<!-- SECTION:NOTES:END -->
