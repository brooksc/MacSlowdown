---
id: TASK-11
title: Menu bar status surface and severity model (FR-001)
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:51'
labels:
  - ui
milestone: m-1
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Indicator updates within 2s of a severity transition
- [x] #2 Can be hidden
- [x] #3 Accessible to assistive technology; severity never by color alone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MenuBarExtra driven by MonitorStore; Severity carries symbol, word and threshold.

- AC#1 The indicator re-renders on every sample at the 2s default cadence, so a severity transition surfaces within one interval. Severity is derived from busy share of total machine capacity.
- AC#2 Hideable via a Settings toggle bound to MenuBarExtra(isInserted:). Verified by flipping the stored preference and relaunching: hidden gives zero menu bar items, shown gives one.
- AC#3 The label is not colour-dependent: the SF Symbol changes shape with severity (33/67/100 percent gauge variants) and carries an accessibility label naming the state in words. The popover header combines symbol and word and is exposed as one accessibility element.

Two real bugs found by testing the hidden state rather than assuming it worked:
1. Monitoring never started when the item was hidden. The sampling loop was kicked off by a .task on the menu bar label, and with the item hidden that view never renders -- so the app ran and measured nothing. Moved app lifecycle into an NSApplicationDelegate, which does not depend on any view rendering. MonitorStore is now a shared instance for that reason.
2. Hiding the item terminated the app. SwiftUI ends the process once no scene is visible, so hiding the only surface quit MacSlowdown outright. Fixed with applicationShouldTerminateAfterLastWindowClosed returning false -- monitoring is the product, and closing the last window must not end it.

Also: when the item is hidden the app switches to .regular activation policy so it keeps a Dock icon. Otherwise hiding the only visible surface would strand a running app with no way back. Verified: hidden gives background only = false, shown gives true.
<!-- SECTION:NOTES:END -->
