# Framework–app seam audit (TASK-73)

Read-only audit, 2026-08-09. No `.swift` file was modified and no build or test was
run. Everything below is from static reading of `Metrics/Sources/`,
`MacSlowdown/Sources/`, `requirements.md` and the two test trees.

The question is not "is this type used" but **"can this behaviour occur in the
running product"**. A type can be unnamed in the app and still be exercised on
every sample; a type can be named in ten places and still hold a value nothing
reads. Both cases appear below.

## Method

1. Extracted every `public` declaration in `Metrics/Sources/*.swift`:
   **130 types** and **400 members**.
2. Counted word-boundary references in `MacSlowdown/Sources/` (a caller),
   `Metrics/Sources/` excluding the declaring line (an internal caller), and the
   two test trees (coverage, which is *not* a caller).
3. Classified each as **used**, **staged** or **forgotten**.
4. Walked `requirements.md` for FRs whose acceptance criteria are met only by
   framework tests, and traced each from `MonitorStore`/`AppDelegate`/a view down
   to the framework, or established that no chain exists.

Method limit, stated because it matters when reading the counts: matching is by
name, so a member shared by two types cannot be told apart. `restore()` exists on
both `MetricsHistory` and `StorageHistory`; the app calls `StorageHistory.restore()`
(`MacSlowdown/Sources/StorageScreenModel.swift:48`) and never
`MetricsHistory.restore()`, and a name-only sweep reads that as covered. Three
findings below were reached by reading call sites rather than by counting.

## Counts

| Level | Total | Used | Deliberately staged | Forgotten |
|---|---|---|---|---|
| Public types | 130 | 121 | 2 | 7 |
| Public members | 400 | 371 | 6 | 23 |

"Used" includes types reached transitively. 23 of the 32 types with no direct app
reference are in this bucket: the app calls `StorageSignals.snapshot()` without
ever spelling `StorageSnapshot`, drives `InvestigationBuilder.build` without naming
`InvestigationStep`, and so on. Counting those as forgotten would have produced a
list nobody would read.

## Forgotten — types

| Type | Where | Consequence |
|---|---|---|
| `RetentionPolicy` | `Metrics/Sources/PrivacySettings.swift:78` | Retention is defined and never enforced. |
| `GroupingCorrection` | `Metrics/Sources/ApplicationPolicy.swift:104` | No UI creates one. FR-039's correct/split/merge does not exist. |
| `GroupingOverrides` | `Metrics/Sources/ProcessFamily.swift:71` | `FamilyGrouper.group` accepts `overrides:`; the one app call site (`MacSlowdown/Sources/MonitorStore.swift:488`) never passes it, so a correction could not take effect even if one could be made. |
| `SwapUsage` | `Metrics/Sources/SwapSignals.swift:5` | Swap bytes-in-use and encrypted-swap are measured and never displayed. |
| `MemoryPressureMonitor.Transition` | `Metrics/Sources/MemorySignals.swift:119` | The monitor is properly started and its `level` is read; the recorded transition log is not, so "pressure has been high for N minutes" has no source. |
| `ActionVerifier` | `Metrics/Sources/ActionOutcome.swift:83` | Nothing ever produces an `ActionVerification`. FR-050 cannot occur. |
| `VerificationOutcome` | `Metrics/Sources/ActionOutcome.swift:20` | Same chain. |

## Forgotten — members

Ordered by consequence, not by file.

