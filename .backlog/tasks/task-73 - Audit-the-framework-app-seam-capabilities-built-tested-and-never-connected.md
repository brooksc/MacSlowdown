---
id: TASK-73
title: 'Audit the framework-app seam: capabilities built, tested, and never connected'
status: To Do
assignee: []
created_date: '2026-08-09 18:23'
updated_date: '2026-08-09 18:53'
labels:
  - core
  - risk
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Raised as a pattern, not an incident.** Five times in one session, work was found that was fully implemented in the `Metrics` framework, covered by passing tests, and simply never wired into the running app. Twice a requirement had green tests and **could not fire in the product at all**.

The confirmed instances:

| Found | Capability | Consequence |
|---|---|---|
| TASK-66 | `lowStorage` never passed into `SystemObservation` | FR-041/FR-042 could never raise an incident |
| TASK-66 | `MetricsHistory` private, no accessor | every sparkline in the design unbuildable |
| TASK-66 | no `PolicyStore` owner | FR-016 framework-only |
| TASK-66 | `LifecycleTracker` undriven | "relaunches today" had no source |
| TASK-69 | `AlertSettings` unread by the detector | every alert control changed a value and no behaviour |
| TASK-71 | no `IncidentCondition` for repeated quits | design 1o can never be shown |
| (open) | `RetentionPolicy.expired` never called | retention defined, never enforced |

The through-line: **a passing test proves a unit works, not that anything calls it.** Our test suite is strong at the framework level and that strength hid the gap — the code was right, the wiring was absent, and nothing failed.

This is not a request to rewrite anything. It is a request to **look deliberately for the next one** rather than trip over it, and to leave behind something that makes the class of defect visible.

Worth checking specifically: every public type in `Metrics/Sources/` that no file under `MacSlowdown/Sources/` references; every `RedactionOptions`-style options struct whose fields are read nowhere (TASK-70 found `hideFilePaths` was inert — the control existed and did nothing); every setting in `PrivacySettings`; and every FR whose acceptance criteria are satisfied only by framework tests.

Note the honest counter-argument, which should be weighed rather than dismissed: some of these are deliberate staging, where the framework was built first on purpose. The audit's job is to tell staged work apart from forgotten work, and to record which is which — not to treat every unreferenced type as a bug.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every public type and public entry point in Metrics/Sources is classified as: used by the app, deliberately staged for later work, or forgotten -- with the list recorded
- [ ] #2 Each 'forgotten' item gets a task or is removed; dead code is not left in place on the grounds that it is tested
- [ ] #3 Every requirement whose acceptance criteria are met only by framework tests is identified, and it is stated for each whether the behaviour can actually occur in the running app
- [ ] #4 A check exists that would catch the next instance -- whatever form is practical, from a documented review step to a test that asserts a capability is reachable end to end
- [ ] #5 The audit distinguishes deliberate staging from oversight rather than treating every unreferenced type as a defect
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit complete, read-only. No `.swift` file modified, no build or test run. Full classification table in `probe/SEAM-AUDIT.md`. Two new non-Swift files: `probe/seam-reachability.sh` and `probe/seam-allowlist.txt`.

**Counts.** 130 public types: 121 used, 2 staged, 7 forgotten. 400 public members: 371 used, 6 staged, 23 forgotten.

The "used" bucket includes types reached transitively. 23 of the 32 types with no direct app reference are in it — the app calls `StorageSignals.snapshot()` without spelling `StorageSnapshot`. Counting those as forgotten would have produced a list nobody would read, which is the reason "unreferenced by the app" is the wrong discriminator.

**FRs whose criteria are met only by framework tests, with whether the behaviour can occur:**

- FR-016 (per-app policies) — suppression happens, the audit trail cannot. `MonitorStore.swift:575` drops the `.suppress` decision, so `SuppressedDetectionsSheet` is permanently empty and its copy is false whenever a rule did suppress something. → **TASK-76**
- FR-029 (retention) — **no**. `RetentionPolicy.retained`/`.expired` have no caller. Two Privacy-tab controls write `UserDefaults` and are read by nothing. → **TASK-79** (depends on TASK-72)
- FR-039 (correct family attribution) — grouping half **no**; `MonitorStore.swift:488` never passes `overrides:` and no view creates a `GroupingCorrection`. "Mark expected" half works. → **TASK-77**
- FR-050 (verify remediation) — **no**. 22 test references on `ActionVerifier.verify`, zero callers. Arguably correct staging given FR-020–024 are deferred, but nobody wrote that down. → **TASK-78** (decision)
- FR-008 swap usage, FR-009 per-app-I/O disclosure, FR-038 start provenance and storage-trend label — measured, never shown. → **TASK-80**
- Residual unused conveniences → **TASK-81**

Verified as genuinely reachable and needing nothing: FR-042 (TASK-66's wire holds; `IncidentPolicy.requiredDuration(.lowStorage)` = 60 s enforces sustained-ness, so `LowStorageDetector.isSustained` is redundant not missing), FR-028 (TASK-70's `hideFilePaths` finding is closed — all three redaction fields read at `ExportDocument.swift:431-459` from both the sheet and the App Intent), FR-054, FR-007, FR-040.

**Staging done properly, for the record.** `PrivacySettings.persistAcrossRestarts` is the model: the reason is in `AlertSettings.swift:215`, the user is told the truth at `SettingsView.swift:512` ("This session only"), and CLAUDE.md lists the open question. Every other staged item was staged by silence. That distinction is what criterion #5 asked for and it is the audit's main conclusion: undocumented staging and having forgotten are indistinguishable six weeks later.

**The check (criterion #4).** `probe/seam-reachability.sh`. The discriminator is *declared public, referenced by tests, referenced by no caller* — zero call sites in `MacSlowdown/Sources/` and none in `Metrics/Sources/` beyond the declaration, while at least one test exercises it. That is the exact signature of all five confirmed instances. Run today it gives 20 hits with no manual triage, including three (`isProtected`, `isCalculated`, `isDestructive`) the manual pass missed; 4 are now allowlisted with reasons, 16 remain and are covered by TASK-76…81. Needs no build, takes ~30 s. Known blind spot: matching is by name, so a member two types share is invisible — `MetricsHistory.restore()` is dead while `StorageHistory.restore()` is live, and three findings came from reading call sites instead.

TASK-71 and TASK-72 were already open and are referenced rather than duplicated.
<!-- SECTION:NOTES:END -->
