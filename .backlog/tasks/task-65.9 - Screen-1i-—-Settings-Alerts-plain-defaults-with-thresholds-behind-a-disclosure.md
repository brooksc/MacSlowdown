---
id: TASK-65.9
title: >-
  Screen 1i — Settings: Alerts, plain defaults with thresholds behind a
  disclosure
status: In Progress
assignee: []
created_date: '2026-08-09 02:23'
updated_date: '2026-08-09 05:12'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1i.png`. Current state: `screenshots/05-settings.png`. Existing implementation: a single Form with three rows (TASK-25, TASK-34).

**What the design specifies**

Five tabs: General / Alerts / Apps / Privacy / Advanced. The Alerts tab:

- "Tell me about slowdowns" — "One notification per slowdown, unless it gets noticeably worse."
- "How sensitive should I be?" — a Relaxed / Balanced / Sensitive segmented control, with the current setting spelled out in words underneath: "Balanced: alert after 3 minutes of sustained trouble." The plain-language restatement is the point; the user never has to decode the setting.
- "Stay quiet during Focus" — "Slowdowns are still recorded and waiting when you come back."
- "Don't interrupt during calls or playback" — "Holds notifications while an app is playing audio or using the microphone." This is the FR-019 audio signal, which CLAUDE.md confirms is available sandboxed via `kAudioHardwarePropertyProcessObjectList`, used for a genuinely useful purpose rather than as a metric.
- **"Exact thresholds"** behind a disclosure, labelled "Overrides 'Balanced' for the Everyday profile": Total CPU above 85% of 10 cores, for at least 3 min 0 s; Memory pressure Warning or above for 90 s.
- "Also compare to — What's normal for this Mac", "Learned locally over 14 days. Incidents will say whether they crossed the fixed number, the learned normal, or both." with "Reset what it learned". That is FR-053 / TASK-37.
- Footer tying the whole tab to the active profile: "These settings belong to the **Everyday** profile. Switch profiles in the sidebar…"

**Gap against what we render today**

Our Settings is one untabbed pane with "Show in menu bar", "Start at login" and a Notifications status line. Nothing about sensitivity, thresholds, Focus, audio suppression, or learned baselines exists. See also TASK-64 for the layout defect in the current pane.

The two-layer structure — a plain choice up top, exact numbers behind a disclosure — is what keeps FR-006's duration thresholds configurable without putting a control panel in front of an ordinary user.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings is organised into tabs rather than a single pane
- [x] #2 Alert sensitivity is chosen in plain language, with the resulting behaviour restated in words
- [x] #3 Exact duration and level thresholds are reachable behind a disclosure and stated in the same units the incident detail later reports
- [ ] #4 Notifications can be held during Focus and during audio or microphone use, without suppressing recording
- [ ] #5 Where a learned baseline is used, incidents state whether a fixed threshold, the learned normal, or both were crossed (FR-053)
- [ ] #6 The tab makes clear which profile the settings belong to (FR-025, FR-026)
- [ ] #7 Verified on screen against design/screens/1i.png
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch `agent-ab5b19c490202e7c9`, commit 5cc1a3b.

**What was built.** `SettingsView` moved out of `MacSlowdownApp.swift` into `MacSlowdown/Sources/SettingsView.swift` and became a `TabView`: General / Alerts / Apps / Privacy. **Four tabs, not the design's five** — Advanced has no content the app can honestly fill, and an empty tab claims more than a missing one does.

Alerts carries: "Tell me about slowdowns" (one notification per slowdown unless it worsens — which is what `NotificationGate` actually does); a Relaxed / Balanced / Sensitive segmented picker with the behaviour restated underneath; a Focus statement; "Don't interrupt during calls or playback"; and an "Exact thresholds" `DisclosureGroup`.

`AlertSensitivity` (new, `AlertSettings.swift`) maps each word to a complete `IncidentPolicy`. The restatement sentence is *derived* from that policy via the same `DateComponentsFormatter.incidentDuration` the incident summary uses, so the words and the numbers cannot drift, and `.balanced` is literally `IncidentPolicy.default` rather than a second copy of the same figures. Editing any slider sets `usesCustomThresholds`, so the plain choice and the numbers never silently disagree about which is in force; a button restores the word's figures.

**Controls deliberately not built as controls (data honesty):**
- **Focus** is rendered as a statement, not a toggle. `MonitorStore` already documents that no public API reports the current Focus to a sandboxed app, so `context.focusActive` is permanently false and our gate never makes this decision — macOS holds the banner. A switch would take credit for someone else's behaviour.
- **Memory pressure level** is fixed text ("Warning or above"). `SystemObservation.breaches` hardcodes warning-or-above and reads no other value, so a picker would silently do nothing. The *duration* is configurable and is a slider.
- **Learned baselines (FR-053)** and **profiles (FR-025/026)** do not exist (TASK-37, TASK-38). Nothing implying them is rendered; the tab footer states plainly that incidents are judged against fixed figures only and that separate profiles do not exist yet.

**Backing gap, surfaced rather than hidden.** `AlertSettings` persists to `UserDefaults` and exposes `incidentPolicy`, `notificationSettings` and `privacySettings` ready to consume — but nothing consumes them. `MonitorStore` owns the `IncidentDetector` and `NotificationGate` as `private let`s built from `.default`, and it is owned by TASK-66's agent. Rather than ship toggles that silently do nothing, the store carries `isAppliedToMonitoring` (false until a consumer calls `markAppliedToMonitoring()`) and the Alerts tab shows a visible "Saved, but not yet in effect" notice while it is false. The notice disappears on its own, with no copy change, once the loop reads the settings. TASK-66's agent has been asked for the two-line wiring; if it does not land, this is follow-up work.

**Criteria.** #1, #2, #3 met. #4 **not met**: audio deferral is saved but not yet applied (above), and Focus is macOS's decision rather than ours — recording is unaffected either way. #5 not met: FR-053 does not exist and nothing pretends it does. #6 not met: profiles do not exist; the tab says so instead of naming a profile it does not have. #7 not verified — the screen was off limits for this run.

**Tests.** `MacSlowdown/Tests/SettingsSurfaceTests.swift`, 24 new tests. Full suite 410 passing; the one failure was `EndToEndIncidentTests.realSlowdownProducesOneIncident`, which passes in isolation (23.9 s) and is the known load-synthesising flake under concurrent builds.

**Rebase reconciliation.** This branch was cut from a6046ba, before eight branches merged into `main`. Rebased onto `main` at f1d4ff8; the rebase itself was clean (one commit, no conflicts) because all of my work is in new files plus `LoginItem.swift` and the block of `MacSlowdownApp.swift` I removed. Two things had to be reconciled by hand afterwards:

1. **TASK-11.1's scene wiring survived intact.** `MacSlowdownApp.body` now registers `MainWindowOpener.action` and returns a `@SceneBuilder private var scenes`. My change only deletes the old `SettingsView` struct from the bottom of that file (it now lives in `SettingsView.swift`) and drops the then-unused `import ServiceManagement`. The `Settings { SettingsView(showMenuBarItem: $showMenuBarItem) }` call site inside `scenes` is unchanged, and the `MainWindowOpener` registration and `scenes` builder are verified present after the rebase.
2. **`InspectorPolicies` already existed** in the merged state — as a `@MainActor enum` with a `static let store: PolicyStore`, in `FamilyInspectorView.swift`. I had created a same-named global on the pre-merge base; that file (`SharedPolicies.swift`) is **deleted** and every call site now goes through `InspectorPolicies.store`. There is one policy store in the app. `StoredData.policiesURL` was dropped with it, leaving `StoredData.rulesFileName` so "delete all history" still knows which file is configuration rather than evidence.

Re-verified after the rebase: build succeeds, 561 tests pass, and `MonitorStore`'s `detector` and `notificationGate` are still `private let`s built from `.default` — so the "saved, but not yet in effect" notice remains accurate. TASK-66's session confirmed it did not take the wiring, because `AlertSettings.swift` does not exist in its worktree.

**Second rebase (main moved again).** While I was writing these notes `main` advanced to fd0f5b4, the TASK-66 merge, which **deletes `InspectorPolicies` outright** and replaces it with `MonitorStore.shared.policies` (same `policies.json`, same instance). Rebased again onto fd0f5b4, clean, and applied the rename in the same commit — TASK-66's session flagged that a half-merge would not build, and this branch is now on the far side of it. Final commit **20d2a8d**, six files: `AlertSettings.swift`, `SettingsView.swift`, `StoredData.swift` (new), `LoginItem.swift`, `MacSlowdownApp.swift` (deletion of the old `SettingsView` only), `SettingsSurfaceTests.swift` (new).

**Test numbers, and a defect in `main` that is not mine.** `MacSlowdownTests` does not compile at fd0f5b4: `MacSlowdown/Tests/IncidentsViewRenderTests.swift:144` calls `IncidentRow(incident:)`, but `IncidentsView.swift:218` now declares `let entry: IncidentHistory.Entry`. That is between TASK-65.6 (which changed the row) and TASK-51.1 (which wrote the render test); my commit touches neither file, and the fix needs an `IncidentHistory.Entry` constructed in the test, so it belongs to those owners rather than to me.

To measure my own work I moved those two files (`IncidentsViewRenderTests.swift`, `IncidentHistoryTests.swift`) aside temporarily, ran the suite, and put them back — nothing committed. With them excluded: **576 tests, 0 failures, exit 0**, including the usually-flaky `EndToEndIncidentTests.realSlowdownProducesOneIncident`. With them present the suite cannot build at all, on this branch or on `main`.
<!-- SECTION:NOTES:END -->