| Member | Where | Consequence |
|---|---|---|
| `PolicyStore.recordSuppression` | `ApplicationPolicy.swift:192` | **`NotificationGate.decide` returns `.suppress(reason:)` at `MonitorStore.swift:575` and the result is dropped.** No `SuppressedDetection` is ever written, so `SuppressedDetectionsSheet` (`SettingsView.swift:429`) can only ever render its empty state. FR-016's "why was I not told" trail is permanently blank, and the empty state's copy ("Nothing has been suppressed by a rule") is therefore a false statement whenever a rule did suppress something. |
| `MonitorStore.record(suppression:)` | `MacSlowdown/Sources/MonitorStore.swift:179` | App-side half of the same gap. Declared, documented, never called. |
| `ActionVerifier.verify` | `ActionOutcome.swift:89` | 22 test references, zero callers. `ActionPerformer.perform` returns an `ActionResult` and stops there. |
| `MonitorStore.record(action:)` | `MacSlowdown/Sources/MonitorStore.swift:165` | App-side half. `IncidentDetailView.verification` (`IncidentDetailView.swift:28`) defaults to `nil` and nothing supplies it. |
| `PolicyStore.corrections` / `addCorrection` / `removeCorrection` / `overrides(for:)` | `ApplicationPolicy.swift:204, 206, 214, 223` | FR-039 grouping correction is complete, persisted and unreachable. |
| `SwapSignals.swapUsage()` | `SwapSignals.swift:53` | The app calls only `pagingCounters` and `rates`. FR-008's swap *usage* half is unread. `SwapUsage.isInUse` (`:14`) and `.encrypted` (`:9`) follow. |
| `RetentionPolicy.retained` / `.expired` | `PrivacySettings.swift:80, 90` | Neither is called. The retention picker (`SettingsView.swift:494`) writes to `UserDefaults` and no code reads it back — see the inert-control table below. |
| `MetricsHistory.restore()` | `MetricsHistory.swift:189` | Never called. `MonitorStore.swift:614` does call `flushIfNeeded()`, but on a `.memoryOnly` store where it is a no-op. |
| `HistoryPersistence.acrossRestarts(url:)` | `MetricsHistory.swift:67` | `MonitorStore.swift:363` constructs `MetricsHistory()`, taking the `.memoryOnly` default. The persistence path exists, is called, and is inert by construction. |
| `MetricsHistory.removeAll()` / `PolicyStore.removeAll()` | `MetricsHistory.swift:155`, `ApplicationPolicy.swift:245` | "Delete all history" (`SettingsView.swift:526`) calls `StoredData.deleteRecordedEvidence()` instead. Its copy states truthfully that rules are kept and session incidents are in memory, so this is honest — but two erase paths exist and one is dead. |
| `ProcessNaming.nameIsTruncatedCommand` | `ProcessNaming.swift:307` | FR-002. `p_comm` is 16 bytes; the framework can say a displayed name is a truncated command and the app never asks. |
| `DiskSignals.perApplicationUnavailable` | `DiskSignals.swift:92` | FR-009's written statement that per-application disk I/O is unavailable sandboxed. Composed, never shown. |
| `Incident.startProvenance` | `Incident.swift:172` | FR-038. When an incident's start time was reconstructed from retained history rather than observed, the `Conclusion` saying so is never rendered. |
| `StorageTrend.isCalculated` | `StorageHistory.swift:200` | FR-038. Storage trend text is shown (`StorageTrendAnalysis.describe`, `.standingStatement`) without its derived-calculation label. |
| `MemoryStatistics.accountedFor` | `MemorySignals.swift:63` | Convenience total; nothing reads it. |
| `PowerContext.hasBattery` | `ThermalPowerSignals.swift:67` | Convenience; the app branches on `batteryPercentage` directly. |
| `FamilyMembership.isCertain` | `ProcessFamily.swift:28` | Convenience over an enum the app matches directly. |
| `ProcessFamily.spawnedMemberCount` | `ProcessFamily.swift:61` | Never read. |
| `SafetyPolicy.isProtected` | `SafetyPolicy.swift:93` | Convenience; the app goes through `availability(of:for:)`, which is the right seam. |
| `RedactionOptions.isAtLeastAsRedacted` | `RedactionOptions.swift:72` | Redundant sibling of `weakerThanDefaultWarning`, which *is* wired (`Shortcuts.swift:130`). |
| `ProcessIdentityResolver.resolutionCount` / `.cachedCount`; `ProcessIconCache.cachedCount` | `ProcessIdentityResolver.swift:66, 70`; `ProcessNaming.swift:238` | Cache diagnostics with no surface. |
| `AlertSettings.privacySettings` | `MacSlowdown/Sources/AlertSettings.swift:219` | App-side. Referenced by exactly one test (`MacSlowdown/Tests/SettingsSurfaceTests.swift:142`) and no app code. This single property is why both privacy controls below are inert. |

