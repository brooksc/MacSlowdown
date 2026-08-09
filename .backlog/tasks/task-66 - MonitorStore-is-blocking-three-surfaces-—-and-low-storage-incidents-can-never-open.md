---
id: TASK-66
title: >-
  MonitorStore is blocking three surfaces — and low-storage incidents can never
  open
status: In Progress
assignee: []
created_date: '2026-08-09 03:31'
updated_date: '2026-08-09 04:43'
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
- [ ] #2 The retained metrics history is readable by the UI, so a view can draw the same series the framework retains rather than accumulating its own
- [ ] #3 The app owns a PolicyStore instance, so per-application policies can be read and written by the running app (FR-016)
- [ ] #4 Storage capacity is recorded on the sampling loop rather than by a view, so history accumulates whether or not the Storage screen is open
- [ ] #5 No existing behaviour regresses: the full suite passes, and the self-cost measurement reasoning in MonitorStore is preserved
- [ ] #6 Each of the three blocked tasks (TASK-65.3 criterion #3, TASK-65.12's incident marker, and the expected-workload chip) is confirmed unblocked or the remaining obstacle is recorded
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Two additions found by TASK-65.4 after this task was written.

**5. `LifecycleTracker` is not wired into `MonitorStore` either.** It exists in `Metrics` and is tested, but nothing drives it from the app, so 'relaunches today' has no source. TASK-65.4 did not invent a zero: its inspector counts replacements *observed while watching* (identity gone, another arrived under the same command, keyed on `(pid, start time)` so a recycled PID reads as a replacement) and says 'Not watched long enough' until the window is real. **That is a stand-in. Replace it with the real tracker once wired**, and check TASK-65.4's inspector when you do. Same shape as items 2-4: tested framework capability, no app-layer owner.

**6. A `PolicyStore` instance already exists on a branch — do not create a second.** TASK-65.4 added `InspectorPolicies` on worktree branch `worktree-agent-ae83f187193f08460` (commit `caa0425`) because it needed `markExpected` and the app had no instance. Item 3 above should adopt or replace that one, not add another alongside it. Two independent policy stores would disagree about what the user marked expected, and the disagreement would be invisible.

Related: `ActionPerformer` deliberately refuses `markExpected`, so that action is handled in the view against the policy store. Keep that separation when wiring.
<!-- SECTION:NOTES:END -->
