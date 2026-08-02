---
id: TASK-3
title: 'Spike: application-family identity under App Sandbox (FR-003)'
status: To Do
assignee: []
created_date: '2026-08-02 01:05'
labels:
  - m1-core-monitor
  - spike
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Last item that could force an architecture rewrite. FR-003 is Phase 1 scope and marked "Review required".

Questions:
1. Can we obtain bundle ID and team ID for an arbitrary PID while sandboxed? Candidates: SecCodeCreateWithPID, SecCodeCopyGuestWithAttributes(kSecGuestAttributePid) + SecCodeCopySigningInformation.
2. If not, does path-walking work? proc_pidpath succeeds for 1037/1058 pids INCLUDING other-uid, so walking up to the .app bundle may be viable.
3. Do helper processes group to their parent app? Helpers are often re-parented to launchd (spec open question).

If stable signed identity is unavailable, grouping degrades to path heuristics, which changes the §6 data model and FR-016 policy identity and FR-039 corrections.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Documented whether signed bundle/team identity is reachable sandboxed for arbitrary PIDs
- [ ] #2 Browser/Electron helper fixtures verified to aggregate to their parent app (FR-003 acceptance criteria)
- [ ] #3 Chosen identity scheme survives app update and PID reuse
- [ ] #4 Findings appended to probe/FINDINGS.md
<!-- AC:END -->
