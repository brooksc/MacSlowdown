---
id: TASK-81
title: Delete or wire nine public conveniences that no caller uses
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-09 20:28'
labels:
  - core
milestone: m-3
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`). TASK-73's acceptance criterion #2 says dead code is not left in place on the grounds that it is tested. These are the residue after the substantive gaps were split into TASK-76 through TASK-80: public surface with no caller anywhere, where nothing is missing from the product — the code is simply unused.

Default action is deletion, along with the tests that only exercise them. Anything kept needs a reason in `probe/seam-allowlist.txt`.

| Member | Where | Note |
|---|---|---|
| `MemoryStatistics.accountedFor` | `Metrics/Sources/MemorySignals.swift:63` | Derived total, no surface. |
| `PowerContext.hasBattery` | `ThermalPowerSignals.swift:67` | App branches on `batteryPercentage` directly. |
| `FamilyMembership.isCertain` | `ProcessFamily.swift:28` | App matches the enum directly. |
| `ProcessFamily.spawnedMemberCount` | `ProcessFamily.swift:61` | Never read. |
| `SafetyPolicy.isProtected` | `SafetyPolicy.swift:93` | App goes through `availability(of:for:)`, which is the right seam. |
| `RedactionOptions.isAtLeastAsRedacted` | `RedactionOptions.swift:72` | Redundant sibling of `weakerThanDefaultWarning`, which is wired at `Shortcuts.swift:130`. |
| `ProcessIdentityResolver.resolutionCount` / `.cachedCount` | `ProcessIdentityResolver.swift:66, 70` | Cache diagnostics with no surface. |
| `ProcessIconCache.cachedCount` | `ProcessNaming.swift:238` | Same. |
| `MemoryPressureMonitor.transitions` | `MemorySignals.swift:140` | The monitor is correctly started and `level` is read; the transition log is not. Judgement call — this one is a plausible source for "pressure has been elevated for N minutes", so it may be worth keeping with an allowlist reason rather than deleting. |
| `LowStorageDetector.isSustained` | `StorageSignals.swift:138` | Duplicates `IncidentPolicy.requiredDuration(.lowStorage)` = 60 s, which the running detector applies. Currently allowlisted; delete when in the file. |
| `MetricsHistory.removeAll()` | `MetricsHistory.swift:155` | Second erase path. "Delete all history" uses `StoredData.deleteRecordedEvidence()`. Keep only if TASK-72 gives it a caller. |
| `PolicyStore.removeAll()` | `ApplicationPolicy.swift:245` | Same; the UI states truthfully that rules are kept. |

`MetricsHistory.restore()` (`:189`) and `HistoryPersistence.acrossRestarts(url:)` (`:67`) are **not** on this list — they belong to TASK-72, which will either give them callers or remove them with the decision.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each member listed is either deleted along with the tests that only exercised it, or kept with a written reason in probe/seam-allowlist.txt
- [x] #2 No behaviour change: the test suite passes with the same count minus only the tests removed alongside deleted code
- [ ] #3 probe/seam-reachability.sh reports zero unexplained findings after this task and TASK-76 through TASK-80
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Done — six deleted, one wired, three kept, one entry wrong

Branch `worktree-agent-a49250753dc5e51b8` on main `fded4a3`. Tests **970 passing, 1 failing** (`EndToEndIncidentTests.realSlowdownProducesOneIncident`, load-sensitive, failed identically at baseline). Baseline 953 passing. **Zero tests deleted** — see below. seam-reachability **16 -> 5 unexplained**; the five left are TASK-76-79's.

### Deleted (6)
Every one was a one-line wrapper over an expression the tests can state directly, so the assertions were rewritten rather than removed and no coverage moved:

| Deleted | Assertions rewritten as |
|---|---|
| `MemoryStatistics.accountedFor` | the sum, inline in `MemorySignalsTests` (2) |
| `PowerContext.hasBattery` | `batteryPercentage == nil` / `!= nil` (2) |
| `FamilyMembership.isCertain` | not referenced by any test; its sibling `isUncertain` is wired and has a written reason to exist, this had neither |
| `ProcessFamily.spawnedMemberCount` | a private helper in `ParentGroupingTests` (4). The app counts the same thing via `GroupingProvenance.byParent`, in one pass over all four evidence kinds, so it was never going to call a single-category property |
| `SafetyPolicy.isProtected` | `policy.protection(for:) != nil` (6). `protection(for:)` returns the *reason*, which is what any UI must show; a bare bool invites showing protection without saying why |
| `RedactionOptions.isAtLeastAsRedacted` | `fieldsLeftInComparedTo(_:).isEmpty` (4, one of them app-side). `weakerThanDefaultWarning`, which names the fields, is the wired form |

### Wired (1) — the one that was a real defect
`ProcessNaming.nameIsTruncatedCommand` is **not** a convenience. `displayName(command:)` marks a cut 16-byte `p_comm` with an ellipsis, and `ProcessNaming.accessibilityLabel(command:)` exists precisely because an ellipsis is silent to VoiceOver — but **neither inventory table used the spoken form**. Both build their own label from a row, so the FR-002 truncation disclosure was visual-only and FR-034 was unmet for every truncated row in two tables.

`InventoryRow` and `AllProcessesRow` now carry `nameIsShortened`, set from `nameIsTruncatedCommand(command:)` at the point the row is built, and both spoken labels append it. The wording is one constant, `ProcessNaming.truncationNote`, so the two tables cannot drift. Five tests in `MeasuredButUnshownTests` drive it from the row builders — including the case that makes it more than a length check: a command that *was* cut but resolved to a real friendly name is not shortened on display.

### Kept, with reasons in `probe/seam-allowlist.txt` (3)
- **`transitions`** — not a convenience. It is the only source for what design 1e shows: "pressure reached critical at 3:16 PM and stayed there for 5 min 40 s" and the markers "crossed warning for 90 s", "normal for 60 s". The incident timeline draws CPU samples and none of those. Staged against **TASK-65.5**. Building it here would have been inventing scope. Its suite also covers FR-007's "transitions captured within 2 seconds", which would have gone with it.
- **`ProcessIdentityResolver.resolutionCount`** — a deliberate test seam. CLAUDE.md makes "resolve once per process lifetime, never per-sweep" a hard rule (~760 ms per full sweep vs ~1.8 ms for the metrics sweep) and this counter is the only way to observe from outside that the cache is used. Deleting it deletes the test for a documented invariant with nothing to put in its place.
- **`cachedCount`** — two declarations share the name. `ProcessIdentityResolver`'s is the case above. `ProcessIconCache`'s **already has a real caller**: `probe/Sources/icon-cost-probe.swift:97`, which the script does not search.

### One table entry was wrong
**`MetricsHistory.removeAll()` has a caller.** `MonitorStore.deleteRecordedHistory()` calls it so that "delete everything" is true of the retained series and not only of the files. TASK-72 landed that after the audit was written. Deleting it broke the build immediately; restored with a comment saying so.

### Out of scope, untouched
`PolicyStore.removeAll`, `PolicyStore.recordSuppression`, `RetentionPolicy`, and everything in `ApplicationPolicy.swift`, `PrivacySettings.swift`, `NotificationPolicy.swift` — another agent owned those this session. `LowStorageDetector.isSustained` stays allowlisted: `StorageSignals.swift` was not mine to edit, so "delete when someone is in the file" still stands.

### Criterion #3 unchecked, deliberately

It reads "zero unexplained findings **after this task and TASK-76 through TASK-80**". TASK-80 is done and contributes none; TASK-76-79 are not, and all five remaining findings are theirs (`ActionVerifier`, `verify`, `recordSuppression`, `addCorrection`, `removeCorrection`). Nothing on TASK-81's own list is reported. The criterion cannot be evaluated until those four land, so it is not mine to tick.

Both tasks left In Progress rather than Done: TASK-80 #3 needs a person at the screen.
<!-- SECTION:NOTES:END -->
