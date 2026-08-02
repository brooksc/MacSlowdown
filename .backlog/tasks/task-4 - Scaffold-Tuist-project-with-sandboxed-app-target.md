---
id: TASK-4
title: Scaffold Tuist project with sandboxed app target
status: To Do
assignee: []
created_date: '2026-08-02 01:06'
labels:
  - infra
milestone: m-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tuist chosen so entitlements and build settings live in reviewable Swift source rather than pbxproj. Single app target plus a Metrics module; defer further module splits until the sampler shape is proven.

Bundle ID com.brooksc.MacSlowdown, team SU999VT2G2. LSUIElement menu bar app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tuist generate produces a building, signed, sandboxed .app
- [ ] #2 Entitlements contain app-sandbox and nothing else
- [ ] #3 FR-037: no privileged-helper code paths or unreachable privileged UI
- [ ] #4 Builds from CLI without opening Xcode
<!-- AC:END -->
