---
id: TASK-57
title: 'Popover contributors show kernel-truncated command names (FR-003, FR-013)'
status: To Do
assignee: []
created_date: '2026-08-08 19:37'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The menu bar popover lists contributors by `ProcessRecord.command`, which is `p_comm` from the process table. The kernel truncates that to 16 bytes, so real rows read "Spotify Helper (" and "Helium Helper (R" — cut mid-word, mid-parenthesis, with no indication that anything was lost.

The inventory table does not have this problem because it shows `family.displayName` from the resolved identity. The popover is reaching past that to the raw record.

Two things are wrong, not one:
1. The name is wrong. A user cannot tell "Spotify Helper (" from "Spotify Helper (GPU". FR-013 requires the explanation name what it measured.
2. It is silently wrong. FR-002's rule is that a value we cannot fully report is labelled, not quietly abbreviated. A truncation the interface performs itself is worse than one it inherits.

The fix is to use the same resolved display name the table uses, and fall back to the truncated command only when identity resolution failed — in which case say so rather than presenting the fragment as the name.

Same defect likely affects the notification body, which also takes `contributors.first?.command`: the verified end-to-end alert read "bash is the largest measurable contributor", which was correct only because "bash" is short.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Popover contributor rows show the resolved application or process name, not p_comm
- [ ] #2 Notification bodies use the same resolved name as the popover and the table
- [ ] #3 A name that could not be resolved is shown as the command with its truncation acknowledged, never as a bare fragment
- [ ] #4 A name too long for the row is elided by the interface with an ellipsis and a full value available, which is distinct from kernel truncation
- [ ] #5 A test covers a command at exactly the 16-byte boundary
<!-- AC:END -->
