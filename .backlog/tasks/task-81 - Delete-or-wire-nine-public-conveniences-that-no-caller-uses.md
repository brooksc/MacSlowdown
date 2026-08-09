---
id: TASK-81
title: Delete or wire nine public conveniences that no caller uses
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-09 19:59'
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
- [ ] #1 Each member listed is either deleted along with the tests that only exercised it, or kept with a written reason in probe/seam-allowlist.txt
- [ ] #2 No behaviour change: the test suite passes with the same count minus only the tests removed alongside deleted code
- [ ] #3 probe/seam-reachability.sh reports zero unexplained findings after this task and TASK-76 through TASK-80
<!-- AC:END -->
