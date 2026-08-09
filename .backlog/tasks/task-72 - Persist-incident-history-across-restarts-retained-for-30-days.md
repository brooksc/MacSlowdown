---
id: TASK-72
title: 'Persist incident history across restarts, retained for 30 days'
status: In Progress
assignee: []
created_date: '2026-08-09 18:23'
updated_date: '2026-08-09 19:15'
labels:
  - core
  - decision
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Product owner decision, 2026-08-09.** This closes the question `CLAUDE.md` has carried under "Undecided — ask, don't assume" since the start: whether incidents persist across restarts, and the default retention.

**Decided: persist across restarts, on by default, retained 30 days.**

Today history is **20 incidents, in memory, lost on quit** — `MetricsHistory` defaults to `.memoryOnly`. So the app currently forgets everything each launch, which makes recurrence detection ("this app appears in five of them") impossible across sessions and makes the 30-day figure in the design a fiction. TASK-65.6 wrote a test asserting the retention footer does *not* claim "30 days"; that test should now change with the behaviour, not before it.

## What already exists

- `HistoryPersistence.acrossRestarts` exists and is budgeted at roughly 3.6 MB/hour.
- `RetentionPolicy.expired` exists **and nothing calls it** — retention is defined and never enforced.
- `PrivacySettings.retention` is a real setting that TASK-69 deliberately left unwired, precisely because wiring it edged into this decision.
- TASK-65.10 built the retention picker and shows the measured bytes in the container beside it, so the cost is visible.

## Do not promise encryption

The design's copy says "Stored encrypted in the app's own container". **Do not ship that sentence.** FileVault is the user's setting, not ours, and `NSFileProtection` on macOS is not the guarantee people read it as. TASK-65.10's recommended wording, which stands: *"in MacSlowdown's own container, which no other app can read"*. That is true and checkable.

## Consequences to handle rather than discover

- **Retention must be enforced on write**, not only described. An expiry policy nobody calls is the same class of defect as the four already found this session where a capability existed and nothing connected it.
- The stored figure must agree with the interface: whatever is actually kept is what the Privacy tab and the incidents footer say is kept (FR-029).
- Incidents now carry recorded attribution (TASK-68), so persistence means persisting that too — including its confidence, which must survive a round trip rather than being recomputed from live state on load.
- A schema version belongs in the stored form. The export already carries one; history should, so a later format change can migrate rather than silently discard.
- Deleting all history must actually delete it, and say how much it removed — TASK-65.10 already implemented that against the current store and excludes `policies.json`.

Update `requirements.md` and remove the question from `CLAUDE.md`'s "Undecided" section once this lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Incident history survives quitting and relaunching the app, verified by an actual restart rather than by a serialisation round-trip in a test
- [x] #2 Retention is enforced, not merely configured: an incident older than the retention period is removed, and the enforcement runs without the user opening any particular screen
- [ ] #3 The retention period is user-adjustable and whatever the interface states is kept is what is actually kept (FR-029)
- [x] #4 Recorded attribution and its confidence survive persistence unchanged, and are never recomputed from live state on load (FR-013, FR-038)
- [x] #5 The stored form carries a schema version so a later change can migrate rather than discard
- [x] #6 No copy claims the store is encrypted; it states that the container is not readable by other apps
- [x] #7 Delete-all removes the history and reports how much it removed, leaving user policies intact
- [x] #8 requirements.md records the decision and CLAUDE.md's 'Undecided' entry for persistence and retention is removed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## TASK-72 implemented (worktree `worktree-agent-a019a30a64f03d323`)

### On-disk format

`incidents.json`, in the app's Application Support directory — under the sandbox
`~/Library/Containers/<bundle id>/Data/Library/Application Support/MacSlowdown/`,
beside `policies.json` and deliberately separate from it so "delete all history"
can take one without the other.

The document is `StoredIncidentHistory` (`Metrics/Sources/IncidentHistoryStore.swift`):
`schemaVersion` (currently 1), `writtenAt`, `retentionDays`, `limit`, `incidents`.
A file whose `schemaVersion` exceeds ours is **refused and left in place** — decoding
half of it would show invented history and overwriting it would destroy history a
newer build can still read. `Incident`'s decoder tolerates a missing field wherever
the property has a default, so an additive change does not need a version step.

Dates are encoded **numerically, not ISO-8601**. `.iso8601` truncates to whole
seconds, which broke round-trip identity outright and would have let `covers()`
disagree about whether an action fell inside an incident. Found by a failing test,
not by reasoning.

### Retention

