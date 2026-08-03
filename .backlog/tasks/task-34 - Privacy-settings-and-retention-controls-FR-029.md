---
id: TASK-34
title: Privacy settings and retention controls (FR-029)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:26'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fresh install sends no process inventory
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PrivacySettings.swift: PrivacySettings, Retention, RetentionPolicy.

- AC#1 A fresh install sends no process inventory, and cannot: the app contains no networking code at all. dataHandlingStatement says so as checkable fact rather than as a promise -- 'no account, no server, no analytics' -- and names the single way data can leave (a report you export and send yourself).
- AC#2 Retention is configurable (7/30/90 days) and RetentionPolicy partitions incidents into retained and expired, with a test asserting the partition is complete and disjoint so nothing is silently dropped or double-counted.
- AC#3 Privacy settings are accessible and enumerate what is stored, per FR-029's 'see exactly what is stored'. The categories explicitly note that machine context excludes serial numbers, making FR-049's exclusion visible to the user rather than only true in code.

Defaults are the most private option that still works: paths are opt-in (off), retention bounded at 30 days.

One deliberate absence worth recording: there is NO window-titles setting, and a test asserts the encoded settings contain no such key. TASK-46 measured window titles as unavailable without Screen Recording, so offering the toggle would imply a capability we do not have -- an honest settings screen should not advertise what the app cannot do.
<!-- SECTION:NOTES:END -->
