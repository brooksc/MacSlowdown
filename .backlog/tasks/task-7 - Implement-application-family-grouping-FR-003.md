---
id: TASK-7
title: Implement application-family grouping (FR-003)
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:13'
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
- [x] #1 Known browser/helper fixtures aggregate correctly
- [x] #2 Uncertain associations are labeled and reversible
- [x] #3 Individual PID records preserved beneath the aggregate
- [x] #4 Standalone (non-bundle) processes modelled as first-class, not family-of-one
- [x] #5 Executable-inside-bundle subprocesses labelled as uncertain associations
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Settled by the TASK-3 spike:

- Group by the OUTERMOST .app in the executable path. The signed bundle ID does
  NOT group: helpers report their own identifier (net.imput.helium.helper.renderer),
  not the parent's (net.imput.helium).
- Verified working sandboxed, identical to unsandboxed: BrowserApp.app -> 24
  processes, AssistantApp.app -> 15, Dock.app -> 5, VaultApp.app -> 4, Xcode -> 4.
- IMPORTANT: only ~15% of processes (154/1063) belong to any application family.
  Daemons and CLI tools must be modelled as first-class standalone processes,
  NOT as a family-of-one. This affects the section 6 data model.
- Known false-grouping case to handle: AssistantApp.app absorbed node_repl and
  assistant-helper subprocesses whose executables live inside the bundle.
  Label as uncertain per FR-003 and make user-correctable per FR-039.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ProcessFamily.swift. Grouping keys on the outermost .app in the executable path; the code signature decides confidence rather than membership.

Verified by test (39 passing overall), using fixtures rather than requiring specific apps to be installed:
- AC#1 A browser-shaped fixture (main process plus two nested Helper.app processes) aggregates into a single family, not three.
- AC#2 Reversible by construction. GroupingOverrides supports split-out and merge-into; tests confirm a detached process becomes standalone, a merged one joins as .userAssigned, and removing the override restores the inferred grouping exactly. Nothing is destroyed.
- AC#3 Individual PID records are preserved beneath the aggregate; a separate test confirms a member whose metrics are denied stays visible in the family rather than disappearing.
- AC#4 Daemons and CLI tools become standalone families with bundlePath == nil, not one-member applications. A mixed listing test confirms applications and standalone processes coexist.
- AC#5 The real Tier 0 false-grouping case is reproduced as a fixture: node_repl executing from inside AssistantApp.app is grouped there but labeled .uncertain with the reason naming its actual signature (org.nodejs.node). Genuine helpers sharing the parent's identifier prefix are .certain. A member with no signature at all is also uncertain, since path alone is weaker evidence.

Confidence rule: the family's identifier comes from the executable directly in Contents/MacOS. A member whose signed identifier equals it or extends it with a dot prefix is certain; a member running from inside the bundle but signed otherwise is uncertain and says why.

A live-system test asserts the invariant that matters most: every process in the snapshot appears exactly once across all families, none duplicated, none dropped.

Swift 6 friction worth noting for later tasks: rethrows methods (allSatisfy, count(where:), first(where:), contains(where:)) cannot be used directly inside #expect/#require macros -- the expansion cannot prove them non-throwing. Hoist them into a local first.
<!-- SECTION:NOTES:END -->