Enforced in `IncidentHistoryStore`, on every path that changes the stored set —
`record`, `replace`, `load`, and `enforceRetention`. `RetentionPolicy.expired`/
`retained` finally has a caller. Enforcement is driven from `MonitorStore`'s sampling
loop (`enforceRetention` every sample, writing only when something actually expired),
so an incident ages out on a machine that is simply left running, with no screen open
and nothing closing. Retention is also applied on **load**, so a Mac switched off for
two months never shows expired incidents even briefly.

**Two bounds, both real, both stated.** Age, from `PrivacySettings.retention`
(user-adjustable 7/30/90, default 30); and count, `MonitorStore.retainedIncidents`,
now `IncidentHistoryStore.defaultLimit` = **200** (was 20 in memory). A period alone
bounds nothing on a machine in trouble all day, so FR-005's "bounded" needs both.
`IncidentHistory.retentionFooter(limit:retention:)` states both and reads the period
from the setting, so the interface cannot promise a retention the store is not
applying. Its call-compatible signature was kept — `IncidentsView.swift` is untouched.

### Attribution

`Incident` is now `Codable` (with `MemoryPressureLevel`, `ProcessAction`,
`ActionResult`, `VerificationOutcome`, `ActionVerification`). `IncidentAttribution`
already was. Nothing on the read path recomputes anything; the decoder is
hand-written and has no fallback that could reconstruct an attribution.

Proved two ways: a whole-record `Equatable` comparison after a real file round trip
through two independent store objects, and — the stronger one — a test that writes a
file whose stored `confidence` is `high` when the figures beside it recompute to
`low`, then asserts the decoded value is `high`. If anything recalculated, that test
fails.

### Deletion

`MonitorStore.deleteRecordedHistory()` clears the in-memory incidents, the metric
series, and the files. Clearing only the file would have let the next close write the
"deleted" incidents straight back. It returns incidents / files / bytes, and the
Privacy tab prints all three. `policies.json` is excluded by name, as before.
`StoredData` deletion now takes an injectable directory so the test suite cannot
delete the running user's real history.

### Not persisted, on purpose

The FR-005 rolling **metric sample series** stays memory-only. Its only non-display
consumer re-dates a breach start against readings that were actually taken; restoring
a series from a previous run could date an incident to a period during which the app
was not running. Recorded in `requirements.md` under FR-005.

### Tests

`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .build`

**866 passing, 0 failing** (was 845). +21: 15 in `MetricsTests`
(`IncidentHistoryStoreTests`), 5 in `MacSlowdownTests` (`IncidentPersistenceTests`),
1 extra footer test. Two existing tests changed **with** the behaviour:
`IncidentHistoryTests`' footer test (TASK-65.6's assertion that the footer must
*not* say "30 days" — it now must, alongside the count bound), and
`PresentationTests.retentionBounds`, which hard-coded 25 incidents and would have
silently stopped bounding anything once the limit rose.

### Criteria

Checked: #2, #4, #5, #6, #7, #8.

**#1 not verified by a real app restart** — needs the screen or a launch. What was
verified instead: a store writes to a real file and a *second, independently
constructed* store reads it back identically; and a separate OS process (`grep`)
finds the record in the file, so the bytes are genuinely on the filesystem rather
than in a shared object. What that does **not** prove: that the container path
resolves as expected in the signed sandboxed `.app`, that `MonitorStore.shared` is
constructed early enough at launch for a window to show restored history, or that
anything appears on screen. Staging a real check: quit the app, run
`./run-menubar.sh`, let an incident close (or hand-write an `incidents.json` into the
container), quit, relaunch, confirm the Incidents pane lists it and that
`.../Application Support/MacSlowdown/incidents.json` exists with `schemaVersion` 1.

**#3 left unchecked**: the retention picker is user-adjustable and now genuinely
drives the store, and the footer and Privacy copy are derived from the same setting
and covered by tests — but **nobody has looked at the Privacy tab or the Incidents
footer on screen**, and TASK-51.1 means the Incidents pane's rendering is itself
still unconfirmed. A UI criterion is not met by a passing unit test.

### Left for someone else

- `AlertSettings.swift` is owned by another agent this session and could not be
  edited. Its doc comment on `privacySettings` still says whether history survives a
  restart "is an open product decision" and that building the switch "would settle it
  by accident". Stale now; the behaviour is right (`persistAcrossRestarts` defaults
  to true and is deliberately not surfaced as a control).
- `Presentation.retained` no longer has a caller in the app — `MonitorStore` bounds
  through the store. `Presentation.swift` was outside this task's editable set, so it
  was left alone rather than deleted.
<!-- SECTION:NOTES:END -->
