---
id: TASK-66
title: >-
  MonitorStore is blocking three surfaces — and low-storage incidents can never
  open
status: In Progress
assignee: []
created_date: '2026-08-09 03:31'
updated_date: '2026-08-09 05:08'
labels:
  - core
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found independently by three parallel sessions building design screens, each blocked at the same file. `MonitorStore.swift` was deliberately made off-limits to all of them to prevent merge conflicts, which is why none of them fixed it — the orchestration protected the file and made it the bottleneck. It needs one owner and one pass.

## 1. Low-storage incidents cannot open at all (defect, FR-041/FR-042)

`MonitorStore` builds `SystemObservation` **without `lowStorage`**, so it defaults false on every sample. The detector is therefore never given a true value and a low-storage incident can never be raised, no matter how full the disk gets. TASK-21 and TASK-53 delivered the storage surface; nothing surfaces the condition into the incident pipeline.

This is the most severe item here: a requirement with passing tests that cannot fire in the running product.

## 2. No retained history is reachable from the UI

`MonitorStore` holds its `MetricsHistory` in a `private let` with no accessor. Every sparkline in the design (Now's four cards and its contributor rows, the popover's 15-minute trace) is therefore unbuildable. TASK-65.3 omitted all of them rather than accumulate a *second* series in the view — which would have drawn something different from the series FR-005 actually retains, and been a quiet lie.

Exposing read access to the retained series unblocks TASK-65.3 criterion #3, TASK-65.2, and TASK-58.

## 3. Nothing in the app owns a `PolicyStore`

`PolicyStore` exists in `Metrics` and is tested, but `grep PolicyStore MacSlowdown/Sources` returns nothing. No per-application policy can be read or written by the running app, so the design's "Expected workload" chip and "Builds are normal for Xcode" action have no source but invention — TASK-65.3 omitted both for that reason. FR-016 is framework-only today.

## 4. Storage capacity is recorded only while the Storage screen is open

`StorageHistory` (added by TASK-65.12) is driven from the view, so history stops accumulating the moment the user looks away, and a 14-day trend never fills. A single `record(...)` call in the sampling loop makes it continuous. Same shape of problem as the others: the data layer is ready and nothing in the app drives it.

## Why this is one task, not four

All four are edits to the same file, and three of them are wiring an existing, tested `Metrics` capability into the app. Splitting them guarantees conflicts. Whoever takes this should expect the diff to be small and the consequences to be large.

Note `MonitorStore.swift:86-101` carries reasoning about self-cost measurement that should survive untouched.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A low-storage condition observed by the storage signals reaches the incident detector, and an incident opens and closes for it -- verified against a real or induced low-storage state, not only a unit test with a synthetic observation (FR-041, FR-042)
- [x] #2 The retained metrics history is readable by the UI, so a view can draw the same series the framework retains rather than accumulating its own
- [x] #3 The app owns a PolicyStore instance, so per-application policies can be read and written by the running app (FR-016)
- [x] #4 Storage capacity is recorded on the sampling loop rather than by a view, so history accumulates whether or not the Storage screen is open
- [x] #5 No existing behaviour regresses: the full suite passes, and the self-cost measurement reasoning in MonitorStore is preserved
- [x] #6 Each of the three blocked tasks (TASK-65.3 criterion #3, TASK-65.12's incident marker, and the expected-workload chip) is confirmed unblocked or the remaining obstacle is recorded
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Two additions found by TASK-65.4 after this task was written.

**5. `LifecycleTracker` is not wired into `MonitorStore` either.** It exists in `Metrics` and is tested, but nothing drives it from the app, so 'relaunches today' has no source. TASK-65.4 did not invent a zero: its inspector counts replacements *observed while watching* (identity gone, another arrived under the same command, keyed on `(pid, start time)` so a recycled PID reads as a replacement) and says 'Not watched long enough' until the window is real. **That is a stand-in. Replace it with the real tracker once wired**, and check TASK-65.4's inspector when you do. Same shape as items 2-4: tested framework capability, no app-layer owner.

