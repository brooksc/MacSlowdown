---
id: TASK-7
title: Implement application-family grouping (FR-003)
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 01:24'
labels:
  - core
milestone: m-1
dependencies:
  - TASK-3
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Depends on the identity spike. Group helper processes into user-meaningful application families while preserving individual PID records.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Known browser/helper fixtures aggregate correctly
- [ ] #2 Uncertain associations are labeled and reversible
- [ ] #3 Individual PID records preserved beneath the aggregate
- [ ] #4 Standalone (non-bundle) processes modelled as first-class, not family-of-one
- [ ] #5 Executable-inside-bundle subprocesses labelled as uncertain associations
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Settled by the TASK-3 spike:

- Group by the OUTERMOST .app in the executable path. The signed bundle ID does
  NOT group: helpers report their own identifier (net.imput.helium.helper.renderer),
  not the parent's (net.imput.helium).
- Verified working sandboxed, identical to unsandboxed: Helium.app -> 24
  processes, ChatGPT.app -> 15, Dock.app -> 5, 1Password.app -> 4, Xcode -> 4.
- IMPORTANT: only ~15% of processes (154/1063) belong to any application family.
  Daemons and CLI tools must be modelled as first-class standalone processes,
  NOT as a family-of-one. This affects the section 6 data model.
- Known false-grouping case to handle: ChatGPT.app absorbed node_repl and
  codex-code-mode subprocesses whose executables live inside the bundle.
  Label as uncertain per FR-003 and make user-correctable per FR-039.
<!-- SECTION:PLAN:END -->
