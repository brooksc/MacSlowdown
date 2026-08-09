---
id: TASK-59
title: 'Spike: GPU utilisation via public IOAccelerator under the sandbox (FR-052)'
status: Done
assignee: []
created_date: '2026-08-08 20:19'
updated_date: '2026-08-09 00:57'
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
- [x] #1 A signed sandboxed probe reports whether IOAccelerator utilisation is readable, measured against a real GPU load and not a zero reading
- [x] #2 The result distinguishes machine-wide from per-process, and claims only what was observed
- [x] #3 GPU temperature and frequency are confirmed still unavailable, so the finding is not over-read later
- [x] #4 Sampling cost is measured against the FR-030 budget
- [x] #5 probe/FINDINGS.md and CLAUDE.md record the outcome either way
- [x] #6 FR-052 is either scoped to what was proven or dropped from the MAS release
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
GPU utilisation IS available sandboxed. FR-052 survives, scoped to machine-wide only. Full detail in probe/FINDINGS.md; probe/Sources/gpu-probe.swift.

One IOAccelerator service is readable with only com.apple.security.app-sandbox: AGXAcceleratorG14G. Its PerformanceStatistics exposes Device Utilization %, Renderer Utilization %, Tiler Utilization %, and memory figures.

Verified against a real Metal compute load rather than a zero reading. Under load the figure pinned at 97-98% for four seconds; beforehand it ranged 0-68%.

Important caveat, and it changes how the feature must be built: the pre-load baseline was NOT idle. Ordinary window compositing reached 68%, so a single sample cannot distinguish real GPU work from a busy desktop. Only persistence separates them. FR-052 must therefore report a sustained condition, using the same duration-and-hysteresis rule as FR-006 — never an instantaneous value.

Confirmed absent by enumerating every key in every service: no temperature, no frequency or clock, and nothing per-process. There is no pid, process or client key anywhere, so per-application GPU attribution would be a fabrication. Machine-wide only.

Cost: 2.54 ms per read, mean of 20 — more than the entire per-process metrics sweep (1.8 ms), because each read re-matches services and builds a full property dictionary. At 2 s cadence that is ~0.13% of one core and fits FR-030, but the service handle must be matched once and retained rather than looked up per sample. Recorded as a rule.

TASK-39 folded in as a duplicate.
<!-- SECTION:NOTES:END -->
