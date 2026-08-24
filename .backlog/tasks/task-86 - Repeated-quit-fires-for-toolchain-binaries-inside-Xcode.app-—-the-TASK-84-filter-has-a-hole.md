---
id: TASK-86
title: >-
  Repeated-quit fires for toolchain binaries inside Xcode.app — the TASK-84
  filter has a hole
status: In Progress
assignee: []
created_date: '2026-08-24 04:03'
updated_date: '2026-08-24 04:15'
labels:
  - core
milestone: m-2
dependencies: []
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on screen by the product owner, 2026-08-23, in the running Debug app on macOS 27 beta.

The menu bar icon was red with an incident open for 1 hr 33 min, headed "An application has been quitting and reopening". Reading `incidents.json` in the container, both persisted incidents carry condition `repeatedApplicationQuits`, and their subjects are:

- `git` (4 exits)
- `swift-frontend` (**419 exits**), `clang` (141), `swift-plugin-ser` (118), `git` (21), `swift-driver` (16), `swift-package` (11), `ld` (9), `xcodebuild` (8), `xctest` (7)

Those are compiler invocations, produced by this session's own `./run-menubar.sh`.

**Why the filter missed them.** TASK-84 restricted the condition to processes "running from inside a `.app`", implemented as `MonitorStore.isApplication` (`MacSlowdown/Sources/MonitorStore.swift:995`) returning `!ResolvedIdentity.isStandalone`, i.e. `appBundlePath != nil`, where `appBundlePath` is the outermost `.app` in the executable path. Xcode's entire toolchain lives inside `/Applications/Xcode.app/Contents/Developer/usr/bin/`, so every compiler, linker and `git` invocation satisfies the predicate. The filter that TASK-84 measured down to zero findings passes hundreds of them — on precisely the machine class most likely to be running this app during development.

TASK-84's amendment-2 rule is not wrong and was approved by the product owner on 2026-08-23; this is the implementation failing to express it.

**Direction (agreed with the product owner).** Tighten the predicate from "any binary inside a `.app`" to "the bundle's **main executable**": the process's executable path is `<bundle>/Contents/MacOS/…`, or the process matches a registered running application. FR-046's noun is *application*, and an application quitting means its main executable went away, not that it forked a compiler.

Note the recall consequence is already accepted in FR-046 amendment 2 and needs no further widening: a helper inside a bundle that really is crash-looping will not open an incident, and its exits remain visible as lifecycle events in the inspector.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A process whose executable is inside a .app but not at Contents/MacOS/ — an Xcode toolchain binary — no longer satisfies the application predicate
- [x] #2 A real application's main executable still does, with a test over both shapes of path
- [x] #3 The predicate remains a cache read on the sampling path, never a resolution, and remains a required parameter with no default
- [x] #4 Replaying the recorded subjects (swift-frontend, clang, git, ld, xcodebuild, xctest) yields zero relaunch patterns
- [ ] #5 The two spurious incidents already in incidents.json are accounted for: either migrated out or explained as pre-fix records
- [ ] #6 Verified on screen: after a full build with the app running, no repeated-quit incident opens and the menu bar icon does not go red
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The predicate, and why the framework tests could not have caught this

TASK-84's seam was sound. `LifecycleTracker.relaunchPatterns` filters on `event.isApplication`, and every test in `LifecycleEventsTests` injects that flag directly — so the framework was tested with the right answers and the shipping app supplied the wrong ones. The defect lived entirely in the one line that fills the seam.

New `ResolvedIdentity.isApplicationMainExecutable` replaces `!isStandalone` in both callers (`MonitorStore.isApplication` and `OverheadHarness`, which deliberately mirrors the app's path). The rule: the executable sits **directly** in some `Foo.app/Contents/MacOS/`.

**Bundled helper applications deliberately still qualify.** `Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper` is the main executable of a bundle, so a renderer crash-loop still opens an incident. Only the outermost-bundle grouping uses "outermost"; the subject rule does not, because a helper application repeatedly dying is exactly the case FR-046 is about. This is narrower than the old rule and wider than "only the outermost app's own binary", and it is the line that excludes the measured noise without costing the measured signal.

`.appex` is excluded by construction — an extension's directory ends `.appex`, not `.app` — and so is anything nested below `Contents/MacOS/`.

## Tests

- `ApplicationMainExecutableTests` (Metrics, 6 tests) over the path rule: real applications, the five recorded Xcode toolchain paths, a Chrome helper, an `.appex`, daemons, a nil path, and a nested resource.
- `RepeatedQuitSubjectTests` (Metrics, 2 tests) replays the exact subjects and counts from the two spurious `incidents.json` records through the real path rule joined to the tracker, and asserts zero patterns — then asserts Final Cut Pro quitting four times still yields one.

`AppBundleTests.helperAndParentShareFamily` already asserted that `swift-frontend` groups to `Xcode.app`. It is still correct and untouched: grouping and subject are different questions, and conflating them is what caused this.

## Test run

Full `AllTests`, `-jobs 6`: one failure, `SettingsAndIntentsTests.exportWithNoIncidents`, which is **not this change** — it requires the developer's real container to hold no incidents and today it holds two. Filed as TASK-91.

## AC #5 and #6 — outstanding

The two spurious incidents are still in `incidents.json`. Not deleted: they are the product owner's data and the decision to discard them is theirs. AC #6 needs a build run with the app watching, and has not been done.
<!-- SECTION:NOTES:END -->
