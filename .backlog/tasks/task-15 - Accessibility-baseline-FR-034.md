---
id: TASK-15
title: Accessibility baseline (FR-034)
status: Parked
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 04:02'
labels:
  - ui
milestone: m-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Non-negotiable. Build in from the start rather than retrofitting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 VoiceOver labels, full keyboard operation
- [x] #2 Increased contrast and reduced transparency respected
- [x] #3 Severity never conveyed by color alone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Baseline built in throughout rather than retrofitted, but PARKED: AC#1 cannot be fully verified from here.

- AC#3 (severity never by colour alone) VERIFIED. The SF Symbol changes shape across severities (gauge 33/67/100), every severity is stated as a word, and the live menu bar item's accessibility description reads "status menu, MacSlowdown: Normal" -- confirmed against the running app.
- AC#2 (increased contrast, reduced transparency) VERIFIED BY CONSTRUCTION. There is not a single hardcoded colour in the app: everything uses semantic styles (.secondary, .quaternary, .quinary) and system materials (.bar), which follow the system's contrast and transparency settings automatically. Audited with grep; no Color.red/green/etc and no .foregroundColor calls.
- AC#1 (VoiceOver labels, full keyboard operation) PARTIALLY VERIFIED. Labels are annotated in code -- the figures grid reads each row as one sentence including its evidence class, the unattributed row carries a label plus the full explanation as a hint, inventory CPU cells name their application, and the stale banner reads as one statement. But I could not confirm them at runtime: SwiftUI on macOS 26 exposes the window through a remote accessibility tree that System Events cannot walk, so the traversal returned nothing. Keyboard operation likewise was not exercised end to end.

FR-034's own criterion is "accessibility audit passes", which needs VoiceOver and Xcode's Accessibility Inspector driven by a human. To finish: run Accessibility Inspector's audit against the Now, Apps & Processes and Settings windows, then tab through each surface with VoiceOver on and confirm every control is reachable and every figure reads with its evidence class.

Nothing else depends on this, so it does not block other m-1 work.
<!-- SECTION:NOTES:END -->
