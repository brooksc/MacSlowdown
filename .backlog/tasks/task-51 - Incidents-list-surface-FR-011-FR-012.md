---
id: TASK-51
title: 'Incidents list surface (FR-011, FR-012)'
status: In Progress
assignee: []
created_date: '2026-08-02 18:14'
updated_date: '2026-08-02 18:15'
labels:
  - ui
  - phase1-catchup
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 1 of m-3: surface what m-2 built. The detector, lifecycle and history all work and are tested, but nothing in the app shows an incident, so none of it is usable or reviewable.

Design reference: screen 1f. Shows open and recent incidents with condition, severity, duration and outcome.

MonitorStore already exposes openIncident and recentIncidents.</description>
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An open incident appears while it is open and moves to history when it closes
- [ ] #2 Each row states condition, severity, duration and whether it recovered
- [ ] #3 Severity is never conveyed by colour alone
- [ ] #4 An empty list says monitoring is running rather than implying nothing is wrong
<!-- AC:END -->