**6. A `PolicyStore` instance already exists on a branch — do not create a second.** TASK-65.4 added `InspectorPolicies` on worktree branch `worktree-agent-ae83f187193f08460` (commit `caa0425`) because it needed `markExpected` and the app had no instance. Item 3 above should adopt or replace that one, not add another alongside it. Two independent policy stores would disagree about what the user marked expected, and the disagreement would be invisible.

Related: `ActionPerformer` deliberately refuses `markExpected`, so that action is handled in the view against the policy store. Keep that separation when wiring.

**7. `diskRates` defaults to `.zero`, so an unreadable disk reads as an idle one.** Found by TASK-65.1. Same class of defect as item 1: unavailable data presented as a plausible number, which FR-002 and FR-010 forbid. Make it optional or carry an explicit unavailable case so consumers can tell '0 MB/s' from 'cannot read'. The 65.1 popover works around it with a one-shot `DiskSignals.counters() != nil` on appear, duplicating a read the store already performs; that workaround should become unnecessary.

**8. `monitoringStartedAt` does not exist.** TASK-65.1 needs 'Watching since 8:02 AM' for its popover and uses `NSRunningApplication.current.launchDate` as a proxy. That is a real measurement and correct today, because `AppDelegate` starts the sampler at launch -- but it breaks silently if `stop()`/`start()` are ever called. A real start timestamp on the store fixes it properly.

**9. Startup-volume capacity is read independently by two surfaces.** The popover and `StorageView` both call `StorageSignals.snapshot()` on their own, so they can disagree about free space at the same moment. Exposing it once on the store removes the possibility.

Sent to the running TASK-66 session; recorded here in case it had already finished.

Done on worktree branch `worktree-agent-a0832a67c5735f763`, commit `90f1b5e`. Branched stale (pre-merge); merged `main` first, so the baseline was the eight merged branches.

**1. Low storage (defect).** `MonitorStore` now reads volume capacity on the sampling loop and passes `lowStorage:` into `SystemObservation`. Read every 30 s (`MonitorStore.storageCheckInterval`), not every sample — capacity reads touch the filesystem, and 30 s is well inside the 60 s the condition must be sustained for. Scoped to the **startup volume**: it is the one whose exhaustion degrades the machine, and raising an incident for a full external disk is a claim we cannot support. `MonitorStore.isLowStorage(startupVolume:detector:)` is pure and tested; an unreadable volume returns false, which is 'no measurement', not 'plenty of room'. There was **no test anywhere** driving `lowStorage` through `IncidentDetector` — there is one now (opens after 60 s, closes after hysteresis).

**2. Retained history.** Added `retainedSamples`, `retainedHistorySpan`, `retainedSamples(around:margin:)`. Read access only — `MetricsHistory` is a reference type with `record`/`removeAll`, so handing the object to a view would let the UI write to the evidence. `IncidentsView` now passes `retainedSamples(around:)` into `IncidentDetailView`, which had been carrying a `samples` parameter no caller could fill (one line each; both stale comments corrected).

**3. PolicyStore — ADOPTED, not replaced.** `InspectorPolicies` (TASK-65.4) moved onto the store as `MonitorStore.policies`, backed by `MonitorStore.defaultPolicies` at the same `policies.json` path, so existing user policies carry over. The enum is gone; `FamilyInspectorView` reads `store.policies`. Injectable for tests. One store, tested.

**4. Storage on the loop.** `storage.refresh()` from the sampling loop, which reads the volumes and appends to `StorageHistory`. The screen shares the same `StorageScreenModel`, so opening it shows history already gathered rather than starting a series.

**5. LifecycleTracker.** Wired in; `lifecycleEvents` bounded to the tracker's 900 s window. The inspector's stand-in is replaced by `store.relaunchCount(forCommands:)`. **Semantics corrected on the way**: a relaunch is `min(exits, launches)` per command, not an exit count — an app the user quit and did not reopen exited once and relaunched never. `monitoringStartedAt` / `hasObservedLongEnough()` replace the per-family 'not watched long enough' gate, and the tracker sees the whole process table rather than only the top-40 families.

**6.** `MonitorStore`'s self-cost reasoning is untouched.

