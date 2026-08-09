---
id: TASK-65.8
title: >-
  Screen 1h — The unattributable incident, told honestly (~40% of real
  slowdowns)
status: In Progress
assignee: []
created_date: '2026-08-09 02:23'
updated_date: '2026-08-09 07:07'
labels:
  - ui
  - core
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1h.png`. No implementation exists. This is the single most important screen in the set for this product's credibility, because CLAUDE.md measured that ~40 percentage points of busy CPU is unattributable in the MAS build.

**What the design specifies**

Headline: "Something outside your apps used the CPU for 8 minutes". The opening paragraph states the limit without apology: "None of your open apps accounts for it — 79% of the load came from system processes that macOS doesn't let us look inside. We can tell you what happened, and which system processes were running at the time — but not how much CPU any of them used."

- **Where the CPU went** — contributor bars totalling 100%, unattributed at 79% as the largest bar.
- **Total CPU** chart with started/recovered markers.
- **What we found** — Measured / Calculated / "Likely, moderate confidence" / Ruled out. The Likely paragraph is a model of inference discipline: `backupd` started two minutes before the rise and ran the whole window, *and* the shape of the load (sharp start, flat plateau, clean stop, no memory or storage change) matches a backup — "We can see that it was running; we can't measure how much CPU it used, so this is an inference from timing, not an attribution."
- **What was running** — "Measured — names and timing only, never their CPU". Lists Time Machine (`backupd`, started 11:02, exited 11:13), Spotlight system indexer (`mds_stores`, running throughout), Software update (`softwareupdated` — **not running**). Listing what was *absent* is evidence too.
- **Why we can't name it** — a plain explanation of the sandbox limit, ending "The 79% above is a real measurement of what's left over, not a rounding error" and pointing out that Activity Monitor is unsandboxed and can see inside.
- **What you can do** — Open Activity Monitor, Check Time Machine, Check for a software update; plus "I know what this was…" letting the user label it so the pattern is recognised next time, stored locally.
- **Has this happened before?** — "Three unattributed CPU incidents in the last 14 days, all between 11:00 and 11:30 on a weekday. A regular time of day is a strong hint that it's scheduled work rather than something you did."

**What this requires that we have**

Process lifecycle and start/stop times for unmeasurable processes are readable — CLAUDE.md confirms name, PID, parent and start time are available for all 234, only CPU and memory are denied. So the timing evidence this screen is built on is obtainable. The recurrence analysis needs incident history with time-of-day clustering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An incident whose load is mostly unattributable produces this presentation rather than a contributor list that silently fails to sum (FR-013, FR-038)
- [x] #2 The unattributed share is presented as a measured remainder, with the reason it cannot be broken down stated in plain language
- [x] #3 System processes running during the window are listed by name and timing only, with an explicit statement that their CPU is not measurable, including processes that were notably absent
- [x] #4 Any suggested cause is labelled as an inference from timing rather than an attribution, with its supporting evidence shown
- [x] #5 The user can label an unattributed incident so the pattern is recognised later, stored only on this Mac (FR-039)
- [x] #6 Recurrence across incidents is surfaced where a time-of-day or day-of-week pattern exists
- [ ] #7 Verified on screen against design/screens/1h.png
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built

`MacSlowdown/Sources/UnattributedIncident.swift` (new) — the presentation model,
pure functions over their inputs:

- **`CPUSplit`** — the "Where the CPU went" bars, with `accountsForTotal` as the
  property the section exists to hold. Two builders, and the difference between
  them is the finding below.
- **`SystemProcessWitness` / `SystemProcessRoster`** — names and timing for the
  processes we cannot measure, plus the ones notably absent.
- **`LoadShape`** — the shape of the retained CPU series, as arithmetic.
- **`TimingInference` / `TimingInferenceBuilder`** — candidate causes from timing.
- **`UnattributedExplanation`** — the "why we can't name it" copy.
- **`UnattributedRecurrence` / `UnattributedRecurrenceFinder`** — time-of-day
  clustering across incidents.
- **`UnattributedIncidentReport`** — the assembly, returning `nil` when this is
  not that kind of incident.

`MacSlowdown/Sources/IncidentLabels.swift` (new) — FR-039. `UserDefaults`-backed,
bounded to 100, reversible, and structurally incapable of touching an `Incident`,
`MetricsHistory` or a recorded attribution: it holds strings keyed by incident id
and nothing else. Deliberately **not** added to the export document.

`MacSlowdown/Sources/SystemToolLinks.swift` (new) — hand-offs. Every entry opens
something and does nothing else, so FR-037 stays true by inspection.

`MacSlowdown/Sources/IncidentDetailView.swift` — the 1h sections in the design's
order, wired from `store.attribution?.protectedProcesses`, `store.lifecycleEvents`,
`store.monitoringStartedAt`, `store.enumeration` and `store.recentIncidents`. No
change was needed to `IncidentsView`, which already passes the store.

## Two corrections to the design, both from our own measurements

**1. The limit is uid, not the sandbox.** The design's copy reads "App Store apps
run in a sandbox that reports total system CPU but not per-process CPU for
protected system processes". Our Tier 0 probe measured the opposite: other-uid
processes are denied *identically* sandboxed and unsandboxed, and only a
privileged process sees them. The shipped copy says macOS reports per-process CPU
only for processes you own, that system work runs under root or service accounts,
and that this holds "sandboxed or not". Blaming the sandbox would have been the
tidier sentence, and it would also have implied that a non-MAS build of this app
could do better, which it could not.

**2. Recorded per-application figures are separate maxima and cannot be stacked.**
`IncidentAttribution` keeps two different aggregations on purpose: the three
totals come from the single busiest sample and therefore sum, while each
application's figure is its own maximum across the incident. The design stacks
apps and the remainder in one 100% bar. Doing that from a recorded attribution
would produce a chart whose parts can exceed its whole. `CPUSplit.Coherence`
carries the distinction: a live single-interval reading stacks contributors
(`.singleInterval`); a recorded one shows measured-vs-unattributed as two bars
that provably sum, with the applications listed underneath and a sentence saying
they are separate maxima (`.peaksAcrossIncident`). Tested both ways.

## How every inference is labelled

- The remainder — `.calculated`. Never `.measured` (we did not read it directly)
  and never a hypothesis (that would suggest it might not be there).
- Names, start times, presence and absence — `.measured`.
- "Ran the whole window" for a closed incident — stated as a **deduction from two
  measured times** (start time precedes the window, process still present), with
  that reasoning printed on screen rather than assumed.
- The shape of the load — `.calculated`, and its text ends "The shape of a load
  does not identify what produced it". A test asserts the shape text never
  contains "backup", "Time Machine" or "index".
- A candidate cause — `.heuristic`, capped at `.moderate` and dropping to `.low`
  the moment more than one process fits, with `TimingInference.disclaimer` inside
  the conclusion string so layout cannot separate the caveat from the claim.
- Recurrence — count `.measured`, clustering `.calculated`, the "scheduled work"
  reading `.heuristic` at moderate, earlier labels `.userProvided`.

## What the data supports, and what it does not

**Supported.** Every process is nameable: command, uid, ppid and start time come
from `sysctl KERN_PROC_ALL` for all of them, and `ProtectedProcess.startedAt`
already exposed the start time as a `Date`. `SystemProcessDescriptors` already
turns `backupd` into "Time Machine" and `softwareupdated` into "Software Update",
so the roster reads as answers rather than as a directory.

**Not supported, and handled as absences:**

1. **The roster is read now, not recorded with the incident.** Nothing retains
   which system processes were running during a closed incident. What makes the
   section honest anyway is the deduction above — and it has a real limit: a
   system process that ran only during the window and has since stopped appears
   only if we saw it go.
2. **Absence is claimable only where we were watching.** Gated on
   `monitoringStartedAt <= window.start` *and* a successful enumeration. Outside
   that, nothing is listed as absent and the reason is printed. Three tests.
3. **Exit times are one sampling interval wide.** `LifecycleTracker` stamps events
   with the sweep's clock, not the kernel's. Launches use the kernel's start time
   and are exact; exits say so.
4. **Inclusion is editorial and says so.** A daemon up for eleven days is not
   evidence about eight minutes, so off-watchlist processes are included only when
   they started within 15 minutes of the window. The watchlist is 14 entries of
   scheduled or periodic work a user can go and check on elsewhere.

## Tests

`MacSlowdown/Tests/UnattributedIncidentTests.swift` — 35 tests. The ones that
carry weight: the split always accounts for the total; recorded application peaks
are never stacked into it; a closed incident never borrows live attribution to
fill a gap; an incident our own apps explain does **not** get this presentation;
absence is refused when monitoring began late or enumeration failed; confidence
falls to low with two candidates and the text says it cannot single one out; no
candidate produces a refusal rather than a guess; a label is reversible, bounded
and readable back through a second instance.

Full suite **822 passing, 2 failing**. Both failures are the load-synthesising
pair CLAUDE.md names — `CPUWorkloadTests."A real workload raises the attributed
share"` and `EndToEndIncidentTests."A real slowdown produces one incident"`
(failing at its own baseline-too-busy guard, line 72). Both **pass in isolation**;
re-run confirmed. The machine was running two dozen concurrent agents.

