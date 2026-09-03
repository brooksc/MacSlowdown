---
id: TASK-65.15
title: 'Screen 1o — Repeated-quit incident: evidence is lifecycle events, not curves'
status: Out of Scope
assignee: []
created_date: '2026-08-09 02:25'
updated_date: '2026-09-03 18:36'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1o.png`. Existing implementation: `LifecycleTracker` and relaunch-pattern detection exist (TASK-48); there is no incident presentation for them.

**What the design specifies**

Headline: "Final Cut Pro quit unexpectedly three times in 12 minutes". Opening: "Each time it reopened by itself within about a minute. Nothing was wrong with CPU, memory or storage while this happened — so this looks like the app failing, not your Mac running out of anything."

- **What we saw** — "Measured — launches, exits and PID changes". A session bar chart rather than a metric curve, showing sessions that ended and the one still open, with quit markers at 2:07, 2:12, 2:16 and a legend distinguishing "Session that ended", "Session still open", "Exit without a quit request".
- An event list with the PID evidence spelled out: "2:07 Exited · PID 2841 disappeared · relaunched 41 s later as PID 2896" and so on, ending "2:19 Running normally since — 4 days without another quit".
- **What we found** — Measured (three exits, each followed by a relaunch under a new PID, none following a quit request from the user or from us). Calculated (session lengths 4, 5 and 3 minutes; memory reached 6.8 GB before the first exit but only 2.1 GB before the third, "so it wasn't growing towards a limit" — evidence used to *rule out* a hypothesis). "Likely, **low** confidence" (repeated quits usually mean the app hit the same problem each time — "We have no way to see why it exited, only that it did"). Ruled out (not a resource problem).
- **What we can and can't say** — the explicit statement that we can see an app quit and return because process lifecycle is visible, but "We can't tell you an app froze or beachballed — macOS reports a hung app exactly the same way it reports a healthy one, so we'd rather say nothing than guess."
- **What you can do** — Open Console ("macOS writes a crash report each time. We can't read them; Console can."), Check for an app update, Copy diagnostics, "Tell me if it happens again".

**Direct match to a proven constraint**

CLAUDE.md is unambiguous that application hangs are undetectable and that FR-046 is deliverable only as repeated-relaunch detection. This screen is exactly that delivery, and it says so to the user in as many words. It is the model for how a ruled-out capability should appear in the product rather than being quietly absent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A repeated-quit incident renders as lifecycle evidence -- sessions, exits and PID changes -- rather than as resource curves
- [x] #2 Each exit is evidenced by the PID that disappeared and the PID it relaunched as, with the interval between them
- [x] #3 The incident states that resource conditions were normal, using that to rule out a resource cause rather than leaving it unsaid
- [x] #4 Confidence is labelled low where the cause cannot be seen, and the screen states plainly that we cannot see why an app exited (FR-013)
- [x] #5 The screen states that hangs and beachballs are not detectable and does not imply otherwise (FR-046)
- [x] #6 Suggested actions point to tools that can see what we cannot, without claiming we read crash reports
- [ ] #7 Verified on screen against design/screens/1o.png with a real repeated-relaunch sequence
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built

`MacSlowdown/Sources/RepeatedQuitIncident.swift` (new):

- **`AppSession`** — one run, launch to exit. `startedAt` comes from the kernel's
  start time for that PID and is exact; `endedAt` is when we first *noticed* the
  process gone and is one sampling interval wide. `startedAt` is optional because
  a process already running when we began watching has an end we saw and a
  beginning we did not, and inventing one would put a fabricated duration on
  screen.
- **`ExitEvidence`** — the PID pair. "Exited · PID 2841 disappeared · relaunched
  41 s later as PID 2896", with a distinct branch for an exit we never saw
  relaunch.
- **`ResourceVerdict`** — `.normal` / `.strained` / `.notObserved`, described below.
- **`MemoryBeforeExit` / `MemoryTrendBeforeExits`** — resident memory before each
  exit, drawn from `HistorySample.topContributors`.
- **`RepeatedQuitReport`** — the assembly, headline, opening, conclusions,
  ruled-out and the capability statement.

`MacSlowdown/Sources/SystemToolLinks.swift` (new, shared with TASK-65.8) —
`SystemTool.console` and `.appUpdates`. Every entry opens something and does
nothing else.

`MacSlowdown/Sources/IncidentDetailView.swift` — a `RepeatedQuitSection` per
relaunch pattern whose window overlaps the incident, built from
`store.relaunchPatterns` and `store.lifecycleEvents`, with a `SessionBar` drawing
sessions as bars and exits as marks. When there is no unattributable report, the
verdict headline and opening come from the quit report instead, because these are
answers to different questions and leading with "your Mac's processors were close
to fully busy" would point the reader at the wrong evidence.

## What the data supports

- **Sessions and PID pairs.** `LifecycleTracker` is keyed on `(pid, start time)`,
  so a recycled PID reads as one exit and one launch. Pairing each exit with the
  next session to start gives the replacement PID and the interval.
- **Session lengths**, exact at the start and one interval wide at the end.
- **Memory before each exit.** `HistorySample.topContributors` carries
  `residentBytes` per command, so where the app was among the leading contributors
  we can state what it held before each exit — and that refutes the first thing
  anyone assumes ("it grew until it ran out") rather than supporting a hypothesis.
  Labelled resident size, not the footprint Activity Monitor shows.

## What the data does not support, and how it reads

1. **"Resource conditions were normal" is claimed only from samples that exist.**
   `ResourceVerdict.notObserved` is the case that matters: without retained
   samples covering the window the text says "We cannot rule a resource cause in
   or out… we can say only that we did not observe a resource problem — not that
   there was none." Also refused when the logical core count is unknown, because a
   percentage of one core means nothing without it. The opening paragraph changes
   with the verdict rather than asserting calm regardless.
2. **Per-sample memory pressure is not retained** (established in TASK-65.5). The
   pressure half of the verdict comes from `incident.peakMemoryPressure`, so it is
   available only where an incident covers the window.
3. **Confidence is low and cannot rise.** The hypothesis text says so explicitly:
   "this cannot be narrowed further from here". A test drives it with a `.high`
   `RelaunchPattern` confidence and asserts the cause is still `.low` — those
   measure different things (name-matching vs. reason-for-exit) and the limiting
   one is not observable at all.
4. **Hangs.** `RepeatedQuitReport.hangLimitation` **is** `RelaunchPattern.limitation`,
   not a copy of it — asserted by a test, so the app and the framework cannot
   drift into saying different things about the same limit. Alongside it,
   `capability` states in the user's words that we can see a quit and a return
   because process lifecycle is visible, and cannot tell them an app froze or
   beachballed because macOS reports a stalled app exactly as it reports a healthy
   one. Given a section of its own, not a footnote.

## A correction to the design's copy

1o's Measured paragraph says none of the exits followed a quit request "from you
or from us". Half of that is provable and half is not. MacSlowdown has no process
control, so "not from us" is true by construction; whether the *user* quit the app
is not visible to us at all. The shipped sentence claims only our half and says
plainly that the other half is not something we can see. A test asserts both
clauses are present.

## Tests

`MacSlowdown/Tests/RepeatedQuitIncidentTests.swift` — 18 tests over a synthetic
2841 → 2896 → 3014 → 3120 sequence. The ones that carry weight: session lengths
come from kernel start times; an exit we never saw relaunch is not described as
having relaunched; no samples means the resource cause is *not* ruled out; a busy
machine reads as "not ruled out" rather than as the cause; a `.high` pattern
confidence still yields a `.low` cause; and a forbidden-phrase sweep over the
headline, the opening and every conclusion for "hung", "hang", "froze", "frozen",
"beachball", "unresponsive", "not responding".

Full suite **822 passing, 2 failing** — `CPUWorkloadTests."A real workload raises
the attributed share"` and `EndToEndIncidentTests."A real slowdown produces one
incident"` (its own baseline-too-busy guard, line 72). Both are the
load-synthesising pair CLAUDE.md names, both **pass in isolation**, re-run
confirmed. Two dozen agents were on the machine.