**Items 7-9 (added after I started) are all done.** 7: `diskRates` is `DiskRates?` now; `Presentation.diskThroughput` and `NowPresentation.diskWrite/diskRead` say 'Not available' for nil. The 65.1 popover's `DiskSignals.counters() != nil` workaround can go. 8: `monitoringStartedAt` is set in `start()`, with `observedDuration` and `hasObservedLongEnough(minimum:)` alongside it. 9: `MonitorStore.startupVolume` exposes the capacity the loop last read, so no surface needs its own `StorageSignals.snapshot()`.

Not done from that list: the 24-hour incident count that survives restart. It depends on the persistence/retention decision that is still with the user, and an agent must not decide it. The store's shape would accommodate it — `recentIncidents` is already a bounded array fed by one `case .closed` site, so restoring into it at init and appending to a file there is the whole change once the retention policy is chosen.

**Tests:** 17 new in `MacSlowdown/Tests/MonitorStoreWiringTests.swift`. Full suite is **537 tests**. One run: 536 passing, the only failure a since-fixed test of my own. Final run: 535 passing, with `realSlowdownProducesOneIncident` and `cadenceAdaptsToRealLoad` failing — the two documented CPU-load flakes, which passed on the earlier run, live in `MetricsTests`, and cannot be implicated by this change because it edits no file under `Metrics/Sources`.

**Criterion #1 left UNCHECKED, deliberately.** Verified only with synthetic observations and a pure decision function. Confirming it against a real or induced low-storage state means taking the startup volume under 5 GB free and watching an incident open and close — that needs a person at the machine, and this session was instructed not to use the screen.

**Blocked work:** TASK-65.3 criterion #3 (sparklines), TASK-65.2 and TASK-58 are unblocked by `retainedSamples`. TASK-65.12's incident marker is unblocked — `StorageView` already filters `store.recentIncidents` for `.lowStorage`, and those incidents can now actually exist. The **expected-workload chip is only half unblocked**: the store exists, but `InventoryRow` carries a bundle path and a name while `PolicyStore.policy(for:displayName:)` matches on a `ResolvedIdentity`, so the chip needs its classification passed in. Recorded in the comment on `NowPresentation.chips`; deliberately not invented here.

**Left behind, deliberately:** `FamilyHistory` keeps its own replacement bookkeeping (`relaunches`, `replacements`, `hasWatchedLongEnough`) and its tests. Nothing user-facing reads it now and a comment on the property says so, but removing it changes `FamilyHistory.record`'s signature and means editing `ProcessInventoryView`, which another session owns. Small follow-up.

Also not done: the TASK-65.9/65.10 session asked for `detector` and `notificationGate` to become settable so `AlertSettings` could drive them. `AlertSettings.swift` is on an unmerged branch and does not exist in this worktree, so referencing it would not compile. It has to happen after that branch merges.

**Merge note from the TASK-65.9/65.10 session.** Their branch is rebased onto main at `f1d4ff8`, where `InspectorPolicies.store` still exists, and their Apps tab plus `AlertSettings.notificationSettings` read it. When this branch lands the reconciliation is a rename at nine call sites, no behaviour change: four in `SettingsView.swift`, one in `AlertSettings.swift`, four in `SettingsSurfaceTests.swift`, all `InspectorPolicies.store` -> `MonitorStore.shared.policies`. Same file on disk (`policies.json`), so no migration and no user data at risk — but the rename must happen in the same commit as the merge, or the build breaks on a symbol this branch deleted.

**Open question this raised, for whoever makes the alert thresholds settable.** Assigning a new `IncidentPolicy` mid-flight reinterprets any in-progress breach against the new threshold. That is the right behaviour — the alternative is a user tightening sensitivity and then waiting out a window they can no longer see — and the accumulated `breachStart` should be kept rather than reset, since resetting would silently postpone an incident that had already been building.

There is a gap underneath that, though, which TASK-66 has incidentally made fixable. `breachStart` is only ever set while `breaches()` is true, so **tightening** a threshold (lowering it, so more conditions breach) finds `breachStart` nil for a condition that was below the old line, and the clock starts from the next observation — delaying the incident by the whole sustained duration for a condition that may have been present the entire time. The retained series (`MonitorStore.retainedSamples`) now makes it possible to evaluate the sustained duration backwards over what was actually measured rather than only forwards from the moment the setting changed. Not in scope here; recorded so it is a decision rather than an accident.
<!-- SECTION:NOTES:END -->
