---
id: TASK-42
title: Per-process memory footprint instead of resident size (FR-043)
status: Parked
assignee: []
created_date: '2026-08-02 01:07'
labels:
  - parked
  - blocked-by-sandbox
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PARKED: ri_phys_footprint requires proc_pid_rusage, blocked under sandbox. We use pti_resident_size instead. Note Activity Monitor shows footprint, so our numbers legitimately differ and must be labeled. Resolves the section 10 open question on primary memory metric by elimination.
<!-- SECTION:DESCRIPTION:END -->
