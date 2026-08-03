---
id: TASK-51
title: 'Incidents list surface (FR-011, FR-012)'
status: Done
assignee: []
created_date: '2026-08-02 18:14'
updated_date: '2026-08-03 05:55'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IncidentsView.swift. Verified against the running sandboxed app with a real incident, not a fixture.

- AC#1 A CPU-saturation incident raised by 10 spinners appeared while open, labelled 'still going'. Open incidents sort above history.
- AC#2 Each row states condition, severity, start time, duration and whether it recovered.
- AC#3 Severity carries a shape (circle / triangle / octagon), a word ('High'), and an accessibility label naming it -- never colour alone.
- AC#4 The empty state says 'MacSlowdown is watching' and distinguishes monitoring-running from monitoring-stopped. 'No incidents' alone could equally mean the app is broken.

Screenshot evidence: 'CPU saturation - Aug 2, 2026 at 10:37 PM - still going - 4 minutes, 4 seconds so far - High'.
<!-- SECTION:NOTES:END -->
