---
id: TASK-65.6
title: 'Screen 1f — Incidents: history and patterns'
status: In Progress
assignee: []
created_date: '2026-08-09 02:23'
updated_date: '2026-08-09 04:58'
labels:
  - ui
milestone: m-2
dependencies: []
modified_files:
  - MacSlowdown/Sources/IncidentsView.swift
  - MacSlowdown/Sources/IncidentHistory.swift
  - MacSlowdown/Tests/IncidentHistoryTests.swift
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1f.png`. Current state: `screenshots/04-incidents.png` (currently renders blank — see TASK-51.1). Existing implementation: `IncidentsView` (TASK-51).

**What the design specifies**

More than a list. Top of the pane carries a range selector (7 days / 30 days) and a **pattern summary**: "9 incidents this week / Chrome appears in 5 of them", above a Mon–Sun strip showing when they fell. That summary is the feature — a single incident is an event, five with the same app in them is a finding.

Each row states condition and attributed app together ("CPU maxed out — Xcode", "Memory pressure — Chrome"), then a subtitle carrying date, duration, severity, and **outcome**, where outcome is a distinct vocabulary:
- "still going"
- "recovered after you acted"
- "resolved on its own"
- "Not alerted — you marked Handbrake as expected"

Row four is a repeated-crash incident ("Final Cut Pro quit unexpectedly — 3 times in 12 minutes … CPU and memory were both normal"), which is screen 1o's incident appearing in the list — so the list must carry lifecycle incidents, not only resource ones.

Footer: "Incidents are kept for 30 days on this Mac and never leave it unless you export one."

**Gap against what we render today**

Our rows carry condition, severity, start time, duration and recovered/still-going, which covers part of it. Missing: the range selector, the pattern summary and week strip, the app name in the row title, the richer outcome vocabulary (particularly "recovered after you acted" and "not alerted because you marked it expected"), and the retention footer. The empty state is currently broken (TASK-51.1) and must be fixed for this screen to be assessable at all.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The list is scoped by a selectable time range
- [x] #2 A summary states how many incidents fell in the range and names any application recurring across several of them
- [ ] #3 Each row states the condition together with the attributed application, and its outcome using a vocabulary that distinguishes recovered-on-its-own, recovered-after-user-action, still-open, and suppressed-by-a-user-rule
- [ ] #4 Lifecycle incidents such as repeated unexpected quits appear in the same list as resource incidents
- [x] #5 Retention and the local-only guarantee are stated on the screen (FR-029)
- [ ] #6 Verified on screen against design/screens/1f.png with several incidents of differing outcomes present
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built

`MacSlowdown/Sources/IncidentHistory.swift` (new) holds every rule the screen
turns on, so none of it needs a screen to test: the range, the outcome
vocabulary, the entry model that carries resource *and* lifecycle findings, the
pattern rule, the day strip and the footer copy. `IncidentsView.swift` is the
view over it: a 7 days / 30 days segmented picker in the toolbar, a headline and
recurrence line, a day strip, the list, and a footer.

`MacSlowdown/Tests/IncidentHistoryTests.swift` (new), 21 tests. Full suite
**407 passing, 0 failing** (`tuist xcodebuild test -scheme AllTests`, run three
times, no flakes seen this session).

## Which outcome vocabulary the data actually supports — two of four

The design asks for four outcomes. `Incident` carries `id`, `beganAt`,
`triggeredAt`, `recoveryStartedAt`, `closedAt`, `conditions`, `severity`,
`peakCPUBusyFraction`, `peakMemoryPressure` — and nothing else. So:

- **"still going"** — supported, from `isOpen`.
- **"resolved on its own"** — *not* supported as written. We know conditions
  cleared. We do not know that nobody acted, because no action is recorded
  against an incident. The row therefore says **"recovered — no action was
  recorded"**, which is what we measured. Inferring "on its own" from the absence
  of a record would be the same error FR-050 forbids.
- **"recovered after you acted"** — not derivable today. `ActionVerification`
  exists (`Metrics/Sources/ActionOutcome.swift`) but nothing links one to an
  incident and `MonitorStore` never stores one. `IncidentHistory.outcome` accepts
  an `ActionVerification` and requires it to have *run* and to fall inside the
  incident's own window; the app passes nil. It is never inferred from timing.
- **"Not alerted — you marked Handbrake as expected"** — not derivable today.
  `SuppressedDetection` exists with application, classification, time and
  severity, but it is not keyed to an incident, and `PolicyStore` is not
  instantiated anywhere in the app (only in `Metrics/Tests`). Same treatment:
  accepted as a parameter, never inferred.

Both undelivered branches are covered by tests, so wiring them later is a data
change, not a UI change.

## What the design needs that we do not store

1. **Per-incident attribution.** The design's row title is "CPU maxed out —
   Xcode". An `Incident` records no contributor, and `store.attribution` is a
   *live* reading, not a snapshot taken during the incident. So an application is
   named only on an **open** incident, from the current leading contributor, and
   the row carries the caveat "…is the largest contributor we can measure right
   now — heuristic, not a cause" (FR-013). Closed rows name no application, and
   the footer says why rather than leaving the reader to notice.
2. **Application recurrence.** "Chrome appears in 5 of them" is therefore
   uncomputable. The summary states the recurrence we *can* establish — the
   recurring **condition**: "CPU saturation in 6 of them". If per-incident
   attribution is ever stored, the same code produces the design's sentence.
3. **A user-action record on an incident**, and **a suppression record keyed to
   an incident** — see above.
4. **Lifecycle findings are not published.** `RelaunchPattern` and
   `LifecycleTracker` exist and are tested, but `MonitorStore` runs no tracker and
   exposes no patterns; only `GuidedInvestigation` and `OverheadHarness` use them.
   The list model, the row, the sorting and the pattern counting all handle
   `.repeatedQuits` and are unit-tested, but the view passes an empty array —
   `MonitorStore` was owned by another agent this session and could not be edited.
   **AC#4 is left unchecked for that reason**: the list carries lifecycle
   incidents, but nothing feeds it one yet.
5. **30-day retention.** The design's footer claims incidents are kept for 30
   days. They are not: `MonitorStore.retainedIncidents` is 20, held in memory, and
   nothing persists them across a restart. The footer states that instead
   (FR-029), and a test asserts the string does *not* say "30 days".

## Pattern rule

A recurrence is stated only when at least 3 incidents fall in the range **and**
the recurring condition appears in at least 3 of them. With two incidents the
screen says the count and nothing more. Tested both ways.

## TASK-51.1's open question is NOT resolved by this

This branch's copy of `IncidentsView.swift` still contained both constructs
TASK-51.1 removed (that branch is not merged here), so both are gone from the
rewritten file: no `.constant` inspector binding, and no `navigationDestination`
registered with `EmptyView()`.

What was **added** and why it is sound:

- `.inspector(isPresented:)` with a real two-way `Binding` whose setter clears
  `selection`, so SwiftUI's write-back on dismissal is honoured. This replaces the
  `.constant` binding rather than reintroducing it.
- Rows are tagged only when they carry an `Incident.ID`; a lifecycle row is
  untagged and unselectable, so selection can never open an empty inspector.
- No navigation destination of any kind is registered.
- The pane is a plain `VStack` of header / `List` / footer with the picker in the
  toolbar. No new container that could collapse.

**None of this proves the blank pane is fixed.** Nobody has looked at the screen,
and the file has been substantially rewritten, so the earlier correlation no
longer applies to this code either way.

## Not verified — needs a person at the screen

- **AC#6** and, strictly, AC#1/#2/#5 on screen. Nothing was launched, driven or
  screenshotted: CLAUDE.md forbids taking the screen without permission, and six
  agents were running concurrently. Checked criteria mean "implemented and covered
  by tests", not "seen".
- Whether the pane renders at all (TASK-51.1).
- The day strip's proportions and the toolbar picker's placement against
  `design/screens/1f.png`.
- Accessibility: every strip column and every row carries a spoken label, but no
  VoiceOver pass was made (TASK-15).
<!-- SECTION:NOTES:END -->