## Criteria

- #1–#6 checked, each covered by tests.
- **#7 unchecked.** Nothing seen; the screen was off limits for this agent, and it
  needs a real repeated-relaunch sequence.

## The structural gap: a repeated-quit episode is not an incident

`IncidentCondition` has no `repeatedQuits` case and `Incident.swift` was not mine
to edit, so this presentation appears **inside an incident's detail** when a
relaunch pattern overlaps the incident window. The design shows it as an incident
in its own right — "Incident · Repeated quits, Tuesday 2:07 PM" — and that is
correct: 1o's whole point is an application failing while the machine is fine,
which by definition opens no resource incident. **As shipped, a repeated-quit
episode with no concurrent resource incident is invisible**, because `IncidentsView`
lists incidents and nothing else. Closing that needs a new `IncidentCondition`
case plus detector and `MonitorStore` wiring, both owned elsewhere. Worth its own
task.

## What staging this screen would take

Three exits of the same command inside `LifecycleTracker`'s 15-minute window
(default `minimumExits: 3`), overlapping an open or recent incident. A scriptable
approximation: launch a small app, `kill` it, relaunch, three times over ten
minutes, while a CPU load keeps an incident open. Then check what tests cannot:
whether the `SessionBar` reads as sessions rather than as a chart of some
measured quantity at the inspector's ~380 pt width; whether the open session is
distinguishable from the ended ones without relying on colour; and whether "What
we can and can't say" lands as candour rather than as an excuse.

## Needs a human

- The missing incident type above — a product decision, not a code one.
- "Tell me if it happens again" from the design is **not implemented**: it needs
  `AlertSettings`, owned by TASK-69. The other three hand-offs are present.
- Whether opening `macappstore://showUpdatesPage` works under the sandbox was not
  verified. The result of asking is reported to the user either way (FR-017).

**Unreachable, and the screen no longer exists** (2026-09-03, TASK-102, FR-046 amendment 5).

The demotion means a repeated relaunch pattern opens no incident, so there is no incident for this screen to be the detail of. Nothing renders it and nothing can.

Claude Design reached the same conclusion independently and acted on it harder than expected: **1o is deleted from the canvas**, not annotated as superseded. The revised document runs 1a–1n, 1p. Its replacement is **4c**, a lifecycle *record* inside the process inspector — no severity chip, no notification behind it, no triage furniture, because a record has no severity. Claude Design's note on the demotion is worth keeping: "the finding was never wrong about what it saw, it was wrong that anyone needed telling."

What survives of this screen's intent is in the inspector already: `FamilyInspectorView` shows "Relaunches, by name" with `Evidence.heuristic`, the confidence, and the caveat that the count is matched by command across the whole process table. 4c asks for more than that — a per-generation timeline ("PID 2841 no longer present after 4 min · PID 2896 appeared 41 s later"), an explicit "what this does and doesn't say" panel, and a Copy lifecycle record action. **That is open design work and is not claimed here**; it belongs to a new subtask against 4c if it is wanted.

Copy discipline carried forward from 4c, which the app already honours: "no longer present", never "quit", "crashed", "failed" or "unexpectedly".
<!-- SECTION:NOTES:END -->
