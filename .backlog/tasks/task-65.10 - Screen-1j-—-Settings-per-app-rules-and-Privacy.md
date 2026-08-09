---
id: TASK-65.10
title: 'Screen 1j — Settings: per-app rules and Privacy'
status: To Do
assignee: []
created_date: '2026-08-09 02:24'
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
- [ ] #1 Per-application rules are manageable from Settings, with the rule vocabulary stated in plain language (FR-016)
- [ ] #2 The screen states that rules change what is flagged and never what is recorded, and suppressed incidents remain visible in history marked as not alerted
- [ ] #3 A route exists to review incidents that were suppressed by a rule
- [ ] #4 Privacy states the local-only guarantee, retention period, and the storage currently used (FR-029)
- [ ] #5 Path recording is off by default and presented as an explicit opt-in
- [ ] #6 Whether history persists across restarts, and the default retention, are settled in requirements.md before implementation rather than inherited from the mock
- [ ] #7 Verified on screen against design/screens/1j.png
<!-- AC:END -->
