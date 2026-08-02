---
id: TASK-20
title: 'Thermal and power context (FR-010, FR-047)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 06:37'
labels:
  - core
milestone: m-2
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Unavailable hardware temperature never fabricated
- [ ] #2 Desktop Macs degrade gracefully
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ThermalPowerSignals.swift: ThermalState and PowerContext.

- AC#1 Unavailable hardware temperature is never fabricated, enforced structurally rather than by care: the type carries no temperature field at all, so there is nothing to invent. A test asserts no explanation mentions degrees, celsius, fahrenheit, temperature, fan, rpm, mhz or ghz. Raw sensors need undocumented SMC keys, which A-03 rules out.
- AC#2 Desktop Macs degrade gracefully. Battery fields are Optional and nil when there is no battery, and the summary omits battery entirely rather than printing '0%' or 'unknown'. Tested both shapes explicitly.

Every explanation attributes the assessment to macOS ('macOS reports serious thermal conditions and may be reducing performance') rather than asserting our own diagnosis or claiming specific throttling behaviour, which FR-010 forbids.
<!-- SECTION:NOTES:END -->
