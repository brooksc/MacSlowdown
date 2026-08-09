---
id: TASK-73
title: 'Audit the framework-app seam: capabilities built, tested, and never connected'
status: Done
assignee: []
created_date: '2026-08-09 18:23'
updated_date: '2026-08-09 21:00'
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
- [x] #1 Every public type and public entry point in Metrics/Sources is classified as: used by the app, deliberately staged for later work, or forgotten -- with the list recorded
- [x] #2 Each 'forgotten' item gets a task or is removed; dead code is not left in place on the grounds that it is tested
- [x] #3 Every requirement whose acceptance criteria are met only by framework tests is identified, and it is stated for each whether the behaviour can actually occur in the running app
- [x] #4 A check exists that would catch the next instance -- whatever form is practical, from a documented review step to a test that asserts a capability is reachable end to end
- [x] #5 The audit distinguishes deliberate staging from oversight rather than treating every unreferenced type as a defect
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

## Audit complete — `probe/SEAM-AUDIT.md`

130 public types and 400 public members classified: 121 types used, 2 staged, 7 forgotten; 371 members used, 6 staged, 23 forgotten. Every FR whose criteria are met only by framework tests is traced to a call chain or shown to have none.

**The useful discriminator is not 'unreferenced by the app.'** That flags 32 types and 23 of them wrongly — the app calls `StorageSignals.snapshot()` without ever spelling `StorageSnapshot`. It is **public, exercised by tests, called by nobody**: no call site in `MacSlowdown/Sources/`, none in `Metrics/Sources/` beyond the declaration, and at least one test that does drive it. That is the signature of all five previously confirmed instances.

**The check that catches the next one:** `probe/seam-reachability.sh` with `probe/seam-allowlist.txt`. No build, ~30 s, so it can gate a commit long before there is CI. Staged work goes in the allowlist **with a written reason** — a bare name is rejected, because undocumented staging and having forgotten are indistinguishable six weeks later.

**Its one blind spot, found the hard way:** matching is by name, so a member two types share is invisible. `MetricsHistory.removeAll()` was reported as forgotten when `MonitorStore.deleteRecordedHistory()` had called it since TASK-72 — deleting it broke the build immediately. One false entry and one masked entry from the same cause. Three of the audit's findings came from reading call sites rather than counting.

## Work this produced, all done in the same session

- TASK-76 — suppressed detections never recorded. **Done.** FR-016's audit trail was permanently empty and the sheet's empty state was a false statement whenever a rule had suppressed something.
- TASK-79 — two inert privacy controls. **Done.** Retention turned out already fixed by TASK-72 (verified by tracing, not assumed); 'Record file paths' was still inert and is now wired.
- TASK-80 — four measured-but-unshown disclosures. **Done.** Found a second instance of the drift it was about: two hand-written paraphrases of the same sandbox limitation on one screen, and a test asserting a copied phrase.
- TASK-81 — nine unused conveniences. **Done.** Six deleted with their assertions rewritten rather than removed, three allowlisted with reasons, and one turned out to be a real defect: `nameIsTruncatedCommand` existed because `p_comm` is 16 bytes and the ellipsis marking a cut is silent to VoiceOver — and neither inventory table used the spoken form, so FR-034 was unmet for every truncated row in two tables.
- TASK-77 — FR-039 grouping corrections unreachable. Open.
- TASK-78 — FR-050 post-action verification. **A product decision, not a defect**, and deliberately left for the owner.

Seam-reachability went 16 unexplained → 5 over the session; the five remaining are TASK-77's and TASK-78's.

## The honest limit

This audit is static reading. It proves a call site exists, not that the call is reached at runtime under real conditions. The complement worth building later is a small reachability test bundle — drive `MonitorStore` through a synthetic suppressed detection, a completed action and a grouping correction, and assert the end effect. Those three assertions would have failed on the day each gap was introduced.
<!-- SECTION:NOTES:END -->
