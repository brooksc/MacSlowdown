---
id: TASK-65.10
title: 'Screen 1j — Settings: per-app rules and Privacy'
status: In Progress
assignee: []
created_date: '2026-08-09 02:24'
updated_date: '2026-08-09 05:07'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1j.png`. Existing implementation: `ApplicationPolicy` model (TASK-32) and retention controls (TASK-34) exist in the framework; neither has a settings surface.

**Apps tab**

"Rules you've set. These change what gets flagged — **they never change what's recorded**." A list of app rules with icon, name and a rule picker:
- Xcode — "Heavy CPU is expected"
- HandBrake — "Never alert me"
- Google Chrome — "Watch memory closely"

Each row removable, with "Add an app…" below. Footer: "Suppressed slowdowns still appear in Incidents, marked 'not alerted'." plus a link "Review the 4 hidden this week". That link matters — a suppression rule that hides its own effects is how monitoring tools quietly stop working.

**Privacy tab**

- "Nothing has left this Mac — No account, no server, no analytics. The only way data leaves is if you export a report and send it yourself."
- "Keep incident history for — 30 days", with "Currently using 41 MB" shown beside it so retention has a visible cost.
- "Record file paths — Helps identify which copy of an app was running. **Off by default.**"
- "Keep history across restarts — Stored encrypted in the app's own container."
- "See exactly what's stored…" and "Delete all history…"

**Note on an open question**

CLAUDE.md lists "whether incidents persist across restarts, and default retention" as undecided and not inferable from the repo. This screen answers both: persistence is a user-facing toggle defaulting to on with encryption, retention defaults to 30 days. Treat that as a design proposal to confirm, not a decision already taken — the answer belongs in requirements.md before it is built.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Per-application rules are manageable from Settings, with the rule vocabulary stated in plain language (FR-016)
- [x] #2 The screen states that rules change what is flagged and never what is recorded, and suppressed incidents remain visible in history marked as not alerted
- [x] #3 A route exists to review incidents that were suppressed by a rule
- [x] #4 Privacy states the local-only guarantee, retention period, and the storage currently used (FR-029)
- [x] #5 Path recording is off by default and presented as an explicit opt-in
- [ ] #6 Whether history persists across restarts, and the default retention, are settled in requirements.md before implementation rather than inherited from the mock
- [ ] #7 Verified on screen against design/screens/1j.png
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch `agent-ab5b19c490202e7c9`, commit fe52c60 (rebased onto `main` at f1d4ff8).

**Apps tab.** Rules are managed against the existing single `InspectorPolicies.store` (`FamilyInspectorView.swift`) — no second policy store. Each row is icon, name, a `Picker` over `PolicyClassification` and a remove button; the vocabulary is the framework's own plain-language labels ("Heavy load is expected", "Never alert me", "Watch closely"), not a severity enum in disguise. The header states verbatim that rules "change what gets flagged — they never change what's recorded".

"Add an app…" lists **currently running applications** (`NSWorkspace.runningApplications`, `.regular` only) rather than opening a file panel: the app holds only `com.apple.security.app-sandbox`, and asking for a user-selected-file entitlement to populate a picker is exactly the scope creep App Review punishes.

The footer states that suppressed slowdowns still appear in Incidents marked "not alerted", with "Review what these rules hid…" opening the `PolicyStore.suppressedDetections` audit trail. **That list is currently empty and says so honestly** — nothing records suppressions yet, because `MonitorStore`'s `NotificationGate` is built from `.default` and never consults the policy store. The empty state distinguishes "nothing was hidden" from "we did not look". Wiring is the same gap described in TASK-65.9's notes.

**Privacy tab.** The local-only statement is `PrivacySettings.dataHandlingStatement`, not re-worded here, so one sentence governs. Retention is a `Picker` over `PrivacySettings.Retention` with the **measured** bytes in the app's Application Support directory printed beside it — `StoredData.bytesOnDisk()` walks the container; an unreadable directory prints "unknown", never a guess. "Record file paths" is off by default and captioned as an opt-in. "See exactly what's stored…" renders `PrivacySettings.storedCategories`. "Delete all history…" removes files in our container **excluding `policies.json`** — the user's rules are decisions, not evidence — and reports how many files were actually removed rather than assuming the call did something.

**Criterion #6 is deliberately left unchecked, and no decision was taken.** `requirements.md` was not touched. What the app does *today* was surfaced as-is: `MonitorStore` constructs `MetricsHistory()` with `HistoryPersistence.memoryOnly`, so nothing survives a quit. "Keep history across restarts" is therefore rendered as a **statement, not a switch**: "This session only — history is held in memory and discarded when MacSlowdown quits. Whether to keep it, and how, has not been decided." `AlertSettings.privacySettings` passes `PrivacySettings.default.persistAcrossRestarts` straight through rather than exposing it, so no code path here can settle the question by accident.

**Criteria.** #1–#5 met. #6 **left unchecked by instruction** — the decision is the user's. #7 not verified: the screen was off limits for this run.

**Tests.** `MacSlowdown/Tests/SettingsSurfaceTests.swift` — rule vocabulary, the suppression audit trail carrying "not alerted", one-shared-store, privacy defaults (paths off, retention taken from the framework rather than a second opinion), and storage usage being a real size or an admission. Full suite 561 passing after the rebase; the one failure was the known load-synthesising `EndToEndIncidentTests.realSlowdownProducesOneIncident`, which passes in isolation on an unloaded machine (23.8 s).

**Recommendation on the blocked decision (a recommendation, not an implementation).**

1. **Persist across restarts: yes, and make it the default.** A monitor whose evidence dies with the process cannot answer "what was happening at 3am", which is most of why FR-011 and FR-043 exist. `HistoryPersistence.acrossRestarts` already exists, is already sized against the FR-030 disk budget (5-minute flush, ~3.6 MB/hour against the 10 MB allowance) and is currently unused — the work is a constructor argument, not a feature.
2. **Do not promise encryption in the copy.** The design's "stored encrypted in the app's own container" is not free: FileVault is the user's setting rather than ours, and `NSFileProtection` on macOS is not the guarantee people read it as. Either implement real encryption and say what protects the key, or write "stored in MacSlowdown's own container, which no other app can read" — true under the sandbox, and the property that actually matters. Claiming encryption we do not perform is the same class of error as fabricating a measurement.
3. **Retention default: 30 days**, matching `PrivacySettings.default`, with 7/30/90 offered. Thirty days spans a monthly billing, backup and update cycle, which is the period over which "it does this every month" becomes visible. This changes nothing in code; it just stops being an accident.
4. **Enforce retention on write, not on read.** `RetentionPolicy.expired` exists but nothing calls it. A retention promise the app does not act on is worse than no promise.

If the user accepts, the spec change is one sentence in FR-029 and one in FR-005, after which the statement row in Privacy becomes a real toggle and criterion #6 can be checked.

**Merge note.** TASK-66's branch removes `InspectorPolicies` and replaces it with `MonitorStore.shared.policies`, backed by the same `policies.json`. This branch is rebased on `main` (f1d4ff8), where `InspectorPolicies.store` is still the one instance, so it uses that. When TASK-66 lands, the Apps tab and `AlertSettings.notificationSettings` need `InspectorPolicies.store` → `MonitorStore.shared.policies` — four call sites in `SettingsView.swift`, one in `AlertSettings.swift`, four in `SettingsSurfaceTests.swift`. No behaviour change; it is the same store.
<!-- SECTION:NOTES:END -->
