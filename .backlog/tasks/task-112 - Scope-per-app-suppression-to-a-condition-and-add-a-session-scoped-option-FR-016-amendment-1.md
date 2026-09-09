---
id: TASK-112
title: >-
  Scope per-app suppression to a condition, and add a session-scoped option
  (FR-016 amendment 1)
status: In Progress
assignee: []
created_date: '2026-09-06 16:53'
updated_date: '2026-09-09 17:40'
labels:
  - core
  - ui
milestone: m-3
dependencies:
  - TASK-111
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
"This application's heavy load is expected" is not "this application can never cause a problem", and the product currently treats the first as the second. An app marked expected for CPU load must still be able to appear in a memory-pressure finding.

**Two problems with the current shape.**

1. **Suppression is application-wide.** Learning that compiles are normal should not silently disable a warning about running out of memory. An application is not a specific enough description of the nuisance.
2. **Keying on "the leading measurable contributor" is unstable.** That ranking is incomplete by construction (FR-055) — a large share of activity is unattributable — so a small ranking change could decide whether otherwise identical conditions announce. The rule must name what it suppresses rather than inferring it.

**What to build.** A rule reads as "mute CPU-load alerts from Xcode": one application, one condition type, visible and reversible from a single place. Plus a **session-scoped** option — "quiet for this work session" — which covers the common case of someone doing something heavy *now* rather than always, and expires without them having to remember it.

**Placement matters as much as scope.** The rule has to be offerable at the moment of annoyance, not only from Settings. Nobody opens a preferences window to fix a notification; they turn notifications off. That part of the earlier analysis (TASK-108) stands.

Note this is partly superseded in urgency by TASK-111: if sustained CPU no longer announces by default, the most common false-positive class disappears and this becomes less pressing. Do TASK-111 first and re-judge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A rule names the condition it suppresses, and suppressing one condition never suppresses another
- [x] #2 A session-scoped rule exists and expires without user action
- [ ] #3 Every rule is visible and reversible from one place
- [ ] #4 A rule can be created from the notification, not only from Settings
- [x] #5 Suppression does not depend on which contributor happened to rank first
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Built 2026-09-09 (worktree branch, not merged).** 1121 tests passing; the only failure is `EndToEndIncidentTests.realSlowdownProducesOneIncident`, which recorded its own "baseline CPU is too high" guard — several agents were building concurrently. Re-run alone on a quiet machine.

**The model.** `ApplicationPolicy` gains `conditions: Set<IncidentCondition>` and `NotificationSettings.expectedApplications` is replaced by `rules: [SuppressionRule]` — one application, one condition. A stored rule written before the field existed is migrated on decode by what it *said*: `.expected` ("heavy load is expected") was always the CPU claim and becomes CPU alone; `.ignored` ("never alert me") was deliberately unconditional and keeps every condition. Defaulting the field would have preserved the exact defect the amendment removes.

**Criterion 5.** `NotificationGate.decide` takes `contributors: [String]` instead of `leadingContributor`, and a rule matches by *membership*, not rank. `MonitorStore.announce` still takes `leadingContributor` because the notification text legitimately names the largest measurable contributor — that is a measurement; it is just no longer what a rule is keyed on. A test asserts two orderings of the same contributors decide identically.

**Session scope.** `SessionQuiet` (new, `MacSlowdown/Sources/SessionQuiet.swift`) holds `startedAt` in memory and nowhere else, so it ends at logout/restart with nothing to remember. `NotificationSettings.sessionQuiet` carries it into the gate on each sample. A test asserts a freshly constructed instance — what a relaunch produces — is inactive.

**Which conditions interrupt** is now a three-state fact: `AlertSettings.conditionOverrides` is a dictionary, so a condition nobody has decided about still follows `announcesByDefault`. A "these interrupt" set would have frozen today's defaults into any installation whose owner opened Settings once.

**Criterion 4 is NOT done.** The sheet (`SuppressionOffer` + `SuppressionOfferView`, design 5f's three sentences) is built and reachable from Settings ▸ Rules for whatever is under way, but the entry points at the moment of annoyance — the notification action, the condition in the overview, the incident detail — are in files owned by other agents this session (`MainWindowView`, `NowPresentation`, `MenuBarContentView`, `NotificationDelivery`'s categories). Wiring those is the remaining work.

**Criterion 3 is left unchecked deliberately.** Everything is in one place in the code — the Rules tab lists the session rule, the per-application rules, and the conditions silenced everywhere — but nobody has looked at the screen. TASK-65.24 already carries Settings as never-seen.

Also done here: the Apps tab is renamed **Rules**; adding a rule is application-then-condition in one menu and merges rather than replaces; `SuppressedDetection` records the condition so the audit trail can say the memory finding would still have reached you.
<!-- SECTION:NOTES:END -->
