---
id: TASK-79
title: >-
  Two privacy controls change a stored value and no behaviour: retention and
  'Record file paths'
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-09 20:22'
labels:
  - core
  - ui
milestone: m-3
dependencies:
  - TASK-72
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`). Same class as TASK-70's `hideFilePaths` and TASK-69's alert settings: a control the user changes that changes nothing.

**Re-verified 2026-08-09. The description below has been corrected; the original claimed both halves were inert, and by the time this task was picked up only one was.**

`AlertSettings.privacySettings` gathers both settings into a `PrivacySettings`.

**"Keep incident history for" (7 / 30 / 90 days)** — **already fixed by TASK-72**, which merged earlier the same day. `MonitorStore.privacySettings` reads `alertSettings?.privacySettings` and passes it to `IncidentHistoryStore` on load, on every write, and on every sample via `enforceRetention`; `IncidentHistoryStore.bounded` calls `RetentionPolicy.retained`. The footer is fixed too: `IncidentHistory.retentionFooter` now takes the period from the setting *and* names the count bound, so the explanation and the control describe the same mechanism. Nothing to redo.

**"Record file paths"** — this half was still inert. Paths were resolved and retained regardless.

The honest scope turned out to be narrower than "record paths or don't". Path *resolution* cannot be switched off: the outermost `.app` in the executable path is what groups an application's processes and what finds its icon, so a control over resolution would break the product, and one that claimed to and did not would be worse. What is a genuine choice is whether a location is **kept** — written into the incident history that persists for up to ninety days. The shipped default is off, and the app was recording them anyway, so the default was already making a promise the app did not keep.

FR-029's acceptance criteria are about locality, deletion and accessible privacy settings; they do not require a path control, so removing the row would also have been compliant. Wiring it was chosen because the default already claimed the behaviour.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The retention setting either takes effect -- RetentionPolicy.expired is applied to stored incidents on a schedule -- or is replaced by a statement of what the app actually keeps, in the manner of the 'Keep history across restarts' row
- [x] #2 The retention explanation and the retention control describe the same mechanism; a count cap is not explained as a time window
- [x] #3 'Record file paths' either changes whether executable paths are recorded and retained, or is removed
- [x] #4 AlertSettings.privacySettings has a real reader in app code, or is deleted
- [x] #5 probe/seam-reachability.sh no longer reports RetentionPolicy or expired, and the allowlist entries for them are removed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Re-verified and fixed (2026-08-09)

### The retention half was already done — evidence, not assumption

TASK-72 wired it. Verified by reading the chain rather than by trusting the task: `MonitorStore.privacySettings` (`MacSlowdown/Sources/MonitorStore.swift`) returns `alertSettings?.privacySettings ?? .default`, and it is passed to `IncidentHistoryStore.load` at construction, to `record` on every close, to `replace` when an incident is mutated in place, and to `enforceRetention` on **every sample** — so a machine simply left running ages incidents out without any screen being open. `IncidentHistoryStore.bounded` calls `RetentionPolicy.retained`. Criterion #1 met.

Criterion #2: `IncidentHistory.retentionFooter(limit:retention:)` takes the period from `AlertSettings.shared.retention` and the count from `MonitorStore.retainedIncidents` and states both — "kept for 30 days on this Mac, and no more than the 200 most recent — whichever comes first". The count cap is no longer explained as a time window. Met.

Criterion #4 was met by the same work: `AlertSettings.privacySettings` has a real reader in `MonitorStore.privacySettings`. It now has two.

Criterion #5: `probe/seam-reachability.sh` already did **not** report `RetentionPolicy` or `expired` at the start of this task. The two allowlist lines were stale and are deleted (`probe/seam-allowlist.txt` is down to `isSustained` and `isDestructive`).

I have corrected the task description rather than leaving its claims to mislead the next reader.

### 'Record file paths' — wired, with the scope narrowed to what is true

Both options were weighed. Removing the row (the `Keep history across restarts` model) would still have satisfied FR-029, whose acceptance criteria are locality, deletion and accessible settings and say nothing about paths. Wiring it won on one fact: **the shipped default is off, and the app recorded paths anyway** — so the default was already making a promise, and the cheapest way to make the app honest was to keep it.

What the control cannot mean: path *resolution* is how families are grouped (the outermost `.app` is the grouping anchor) and how icons are found. A switch over resolution would break the product. So the control governs what is **kept**.

`MonitorStore.recordable(_:)` reads `privacySettings.recordFilePaths` and, when off, rewrites the attribution sample the detector is given: `bundlePath` is dropped and `applicationID` — which *is* the bundle path wherever one exists — becomes the name-keyed form. Rewriting the id was not optional; leaving it would have kept the location on disk under a different field name. `bundleID` is kept, because a signing identifier says which application, not where the user put it. Recurrence across incidents still works on the name key, which is already the fallback for the ~85% of processes that live in no bundle; the cost is that two applications sharing a display name are no longer told apart, and that is written down in the code.

The row's copy now says which half is a choice: "MacSlowdown always reads locations while monitoring — that is how it groups an app's processes and finds its icon — so this changes only what is written to disk." A user who sees a path in the Family Inspector with the switch off is not looking at a bug.

Export is untouched: it has its own path control (`RedactionOptions.hideFilePaths`, wired by TASK-70), and two controls over one surface would be worse than one over each.

### Tests

`MacSlowdown/Tests/SuppressionAndPathRecordingTests.swift`, suite "'Record file paths' changes what is recorded" — 4 tests, all app-level: off by default strips location and id while leaving name, bundle id and figures intact; flipping the setting changes what `MonitorStore.recordable` produces, both ways; **the written `incidents.json` contains no `/Applications/Xcode.app` anywhere in its bytes** (a field-by-field check would miss a path arriving through some other key) while still naming the application; and a retention check driven from `AlertSettings.privacySettings`, so criterion #4 is a test rather than a claim.

Full suite on the rebased branch: **963 passing, 0 failing**. Main at fded4a3 was 954.

`probe/seam-reachability.sh`: 16 unexplained before, **15 after**, allowlist 4 entries → 2.

### Not verified

Nothing here was seen on screen. The Privacy tab's new copy is longer than the row it replaces and may wrap differently; the check that would settle it is opening Settings → Privacy and confirming the row reads cleanly and the toggle is reachable by keyboard.

Commit: `2a0eb18` on `worktree-agent-a09f64177e86529db`.
<!-- SECTION:NOTES:END -->