## Deliberately staged — with the evidence

Recorded so nobody re-files these as defects.

| Item | Evidence |
|---|---|
| `OverheadMeasurement`, `OverheadHarness`, `FR030Budget.withinAllBudgets` and siblings | `CLAUDE.md` §"Performance budget — deferred, still measured": the numeric budget "no longer gates work" and the harness runs standalone via `probe/overhead/run.sh`. Not app-facing by design. |
| `HistoryPersistence` / `PrivacySettings.persistAcrossRestarts` | `MacSlowdown/Sources/AlertSettings.swift:215-218` states it is left at the type default and **not** surfaced because "whether incident history survives a restart is an open product decision, and building the switch would settle it by accident." `SettingsView.swift:512-514` repeats it and the UI says "This session only". `CLAUDE.md` §Undecided lists the same question. This is the model case of staging done properly: the decision, the reason and the user-visible truth are all written down. TASK-72 is now open to settle it. |
| `RetentionPolicy` | Staged only by adjacency to the above; nothing said so at the time. TASK-72 covers it. Allowlisted with that reason. |
| `LowStorageDetector.isSustained` | Duplicates `IncidentPolicy.requiredDuration(.lowStorage) = 60 s` (`Incident.swift:77`), which the running detector does apply. Redundant, not a hole — FR-042's "a transient anomaly does not create an incident" is satisfied by the detector. |
| `ProcessAction.isDestructive` | Returns a literal `false`. It is the FR-037 claim that no action changes how a process runs, kept checkable. Nothing calls it because nothing may. |
| `GuidedInvestigation.isWellFormed` / `canContinue` / `hasRawEvidence`; `IncidentSummary.isWellFormed` | Design-by-contract invariants asserted by tests over FR-013/FR-054 output. Not intended as call sites. |

## Inert controls — a setting the user changes that changes nothing

This is the sharpest form of the defect: the interface promises a behaviour change
and none occurs. TASK-70 found `RedactionOptions.hideFilePaths` this way. That one
is now fixed — all three redaction fields are read at
`Metrics/Sources/ExportDocument.swift:431, 435, 442, 447, 453, 459`, both from the
sheet (`ExportReportView.swift:114-116`) and from the App Intent
(`Shortcuts.swift:196-198`).

Two remain, both in the Privacy tab, and both for the same reason: they are
persisted into `AlertSettings`, gathered into `AlertSettings.privacySettings`
(`AlertSettings.swift:219`), and that property has no reader outside a test.

| Control | Written at | Read by |
|---|---|---|
| "Keep incident history for" (7 / 30 / 90 days) | `SettingsView.swift:494`, persisted `AlertSettings.swift:179` | Nothing. `IncidentsView.swift:201` shows a footer derived from `MonitorStore.retainedIncidents`, a **count** cap, so the visible explanation does not even describe the same mechanism as the control. |
| "Record file paths" | `SettingsView.swift:506`, persisted `AlertSettings.swift:175` | Nothing. Paths are resolved and retained regardless. |

By contrast "Keep history across restarts" is deliberately *not* a control
(`SettingsView.swift:512`), and says what the app actually does. That is the
pattern the two above should be brought to, or wired.

## FRs met only by framework tests

For each: can the behaviour occur in the running app, and how that was determined.

