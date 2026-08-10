---
id: TASK-84
title: >-
  The repeated-quit condition fires on ordinary process churn — 28 subjects
  qualify in one 15-minute window
status: In Progress
assignee: []
created_date: '2026-08-09 23:56'
updated_date: '2026-08-10 02:00'
labels:
  - core
  - decision
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured while re-examining the threshold for TASK-82 criterion #5. **This is not a threshold that is slightly too eager. The predicate is wrong, and no value of the count fixes it.**

## What was measured

An approximation of `LifecycleTracker` at a 2 s cadence over one **901 s** window (the tracker's own 900 s window), on the same developer Mac where both real false positives were seen on 2026-08-09. Snapshots of the full process table, disappearances grouped by basename truncated to 16 bytes, exactly as `p_comm` is.

**28 commands reached `minimumExits = 3`** in that single window (26 of them own-uid). Discounting `ps`, which was the sampler itself, 27.

| command | exits | exits with a later relaunch | median session life |
|---|---|---|---|
| swift-frontend | 112 | 110 | 2 s |
| swift-plugin-ser | 63 | 62 | 2 s |
| mdworker_shared | 61 | 61 | 51 s |
| yes | 60 | 52 | 3 s |
| zsh | 42 | 39 | 13 s |
| xcodebuild | 19 | 18 | 9 s |
| ugrep, SWBBuildService, head | 16-17 | 15-16 | 9-11 s |
| … 19 more at 3-12 exits | | | |

## What this means for the three dials

1. **Raising `minimumExits` does not work.** `yes` reached 60 exits and `swift-frontend` 112. A threshold high enough to exclude them excludes every genuine case FR-046 exists for — a user relaunching a failing app three or four times before giving up.
2. **Requiring a matched relaunch barely helps: 23 of 28 survive.** A build spawns the same compiler over and over, so an exit is almost always followed by another launch of the same command. This was the obvious fix and the measurement kills it.
3. **Requiring a median session lifetime ≥ 60 s leaves 3 of 28** — `caffeinate`, `ibtoold`, `sleep`. Still false positives, but a 90% reduction.
4. **Applying FR-046's own noun leaves 0.** Exactly one of the 28 lives in a `.app` bundle: MacSlowdown itself, being rebuilt. Every other subject is a compiler, a CLI tool, a daemon or a helper.

## Why this is severe, not cosmetic

`SystemObservation.breaches(.repeatedApplicationQuits)` is true if *any* finding is inside the quiet period, and the quiet period is refreshed by the next piece of churn. On a Mac that is building, the condition therefore **breaches continuously** — one incident that opens within a minute and never closes, whose subject is whichever compiler happens to have the highest exit count. That is exactly the two episodes observed on 2026-08-09.

## The FR-006 argument

TASK-71 argued that `minimumExits = 3` is FR-006's sustained-not-transient guard, and that a second clock would count the same evidence twice. The second half of that is right. The first half defends against the wrong transient. FR-006's acceptance criterion is "no alert for a single transient spike **shorter than the configured duration**" — one event that did not last. The observed false positives are not one event that was too short; they are **many events that were each entirely normal**. Multiplicity is not duration, and three normal exits do not compose into one abnormal episode.

## What FR-046 actually asks for

The statement is "repeated **application** failure". The objective is "explain **application** failures that occur without aggregate resource saturation". The outcome is "distinguish a repeatedly failing **application** from a system-wide CPU or memory incident". The detector does not implement that noun; it implements "three processes sharing a 16-byte `p_comm` disappeared inside 15 minutes".

## The decision to make

Restrict the condition's subject to a process that resolves to an outermost `.app`. On the measured window that produces **zero** findings and loses nothing real.

It is a product decision because it has a genuine recall cost — a daemon or a CLI tool that really is failing repeatedly would no longer open an incident — and because it is not free to build: `LifecycleTracker` works from `ProcessSnapshot.records`, which carry no executable path. Identity resolution is cached separately by `(pid, start time)` and would have to be handed in, which is wiring in `MonitorStore`.

## Separately: "unexpected" is a claim we cannot support

`LifecycleEvent.exited` is derived from a process vanishing between two snapshots. There is no exit status, no signal, and crash reports are unreadable under the sandbox (FR-046's own notes). A clean exit and a crash are identical to us. `IncidentCondition.repeatedApplicationQuits.label` says "Repeated unexpected quits" and the report copy says "quit unexpectedly". FR-046 forbids claiming an application was unresponsive on exactly this reasoning, and FR-002 forbids stating what was not measured. Design 1o's copy is the product owner's, so this is raised rather than changed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A decision is recorded on whether the repeated-quit subject is restricted to processes resolving to an application bundle, with the recall cost stated
- [ ] #2 If restricted, the measurement is repeated on a building developer Mac and the qualifying-subject count is recorded
- [x] #3 A decision is recorded on the words "unexpected" and "quit unexpectedly", which assert an exit status we cannot read (FR-002, FR-046)
- [x] #4 Whatever is decided, the predicate and its evidence are stated in LifecycleTracker's own documentation rather than in a task note
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Implemented on branch `worktree-agent-a4fb2da76881b13b3` (commit 9b9683e)

Both product-owner decisions applied. Criteria #1, #3, #4 met; **#2 is not met**.

### #1 The subject is restricted to an application, and the recall cost is stated

`LifecycleTracker.relaunchPatterns` now considers only exits of processes that ran
from inside a `.app`. The filter is at *pattern derivation*, not at event recording,
deliberately: FR-045 wants every launch and exit recorded, and the family inspector,
`relaunchCount(forCommands:)` and the store's event log all still see the full set.
Only the **incident** is withheld.

The recall cost is written into `relaunchPatterns`' own documentation, not a task
note: a daemon, launch agent or CLI tool that really is crash-looping — `sshd`, a
database server, a sync helper — no longer opens an incident. Where a user can still
see it: the exits remain `LifecycleEvent`s, remain counted, and remain listed per
family in the process inspector.

### The seam, and how per-sweep resolution was avoided

TASK-84's own note was right that `ProcessRecord` carries no path. Three constraints
made the obvious fix wrong: identity resolution costs ~760 ms per full sweep and may
never run on the sampling path; a process that has *just exited* has no path left to
read, and asking `proc_pidpath` about its pid may answer about whoever inherits the
number; and by the time a pattern is assembled — up to 15 minutes later — the
resolver's `(pid, start time)` entry has been pruned.

So the answer is **captured on the event** at the moment the event is derived:

- `LifecycleEvent.launched/.exited` gained `isApplication: Bool`.
- `LifecycleTracker.events(from:to:at:isApplication:)` takes a closure. **No default
  value** — a caller that silently omits it is the TASK-71 failure shape, so it is
  required and the compiler enforces the handover.
- `ProcessIdentityResolver.cachedIdentity(for:)` is new: a cache **read** that never
  resolves. Documented as such.
- `MonitorStore.isApplication(_:)` supplies it as `!resolved.isStandalone`.

Why that is a warm hit rather than work: `run()`'s existing order is
`regroup(from: snapshot)` → `recordLifecycle` → `resolver.prune`. Grouping already
asks `identity(for:)` about every process in the sweep, and pruning happens after,
so both the process that just launched and the one that just disappeared are in the
cache when the event is built. **A miss reads as `false`** — not known to be an
application — which withholds an incident rather than opening one on a guess.

`OverheadHarness` was given the same closure rather than a stub, per CLAUDE.md's rule
that the harness must exercise the path the app runs.

### #3 "Unexpected" is gone

Renamed at every surface, all composing from **one** new constant,
`RepeatedQuitWording` (`Metrics/Sources/LifecycleEvents.swift`):

| slot | before | after |
|---|---|---|
| `IncidentCondition.label` (and the summariser headline built from it) | Repeated unexpected quits | **Repeated quits** |
| incidents row title / VoiceOver | `<X>` quit unexpectedly, repeatedly | **`<X>` quit repeatedly** |
| `RepeatedQuitReport.headline` | `<X>` quit unexpectedly three times in 12 minutes | **`<X>` quit three times in 12 minutes** |
| `MenuBarPresentation.conditionWord` | quits | **quits** — text unchanged, now read from the constant so it cannot drift |

The row's accessibility label composes from the title, so VoiceOver follows without a
second string. Two tests hold the rule: one asserts none of the wording contains
`unexpected`/`crash`/`fail`/`hung`/`killed`/`terminated`, the other asserts
`IncidentCondition.repeatedApplicationQuits.label == RepeatedQuitWording.conditionLabel`
so a sixth surface writing its own copy fails rather than diverging (the TASK-82
failure mode).

**Left alone deliberately**, as pre-existing honest copy in a different grammatical
slot — condition *explanations* rather than the label:
`IncidentEvidence.plainDescription` ("An application quit and started again,
repeatedly") and `PopoverPresentation` ("An application has been quitting and
reopening"). Neither claims an exit status. `SystemToolLinks`' Console entry ("macOS
writes a report when an application quits unexpectedly") is a true statement about
what macOS does, not about what we measured, and was out of scope.

**This wording may change again.** A comment on `RepeatedQuitWording` points at the
open `kqueue`/`EVFILT_PROC`/`NOTE_EXITSTATUS` spike: if a crash can be distinguished
from a normal exit sandboxed, "crashed" becomes sayable for the exits that were
crashes, and the threshold argument reopens too — a *crash* loop is a much stronger
signal and would not need the application restriction to be safe.

### #4 The predicate and its evidence live in the code

`LifecycleTracker.relaunchPatterns` carries the 28-command measurement, the
multiplicity-is-not-duration FR-006 argument, and the recall cost. `minimumExits`
keeps the "no value of the count fixes it" evidence and now points at the filter that
does work.

### #2 NOT MET — the measurement was not repeated

Re-running the 901 s sampling probe on a building Mac was not done: `probe/Sources/`
is owned by another agent this session and the machine was shared. What exists
instead is the *synthetic* form of the same case, as tests: `swift-frontend` × 112,
`yes` × 60, `zsh` × 42, `xcodebuild` × 19 produce **zero** patterns
(`RelaunchPatternTests.commandChurnIsNotAPattern`), and at the store level 19 exits of
a non-application are recorded, counted, and open nothing through the real detector
(`LifecycleWiringTests.commandChurnOpensNothing`). That is not a fresh measurement on
a real build, so #2 stays unchecked.

### Not verified on screen

Nothing was put on screen — the machine was in use. The precise check: with a build
running, drive a `.app` through three exit/relaunch cycles
(`for i in 1 2 3; do open -a TextEdit; sleep 8; osascript -e 'quit app "TextEdit"'; sleep 8; done`)
and confirm (a) an incident opens for TextEdit; (b) the Now banner, the incidents row
and the inspector all read "quit" with no "unexpectedly" anywhere; (c) the menu bar's
VoiceOver label reads "…, high, quits, N minutes"; and (d) with the build running and
*no* app cycled, **no incident opens at all** — that last one is the regression this
task is about and the only one that proves the fix in the running product.

### Spec

No `requirements.md` edit was made (out of bounds for this branch). FR-046 wording
that the restriction arguably implies is proposed in the agent's report, unapplied.

### Tests

1063 passing, 1 failing: `EndToEndIncidentTests.realSlowdownProducesOneIncident`, at
its own "baseline CPU is N% of this Mac" guard (`EndToEndIncidentTests.swift:72`) —
the documented busy-machine case; several agents were building concurrently.
<!-- SECTION:NOTES:END -->
