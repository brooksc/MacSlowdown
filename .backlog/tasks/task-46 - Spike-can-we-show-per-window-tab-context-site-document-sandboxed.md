---
id: TASK-46
title: 'Spike: can we show per-window/tab context (site, document) sandboxed?'
status: Done
assignee: []
created_date: '2026-08-02 01:56'
updated_date: '2026-08-02 03:52'
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
- [x] #1 Documented whether window titles are obtainable sandboxed, and at what permission cost
- [x] #2 If it requires Screen Recording, a product decision is recorded on whether to ask for it
- [ ] #3 Design updated to match the answer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ANSWER: window titles are NOT available to a sandboxed App Store build without Screen Recording permission. The design's per-tab context ("Chrome Helper — figma.com") must be cut.

Measured, sandboxed, launched via `open` so launchd is the responsible process:
  windows returned        8
  with owner name         8/8   <- app name IS available, no permission needed
  with kCGWindowName      1/8   <- only our own menubar window
  CGPreflightScreenCaptureAccess  false
  AXIsProcessTrusted              false

A methodology note worth keeping, because it nearly produced the opposite conclusion: running the same probe directly from a terminal reported 8/8 titles and screen-capture access true. macOS attributes TCC permissions to the *responsible process*, which for a binary exec'd from a terminal is the terminal itself, so the probe inherited the terminal's Screen Recording grant. Any TCC-sensitive capability must be tested via `open`, never by exec'ing the binary from a shell.

Consequences:
- Per-tab and per-document context is out for the MAS build. Asking for Screen Recording to label a browser tab is disproportionate and a likely App Review question, and FR-029's privacy posture argues against it independently.
- The Privacy screen's "Record file paths and window titles" option should drop the window-titles half. File paths remain available via proc_pidpath.
- Usefully, kCGWindowOwnerName IS available for every window with no permission at all. That gives which applications currently have on-screen windows, which is enough for foreground/visible state (FR-002) without asking for anything.

No product decision needed: this closes as "not available", which is the answer the spec prefers -- omit rather than approximate.
<!-- SECTION:NOTES:END -->
