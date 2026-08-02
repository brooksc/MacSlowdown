---
id: TASK-46
title: 'Spike: can we show per-window/tab context (site, document) sandboxed?'
status: To Do
assignee: []
created_date: '2026-08-02 01:56'
labels:
  - spike
  - risk
milestone: m-1
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised by the UI design review. Screen 1d shows "Chrome Helper (Renderer) - figma.com", attributing a renderer process to a specific site, and the Privacy screen offers "Record file paths and window titles".

Feasibility is unverified and I suspect it is blocked:
- CGWindowListCopyWindowInfo returns kCGWindowName (the title) only with Screen Recording permission since macOS 10.15. That is a heavy permission ask for a monitoring utility and a likely App Review question.
- The Accessibility API route requires AXIsProcessTrusted, which sandboxed apps generally cannot obtain.

If neither is available, the per-tab/per-document context must be cut from the design, which materially weakens the "which tab was busy" story. Decide before building the inspector.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Documented whether window titles are obtainable sandboxed, and at what permission cost
- [ ] #2 If it requires Screen Recording, a product decision is recorded on whether to ask for it
- [ ] #3 Design updated to match the answer
<!-- AC:END -->
