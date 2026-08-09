---
id: TASK-77
title: >-
  FR-039 grouping corrections are built, persisted and unreachable — no UI
  creates one and the grouper is never given them
status: In Progress
assignee: []
created_date: '2026-08-09 18:51'
updated_date: '2026-08-09 21:11'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`).

FR-039 says the user shall be able to correct process-family attribution — correct, split, merge or mark expected. The "mark expected" half works, through `PolicyStore.setPolicy`. The grouping half exists at every layer and is joined at none:

- `GroupingCorrection` (`Metrics/Sources/ApplicationPolicy.swift:104`) — no app reference. No view creates one.
- `PolicyStore.corrections` / `addCorrection` / `removeCorrection` (`:204, :206, :214`) — zero callers; `addCorrection` has 6 test references.
- `PolicyStore.overrides(for:)` (`:223`), which turns corrections into a `GroupingOverrides` explicitly "for FamilyGrouper" — zero callers.
- `FamilyGrouper.group` accepts `overrides:` and defaults it to `.none`. The single app call site, `MacSlowdown/Sources/MonitorStore.swift:488`, does not pass it.

So even if a correction could be made, it could not take effect. Both ends need connecting, not just one.

FR-039's acceptance criteria are "corrections are reversible; raw PID samples remain intact; no correction uploads by default". `removeCorrection` gives reversibility and the persistence is already local-only, so the framework side of those criteria is satisfied — it is the reachability that is missing.

Design input: the Claude Design screens under `design/` should be checked for whether a correction affordance was drawn before inventing one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A user can detach a process from a family or attach it to another from the family inspector or the inventory, and the action creates a GroupingCorrection
- [x] #2 MonitorStore passes PolicyStore.overrides(for:) into FamilyGrouper.group on every sweep, so a correction changes the next grouping
- [x] #3 A correction is reversible from the interface and removing it restores the heuristic grouping
- [x] #4 Raw per-PID samples are unchanged by a correction -- history is not rewritten (FR-039)
- [x] #5 probe/seam-reachability.sh no longer reports addCorrection or removeCorrection
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## TASK-77 — done in code, unverified on screen (2026-08-09)

The design **did** draw this. Screen `1d` has a GROUPING section at the foot of the
inspector with the provenance sentence and two buttons, `Split out…` and
`Merge into…`. Nothing was invented; the ellipses became menus.

### The correction's key, and why it survives a restart and PID recycling

`GroupingCorrection` is keyed on **`executablePath` where one was readable, and the
16-byte `p_comm` otherwise** — never on a PID and never on `(pid, start time)`.
macOS wraps PID allocation at 99999 and the counter had already wrapped on a machine
with twelve days of uptime, so a PID-keyed correction would attach itself to an
unrelated process within days and would not survive a relaunch at all.
`PolicyStore.overrides(for:resolver:)` resolves the durable key back onto the
`ProcessIdentity`s present in *this* snapshot every sweep, so the identity half is
recomputed and never stored.

`p_comm` is 16 bytes, so a command-keyed correction can cover more than one process.
That is stated in the interface (`GroupingCorrectionCopy.scope`) rather than left to
be discovered. `id` is the subject alone, not `kind:subject`, so a second decision
about the same process replaces the first instead of leaving a split and a merge
both stored with whichever `first(where:)` found deciding it.

Persistence is `policies.json` in our own container, alongside the FR-016 rules —
local only, nothing uploaded (FR-039, A-05).

### Where it enters FamilyGrouper

`FamilyInspectorView` → `MonitorStore.correctGrouping` → `PolicyStore.addCorrection`
→ `MonitorStore.regroup(from:)` → `policies.overrides(for:resolver:)` →
`FamilyGrouper.group(snapshot:resolver:overrides:)` → `families` → `inventory`.

`regroup(from:)` is now the **only** place the app groups anything: the sampling loop
calls it too. That is the fix for the defect's actual shape — two paths to one
behaviour with one of them never taken — and it is a stronger guarantee than a test,
because there is no longer a way to reach the interface without the overrides.

`overrides(for:)` returns `.none` immediately when there are no corrections, so the
common case adds nothing to the sweep; otherwise it costs one cached resolver lookup
per process.

### How it is labelled, and how it is reversed

FR-038's four classes are held apart in the copy the user reads before acting:
`GroupingCorrectionCopy.heuristic` says the machine's grouping is "a reasoned guess,
not something macOS tells us"; `.userProvided` says a correction is "recorded as your
correction, not as a measurement" and that it "never changes what an incident already
recorded". A merged member is `FamilyMembership.userAssigned`, which
`GroupingProvenance` already renders as "N processes were placed here by you".

Reversal: an `Undo` button per correction in the inspector's "Your corrections" list,
and the complete list with a remove control in **Settings › Apps › Grouping
corrections** — needed because a merge moves processes out of the inspector that made
it, and a correction whose application is not running has nowhere else to live.

A correction cannot rewrite a past incident: incidents store the `AttributionSample`
built from the families as they were grouped at that moment (TASK-68), and `regroup`
touches `families` only — not `attribution`, not `contributionIndex`, not the
retained series. `InventoryCensus` totals are computed from the families, so they add
up unchanged; asserted.

### Tests

`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .build`
**998 passing, 0 failing** (main baseline 980; 18 added). One intermediate run failed
the two load-sensitive `EndToEndIncidentTests` cases CLAUDE.md names, on a machine
busy with a concurrent build; both passed on quiet runs before and after.

New: `MacSlowdown/Tests/GroupingCorrectionWiringTests.swift`. Every app-level case
starts at `correctGrouping` / `removeGroupingCorrection` and asserts on
`store.families` — a `MetricsTests` case driving `FamilyGrouper.group(overrides:)`
directly would have passed throughout the entire period the defect existed. Covers:
merge reaches the grouper; a correction made before the first sample applies to it;
survives PID *and* start-time replacement; survives a restart through a shared
`policies.json`; undo restores the heuristic; split reaches the grouper; one
correction per subject; no reading or census count changes. Fixtures use PIDs above
99999 so the real identity resolver reliably finds nothing and the grouping under
test is decided by the correction alone.

### seam-reachability

Before: **3 unexplained** (`verify`, `addCorrection`, `removeCorrection`).
After: **1 unexplained** (`verify` — FR-050, TASK-78). `probe/SEAM-AUDIT.md` updated.

### Not verified

**Nothing here has been seen on screen**, so all five criteria are checked on code and
tests only. What would settle the UI half: open Apps & processes, select an
application with more than one process, and in the inspector's GROUPING section (a)
confirm `Split out…` lists the members with the "grouped by guess" one first, (b)
split one out and confirm it appears as its own row and as an undoable entry under
"Your corrections", (c) confirm the same entry appears in Settings › Apps › Grouping
corrections, (d) undo it and confirm the row returns to the family. Menu enablement,
the wrapping of the two paragraphs of copy, and VoiceOver on the Undo buttons are all
unverified for the same reason.
<!-- SECTION:NOTES:END -->