| FR | Can it occur? | Chain |
|---|---|---|
| **FR-016** — per-application allow / ignore / expected policies | **Partly. The audit trail cannot.** | Setting a policy works: `SettingsView` → `MonitorStore.policies.setPolicy`, and `AlertSettings.notificationSettings` (`:210`) feeds `expectedApplications` into `NotificationGate`. Suppression therefore happens. But `MonitorStore.swift:575` discards the `.suppress` decision, so no `SuppressedDetection` is ever recorded and the sheet that exists to show them is permanently empty. |
| **FR-029** — retention controls | **No.** | `RetentionPolicy.retained`/`.expired` have no caller anywhere. The picker writes `UserDefaults`; nothing reads it. Locality *is* satisfied and honestly stated (`PrivacySettings.dataHandlingStatement` at `SettingsView.swift:482`). |
| **FR-039** — user correction of process-family attribution | **No.** | No view creates a `GroupingCorrection`; `PolicyStore.addCorrection` has zero callers; `MonitorStore.swift:488` calls `FamilyGrouper.group(snapshot:resolver:)` without `overrides:`. Every layer exists and none of them is joined. (The "mark expected" half of FR-039 does work, via `setPolicy`.) |
| **FR-050** — verify and report the outcome of remediation | **No.** | `ActionPerformer.perform` returns `ActionResult` and stops. `ActionVerifier.verify` has 22 test references and no caller; `MonitorStore.record(action:)` has none; `IncidentDetailView.verification` is always `nil`. Worth weighing before treating as a plain defect: with FR-020–024 deferred, every available action (activate, reveal, open Activity Monitor, copy diagnostics) is observational, so there is arguably nothing whose outcome could be measured. That is a defensible reason to stage it — but it was never written down anywhere, which is exactly the failure mode this audit is about. |
| **FR-008** — swap, compression, paging | **Partly.** | Compression and paging rates are wired (`SwapSignals.pagingCounters`, `.rates`, `DiskRates` shown in 7 places). `SwapSignals.swapUsage()` — swap bytes in use, encrypted flag — has no caller, so the swap half of FR-008 is measured and never surfaced. |
| **FR-009** — aggregate disk throughput | **Yes, with one omission.** | `DiskSignals.counters`/`.rates` are called. The `perApplicationUnavailable` disclosure, which is how the app is supposed to say per-app I/O is blocked sandboxed, is never displayed. |
| **FR-038** — traceable evidence classification | **Partly.** | `Conclusion` is used in 39 places, so most labelling works. Two labels are built and never rendered: `Incident.startProvenance` (start time reconstructed from history) and `StorageTrend.isCalculated` (trend is a derived calculation). |
| **FR-002** — inventory with truncation honesty | **Partly.** | Naming is fully wired (`ProcessNaming.accessibilityLabel`, `unidentified`, `isTruncated` used internally at `ProcessNaming.swift:44`). `nameIsTruncatedCommand` — the per-row question the table would ask — has no caller. |
| **FR-042** — sustained low storage | **Yes.** | `MonitorStore.swift:646` → `LowStorageDetector.isBelowThreshold` → `SystemObservation.lowStorage` → `IncidentDetector`, which applies `requiredDuration(.lowStorage) = 60 s`. TASK-66 fixed the missing wire; the surviving `isSustained` is redundant, not a gap. |
| **FR-028** — redactable export | **Yes.** | All three redaction fields read in `ExportDocument`; both the sheet and the App Intent go through the single builder; `weakerThanDefaultWarning` and `disclosure` reach `Shortcuts.swift:130-131`. TASK-70's finding is closed. |
| **FR-054** — guided investigation | **Yes.** | `IncidentDetailView.swift:97-98` → `InvestigationBuilder.build`. |
| **FR-007** — memory pressure | **Yes, minus the transition log.** | `MonitorStore.swift:436/451/512` starts, stops and reads `pressureMonitor.level`. `transitions` is unread. |
| **FR-040** — versions recorded with each incident | **Yes.** | `MachineContext.appVersion`/`schemaVersion` reach `IncidentEvidence.swift:453` and `ExportDocument.swift:328`. |

## The check that would catch the next one

`probe/seam-reachability.sh`, with `probe/seam-allowlist.txt`.

