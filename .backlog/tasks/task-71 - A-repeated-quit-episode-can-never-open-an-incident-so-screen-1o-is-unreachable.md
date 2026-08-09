---
id: TASK-71
title: >-
  A repeated-quit episode can never open an incident, so screen 1o is
  unreachable
status: In Progress
assignee: []
created_date: '2026-08-09 07:11'
updated_date: '2026-08-09 19:45'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-65.15 while building the repeated-quit incident screen (design 1o). The screen is built, tested and merged — and as shipped **nothing can ever show it**.

`IncidentCondition` has no case for repeated quits. Incidents are opened by resource conditions: CPU saturation, memory pressure, low storage and so on. But 1o's entire premise is **an application failing while the machine is fine** — "Nothing was wrong with CPU, memory or storage while this happened, so this looks like the app failing, not your Mac running out of anything."

So the exact episode the screen exists to explain opens no incident, and the section renders inside an incident's detail that will never occur for that reason. TASK-65.15 could not fix it because `Incident.swift` was owned by another session, and correctly built the presentation rather than silently widening the model.

What is already in place: `LifecycleTracker` is wired into `MonitorStore` (TASK-66), `relaunchPatterns` is exposed, `RelaunchPattern` exists and is tested, and `RepeatedQuitReport` renders sessions, exits, PID pairs and a resource verdict. The evidence is all there; only the trigger is missing.

What is needed: a lifecycle condition the detector can raise, plus the wiring in `MonitorStore`, so a relaunch pattern opens and closes an incident of its own.

Design constraints that must survive, all already honoured by the presentation:

- **Confidence is low and cannot rise.** We see that an app exited, never why. `RepeatedQuitReport` enforces this — a high pattern confidence still yields a low cause confidence.
- **`ResourceVerdict.notObserved` means the resource cause is not ruled out** — "we did not observe a problem, not that there was none". Do not let a new detector path convert that into an assertion of health.
- **Hangs remain undetectable.** `RelaunchPattern.limitation` is the single source for that copy and the view reuses it rather than copying it, so the app and framework cannot drift. FR-046 is deliverable only as repeated-relaunch detection and must never be presented as hang detection.
- An incident opened for this must not claim a quit request was absent on the user's side: we can only prove *we* did not request one, having no process control at all.

Note this interacts with FR-006's sustained-not-transient rule. A single unexpected quit is not an incident; the pattern threshold in `RelaunchPattern` is what makes it one, and the incident's duration is the span of the episode rather than a breach duration. Confirm the shape against FR-011, FR-045 and FR-046 before building.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A repeated-relaunch pattern opens an incident of its own, and closes when the pattern stops, without any resource condition being breached (FR-045, FR-046)
- [ ] #2 The incident appears in the incidents list alongside resource incidents, and opening it shows the repeated-quit evidence rather than an empty resource timeline
- [x] #3 A single unexpected quit does not open an incident; the threshold that makes a pattern is stated and tested (FR-006)
- [x] #4 Cause confidence remains low regardless of how strong the relaunch pattern is, and the interface never claims to know why an application exited
- [x] #5 The screen continues to state that hangs and beachballs are not detectable, from the single shared source rather than a copy (FR-046)
- [ ] #6 Verified on screen with a real repeated-relaunch sequence, or the on-screen criterion is left unchecked with what staging one would take
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built (TASK-71)

**The condition.** `IncidentCondition.repeatedApplicationQuits`, alongside a new
`IncidentCondition.isResourceCondition` so a screen can tell a lifecycle episode
from a resource one without enumerating cases. `SystemObservation` gained
`lifecycleFindings: [RelaunchPattern]`; `breaches(.repeatedApplicationQuits)` is
true while any finding's last exit is inside the new
`IncidentPolicy.repeatedQuitQuietPeriod` (default 300 s).

**Raised** in `IncidentDetector.observe` like any other condition, from
`MonitorStore.currentObservation(at:cpuBusyFraction:)` — a method extracted from
the sampling loop precisely because the seam is the thing that was broken: the
framework could do this and the app never handed it the data, and nothing failed
while that was true. `recordLifecycle` moved to *before* detection in the loop;
run at the end it would have delayed every lifecycle incident by one cadence.

**Closed** by the ordinary recovery hysteresis once the quiet period lapses, so an
episode ends ~6 minutes after the last exit we noticed rather than when the pattern
finally ages out of the tracker's 15-minute window.

## Threshold, and the FR-006 argument

The sustained duration for this condition is **zero**, deliberately.
`LifecycleTracker.minimumExits` (3, inside a 900 s window) already is the
sustained-not-transient guard: one unexpected quit never becomes a
`RelaunchPattern`, so the detector is never offered one and nothing can open. A
second clock on top would count the same evidence twice and delay a finding whose
evidence already spans minutes. Tested at 1, 2 and 3 exits, through the tracker and
through the detector.

The quiet period is not a trigger threshold — it decides when the episode is
**over**. Without it every episode would be recorded as a quarter of an hour long
regardless of how long the quitting actually went on.

## Dating

`SystemObservation.intrinsicBreachStart(for:policy:)` lets a condition supply its
own start where the evidence carries one. Only the lifecycle condition does; every
resource condition returns nil, because a threshold crossing is known only from
when we saw it cross. So the incident's `beganAt` is `pattern.firstAt` — the span
of the episode, not the age of a breach flag — and the start only ever moves
earlier, never forward.

