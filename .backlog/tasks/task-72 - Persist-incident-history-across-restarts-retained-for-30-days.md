---
id: TASK-72
title: 'Persist incident history across restarts, retained for 30 days'
status: To Do
assignee: []
created_date: '2026-08-09 18:23'
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
- [ ] #2 Retention is enforced, not merely configured: an incident older than the retention period is removed, and the enforcement runs without the user opening any particular screen
- [ ] #3 The retention period is user-adjustable and whatever the interface states is kept is what is actually kept (FR-029)
- [ ] #4 Recorded attribution and its confidence survive persistence unchanged, and are never recomputed from live state on load (FR-013, FR-038)
- [ ] #5 The stored form carries a schema version so a later change can migrate rather than discard
- [ ] #6 No copy claims the store is encrypted; it states that the container is not readable by other apps
- [ ] #7 Delete-all removes the history and reports how much it removed, leaving user policies intact
- [ ] #8 requirements.md records the decision and CLAUDE.md's 'Undecided' entry for persistence and retention is removed
<!-- AC:END -->
