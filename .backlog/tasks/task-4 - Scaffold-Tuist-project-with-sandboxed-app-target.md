---
id: TASK-4
title: Scaffold Tuist project with sandboxed app target
status: Done
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-08-02 03:01'
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
- [x] #1 tuist generate produces a building, signed, sandboxed .app
- [x] #2 Entitlements contain app-sandbox and nothing else
- [x] #3 FR-037: no privileged-helper code paths or unreachable privileged UI
- [x] #4 Builds from CLI without opening Xcode
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tuist project scaffolded. App target + Metrics framework + MetricsTests. Builds and runs from CLI, no Xcode.

Verified:
- AC#1 `tuist generate` then `tuist xcodebuild build` produces a signed .app; codesign --verify --deep --strict passes; sandbox container is created at ~/Library/Containers/com.brooksc.MacSlowdown at runtime, confirming the sandbox is actually applied and not just declared.
- AC#2 Release entitlements are exactly com.apple.security.app-sandbox and nothing else. This needed a fix: Xcode injects com.apple.security.get-task-allow into BOTH Debug and Release by default, and App Review rejects a submission carrying it. Release now sets CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO; Debug keeps it so the debugger can attach.
- AC#3 Single target, no build configuration, compilation condition or code path for a privileged tier. Nothing to strip later.
- AC#4 Full build, test and launch cycle runs from the CLI via ./run-menubar.sh.

Also fixed a real bug found by testing rather than assuming: an LSUIElement app runs with .accessory activation policy, and accessory apps CANNOT raise a window above other applications. `openWindow` succeeded and created the window at the right position, but it stayed behind whatever was in front, making it unreachable. Confirmed via AXUIElement: `background only: true`, frontmost stayed on another app even when forced. Fix is ActivationPolicy.swift: switch to .regular while the main window is open, back to .accessory on close. After the fix, frontmost=MacSlowdown and the window renders correctly (verified by screenshot).

Two smaller fixes:
- run-menubar.sh now always runs `tuist generate`, because Project.swift globs Sources/** and a newly added file is invisible to the build until regeneration. Cost is ~0.6s.
- `tuist xcodebuild` requires an action verb, so -showBuildSettings cannot go through it. Rather than discover the product path (tuist and plain xcodebuild resolve different DerivedData hashes for the same workspace), the script pins -derivedDataPath .build.

Added LSApplicationCategoryType=public.app-category.utilities; Xcode warns without it and MAS submission requires it.

Tests: 6 passing in MetricsTests, covering the two Tier 0 landmines -- mach ticks are not nanoseconds, and Duration.components.attoseconds truncates whole seconds. Entry point is `tuist xcodebuild test -scheme AllTests`; Tuist's auto-generated app scheme has no test action.
<!-- SECTION:NOTES:END -->