## Criteria

- #1–#6 checked, each covered by tests.
- **#7 unchecked.** Nothing has been seen. This agent was forbidden the screen,
  and the presentation only appears for an incident whose recorded attribution has
  an unattributed share ≥ 50%.

## What staging this screen would take

The presentation is keyed on `incident.attribution.unattributedShare >= 0.5`, so
it needs a real incident dominated by system work. The reliable way to produce one
is to start a Time Machine backup to a local disk (or trigger a full Spotlight
reindex with `mdutil -E /`) and leave the app running for more than the sustained
CPU duration — 3 minutes at default thresholds, or set Alerts to Sensitive for 60
seconds. Watch that the roster names Time Machine and lists Software Update as
absent, then check the four things that cannot be judged from a test: whether the
bars survive the inspector's ~380 pt width; whether "Why we can't name it" reads
as an honest limit rather than as an apology or a bug; whether the label field and
its suggestion chips fit that column; and whether the whole thing holds up at
increased contrast and reduced transparency.

## Needs a human

- The recurrence section needs three unattributed incidents in 14 days to appear
  at all, and incidents do not persist across restarts (still undecided in
  CLAUDE.md). Until that is settled, recurrence will only ever fire within one long
  run of the app.
- `SystemTool.settings(url:)` opens System Settings panes by URL scheme. Whether
  the sandbox permits `x-apple.systempreferences:` was **not** verified — the
  result of `NSWorkspace.open` is reported to the user either way, so a refusal
  degrades honestly, but somebody should look.
- The watchlist is a judgement call about which system processes are worth naming
  when absent. Worth a second opinion.
<!-- SECTION:NOTES:END -->