## Confidence

`RelaunchPattern.causeConfidence` is the single source: `min(.low, confidence)`.
`confidence` is about the *association* (are these the same app, which better
evidence can genuinely improve); cause confidence is a different question with a
permanent answer, because the thing that would raise it — why a process ended — is
not observable at all. Capped rather than fixed so a weak association cannot come
out looking better than the pattern it rests on. `RepeatedQuitReport` now reads it
from there instead of recomputing `min(.low, …)` locally. Tested across all three
pattern confidences and at 40 exits.

Merging repeated sightings of one command takes the **weakest** confidence, the
earliest first exit, the latest last exit and the highest exit count — never an
average, and never a stronger claim than any single sighting supported.

`RelaunchPattern.limitation` remains the only home for the hang caveat; nothing was
copied. New copy for the condition (`IncidentEvidence.phrase`,
`PopoverPresentation.conditionPhrase`) states only what the process table showed,
and a test asserts the label contains none of crash/hang/hung/froze/frozen/
unresponsive/beachball.

## Persistence — schema **2**, deliberately

`Incident.lifecycleFindings: [RelaunchPattern]` (RelaunchPattern is now `Codable`)
carries the evidence on the incident, because lifecycle events are bounded by the
tracker's window and are not persisted — an incident reloaded tomorrow would
otherwise render as the empty resource timeline this task exists to prevent.

That field alone would have been additive. What forced the version step is the new
`IncidentCondition` case: the meaning of the existing `conditions` field changed, so
an *older* build reading a newer file would fail on the enum, call the whole file
`.malformed` and discard the user's entire history. At schema 2 it sees
`.futureSchema`, refuses, and leaves the file intact. Version-1 files still load —
there is a test that decodes a hand-built v1 payload with no `lifecycleFindings`
key and asserts `lastLoadFailure == nil`.

Round trip proved twice: through the encoder (`restored == original`, plus explicit
checks on findings, exits, pattern confidence and attribution confidence) and
through a real `IncidentHistoryStore` write and a fresh load from disk.

## The double-listing question — real, and solved in `IncidentHistory`

Yes: once a pattern opens an incident, the tracker still holds that pattern for 15
minutes, so the same episode would arrive from two directions and be listed twice —
and counted twice in "3 incidents in the last 7 days".

`IncidentHistory.entries` now drops a relaunch pattern that any incident's
`lifecycleFindings` already names. **The incident wins**: it is selectable, it opens
the detail with the evidence attached, and it survives a restart; the live pattern
is none of those. A pattern no incident covers still gets its own row, so nothing
observed disappears. Matched on **command, not times** — an episode's window grows
as it goes, so a time-equality test would stop matching the moment another exit
landed and the row would reappear beside its own incident. `IncidentsView.swift` was
not touched. `Entry.repeatedQuitsLabel` is now taken from the condition's label so
the two spellings cannot drift and the recurrence summary counts them as one thing.

## Also changed, and why

`IncidentDetailView` now (a) suppresses the unattributed-CPU narrative for an
incident with no resource condition — the share can read high simply because the
machine was idle, and leading with a CPU split for an episode where nothing was
breaching points the reader at evidence that does not exist; and (b) prefers the
incident's own recorded findings over the live tracker, for the same reason the
attribution does.

## Tests

`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests
-configuration Debug -destination 'platform=macOS' -derivedDataPath .build`

**906 passing** (main baseline 866). New: `Metrics/Tests/RepeatedQuitConditionTests.swift`
(three suites), 5 tests in `MacSlowdown/Tests/IncidentHistoryTests.swift`, 2 in
`MacSlowdown/Tests/MonitorStoreWiringTests.swift`.

Two load-sensitive tests failed on the final run and are the documented ones —
`CPUWorkloadTests.workloadIsAttributed` and
`EndToEndIncidentTests.realSlowdownProducesOneIncident` (at its own "baseline CPU
too high" guard). Both passed on an earlier run of the same tree; other agents were
building concurrently. Neither was touched.

## Not verified — criteria #6 and the on-screen half of #2

**Nothing was put on screen.** To stage it: run the app, then drive an own-uid app
MacSlowdown can measure (TextEdit is easiest) through at least **three**
exit-and-relaunch cycles inside 15 minutes, with each phase longer than the ~2 s
sampling cadence so every exit is actually noticed —
`for i in 1 2 3 4; do open -a TextEdit; sleep 8; osascript -e 'quit app "TextEdit"'; sleep 8; done`.

What to look for: the Incidents list gains **exactly one** new row labelled
"Repeated unexpected quits" — not one per exit, and **not two rows for the one
episode**, which is the specific regression to watch. The row must be **selectable**
(before this change a lifecycle row was not), and the inspector must show the
repeated-quit evidence — sessions, PID pairs, the resource verdict — rather than an
empty resource timeline. The incident should close about six minutes after the last
quit. Then quit and reopen MacSlowdown and confirm the incident is still listed and
still shows its evidence.

Also unverified: whether a real episode's `ResourceVerdict` lands on `.normal`
rather than `.notObserved` in the running app. That depends on retained samples
covering the window, which only a live run can show.
<!-- SECTION:NOTES:END -->
