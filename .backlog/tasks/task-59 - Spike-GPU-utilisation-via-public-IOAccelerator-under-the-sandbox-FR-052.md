---
id: TASK-59
title: 'Spike: GPU utilisation via public IOAccelerator under the sandbox (FR-052)'
status: To Do
assignee: []
created_date: '2026-08-08 20:19'
updated_date: '2026-08-08 20:19'
labels:
  - spike
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FR-052 (GPU) is currently listed as unproven and was heading toward being dropped alongside the other sensor-class signals. Research into how iStat Menus 7 works suggests GPU *utilisation* may be separable from GPU *temperature and frequency*, and obtainable with no entitlement.

A competing Mac App Store monitor states it "reads device utilization from Apple Silicon GPUs through Apple's public IOAccelerator API", working in both App Store and direct builds "without requiring private APIs or elevated privileges" — and that same vendor explicitly omits temperature and fan data, which is consistent with the boundary we have measured everywhere else.

This is a single vendor's self-description, not Apple documentation, and nobody has measured it here. It is exactly the sort of claim this project settles with a probe rather than a decision.

Measure, in a signed sandboxed .app carrying only com.apple.security.app-sandbox:
- Whether the IOAccelerator entries in the IORegistry are readable at all.
- Whether "Device Utilization %" or an equivalent key is present and plausible, checked against a real GPU load rather than a zero reading.
- Whether anything is per-process or only machine-wide. Machine-wide is still useful; claiming per-process without evidence is not.
- What the sampling cost is, since FR-030 governs.
- Explicitly confirm that GPU temperature and frequency remain unavailable, so the finding cannot later be over-read.

If it works, FR-052 becomes deliverable in the MAS build as an aggregate signal and should be scoped that way. If it does not, record it and drop FR-052 from the MAS release with the same finality as FR-048.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A signed sandboxed probe reports whether IOAccelerator utilisation is readable, measured against a real GPU load and not a zero reading
- [ ] #2 The result distinguishes machine-wide from per-process, and claims only what was observed
- [ ] #3 GPU temperature and frequency are confirmed still unavailable, so the finding is not over-read later
- [ ] #4 Sampling cost is measured against the FR-030 budget
- [ ] #5 probe/FINDINGS.md and CLAUDE.md record the outcome either way
- [ ] #6 FR-052 is either scoped to what was proven or dropped from the MAS release
<!-- AC:END -->