The discriminator is not "unreferenced by the app" — that flags 32 types, 23 of
them false. It is **declared public, referenced by tests, referenced by no
caller**: no call site in `MacSlowdown/Sources/`, and none in `Metrics/Sources/`
other than the declaration itself, while at least one test does exercise it. That
is the exact signature of all five confirmed instances, and run today it produces
20 hits with no manual triage — including three (`isProtected`, `isCalculated`,
`isDestructive`) this audit had not found by hand. Anything staged goes in the
allowlist **with a written reason**; a bare name is rejected on review, because
undocumented staging and having forgotten look identical six weeks later, and a
line that survives a whole milestone is evidence the code should be deleted rather
than staged again. Run it before finishing any task that adds public framework
surface; it needs no build and takes about 30 seconds, so it can gate a commit
long before there is CI. Its one blind spot is that matching is by name, so a
member two types share (`restore()`, `removeAll()`) is invisible to it — three
findings above came from reading call sites instead. The complement worth adding
later is a small end-to-end test bundle asserting reachability rather than
correctness: drive `MonitorStore` through a synthetic suppressed detection and
assert `policies.suppressedDetections` is non-empty; through a completed action
and assert the incident carries an `ActionVerification`; through a grouping
correction and assert `FamilyGrouper` output changes. Those three assertions
would have failed on the day each gap was introduced.

## Outcome — TASK-80 and TASK-81 (2026-08-09)

Both worked from the tables above. Recorded here so the audit is not read later as
still-open.

**TASK-80, the four measured-but-unshown disclosures — all wired.** Swap usage now
reaches the Now screen's memory card via a new `MonitorStore.swapUsage`, read on the
sampling loop rather than by the view, so every surface quotes one reading.
`DiskSignals.perApplicationUnavailable` replaced *two* separately worded
hand-written paraphrases of the same limitation that were both sitting on the Now
screen. `Incident.startProvenance` is carried on `IncidentTimeline` and rendered by
the existing `ConclusionRow`. `StorageTrend.isCalculated` drives a provenance label
in the same "Measured / Calculated / Estimate" vocabulary the capacity legend
already used.

**TASK-81 — six deleted, one wired, three kept with reasons, one wrong.**

- Deleted, with their assertions rewritten against the seam that remains rather
  than removed: `MemoryStatistics.accountedFor`, `PowerContext.hasBattery`,
  `FamilyMembership.isCertain`, `ProcessFamily.spawnedMemberCount`,
  `SafetyPolicy.isProtected`, `RedactionOptions.isAtLeastAsRedacted`. No test was
  deleted; every one of them was a one-line wrapper over an expression the tests
  can state directly.
- **`ProcessNaming.nameIsTruncatedCommand` was a real gap, not a convenience.**
  `displayName(command:)` marks a cut 16-byte `p_comm` with an ellipsis, and
  `ProcessNaming.accessibilityLabel(command:)` exists precisely because an ellipsis
  is silent to VoiceOver — but neither inventory table used the spoken form. Both
  built their own label from the row. So the FR-002 truncation disclosure was
  visual-only, and FR-034 was unmet for every truncated row in two tables. Both
  row types now carry `nameIsShortened` and both spoken labels say so.
- Kept, in `probe/seam-allowlist.txt` with reasons: `transitions`,
  `resolutionCount`, `cachedCount`.
- **`MetricsHistory.removeAll()` was listed in error.** It has had a caller since
  TASK-72 landed — `MonitorStore.deleteRecordedHistory()` calls it so that "delete
  everything" is true of the retained series and not only of the files. Deleting it
  broke the build immediately. The audit predates that commit; the entry is wrong,
  not stale.

`LowStorageDetector.isSustained` stays allowlisted: `StorageSignals.swift` was out
of scope for the agent that did this work.

After: **5 unexplained**, down from 16, and all five belong to TASK-76–79
(`ActionVerifier`/`verify` for FR-050, `recordSuppression`/`addCorrection`/
`removeCorrection` for FR-016 and FR-039).

One thing this confirms about the method: the blind spot named above cost real
work twice in one pass. `removeAll()` was reported as dead because it is shared by
two types, and `cachedCount` is *still* invisible for the same reason — one of its
two declarations has a genuine caller in `probe/`, which the script does not search
at all. Reading call sites is not optional after running it.
