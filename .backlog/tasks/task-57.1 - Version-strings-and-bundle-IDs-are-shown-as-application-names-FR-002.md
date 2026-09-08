---
id: TASK-57.1
title: Version strings and bundle IDs are shown as application names (FR-002)
status: In Progress
assignee: []
created_date: '2026-08-09 02:14'
updated_date: '2026-08-09 03:09'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
parent_task_id: TASK-57
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression or gap against TASK-57, which delivered human-meaningful names and icons.

Observed on macOS 27 in the built Debug app. Screenshots: `screenshots/03-apps-processes.png`, `screenshots/01-menubar-popover.png`.

In the Apps & Processes inventory, three of the top ten rows by CPU are named after version numbers:
- `2.1.226` — 12%, 645.5 MB
- `2.1.220` — 12%, 705.9 MB
- `2.1.220` — 0.8%, 234.6 MB, and again at 0.5%, 272.5 MB

So the same string names four separate rows, and a user cannot tell what any of them are. The menu bar popover shows the same thing: `2.1.220 20%` and `2.1.226 9.7%` sit in the top three contributors, alongside `com.apple.Safari…` — a raw bundle identifier, truncated, presented where a name belongs.

Likely cause, stated as hypothesis rather than fact: some applications install under a version-numbered directory (`.../SomeApp/2.1.220/...`), and the naming fallback is taking a path component that happens to be a version. Worth checking against `ProcessNaming`'s resolution order — running application, outermost `.app`, `.appex`, then command — and finding which step produces this.

FR-002 is explicit that a fragment must not be shown as if it were the name. A version number is worse than a truncated command, because it looks like a legitimate name and tells the user nothing. This lands in the two most prominent surfaces in the app: the popover's top-three contributors and the inventory's busiest rows.

Determining what these processes actually are is part of the work — the answer shapes whether this is a fallback ordering bug or a missing case.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No row in the inventory or the popover displays a version-number path component as an application name
- [x] #2 No row displays a raw bundle identifier where a display name is obtainable; where none is obtainable the row is labelled as unidentified rather than given a plausible-looking fragment (FR-002)
- [x] #3 The processes currently naming themselves 2.1.220 and 2.1.226 are identified, and the task notes record what they are and which resolution step produced the wrong name
- [ ] #4 Verified on screen in the running app's inventory and popover, not by unit test alone
- [x] #5 Test coverage includes a process whose executable path contains a version-numbered directory
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What those processes are (criterion #3)

Measured with `probe/Sources/version-name-probe.swift`, signed and sandboxed, 797 processes.

**They are Claude Code.** `~/.local/bin/claude` is a symlink to `~/.local/share/claude/versions/2.1.226`: Claude Code installs one binary per version and names the *file* after the version. `proc_pidpath` returns that path and `p_comm` is therefore literally `2.1.226`. Eight were running — pids 2252/21031/56393/67784/81139 (2.1.220 and 2.1.226) and 21444/38222/65870 across 2.1.220, 2.1.224, 2.1.226 — which is why one string named four indistinguishable rows.

**The hypothesis in the description is wrong in mechanism.** No fallback took a version-numbered path component. The failing step was the *last* one: `ResolvedIdentity.displayName(command:)` falling through to `p_comm`, which was correct by every rule we had. There is no `.app`, no `.appex`, and no Launch Services registration anywhere for these processes, so `ProcessNaming.resolve` correctly returned nil.

**`com.apple.Safari…` is the same defect from the other end.** `p_comm` is cut at 16 bytes, so `com.apple.Safari.History` (pid 28318, `/System/Volumes/Preboot/Cryptexes/App/usr/libexec/`) and `com.apple.Safari.SafeBrowsing.Service` (pid 66515) both render as `com.apple.Safari…`, which reads as Safari. 29 processes were showing a cut-off reverse-DNS fragment. The executable *file* name is not truncated, so the path recovers the whole identifier.

**A declared name can itself be an identifier.** Found while checking the fix against the live table: `PressAndHold.app` declares `CFBundleName` = `com.apple.PressAndHold`, and `CoreSimulatorService` registers with Launch Services under its own identifier. Having a source for a string does not make it a name, so the check sits after the declared name, not only on the path fallback.

## What changed

`Metrics/Sources/ProcessNaming.swift`
- `isVersionNumber`, `isBundleIdentifier`, `isNonName`, `unidentified(_:)`. A non-name is shown as `Unidentified process (2.1.220)` — the evidence stays beside the label rather than being dropped (FR-002, FR-038). Applied in `labelled(command:)` and `accessibilityLabel(command:)`, so the inventory and the popover (`ProcessCPUUsage.label`) agree.
- `installationName(forExecutablePath:)`: a version-named executable is named after its install directory — `.../claude/versions/2.1.226` -> `claude`. Searches at most **two** levels, skips structural components (`bin`, `versions`, `Contents`, …), and never accepts a directory directly under `/Users` or `/home`, because that is an account name and does not belong on screen (A-05).
- `resolve` now checks the declared name for non-name shapes, and recovers the untruncated executable file name for identifiers.

`Metrics/Sources/ProcessFamily.swift` — only members that live *inside* a bundle may name their family. Members arrive in the snapshot dictionary's order, so a `.byParent` member (a shell under a terminal, a `claude` under TerminalApp) could name the family on one sweep and not the next. Latent before this task; the fix made it likely enough to matter.

## Verification

Re-ran the probe compiled against the shipping `ProcessNaming`, over the live table: **0 of 797 processes still display a version number or a bare identifier**, and all eight Claude Code processes resolve to `claude`.

Tests: **400 passing, 0 failing** (`tuist xcodebuild test -scheme AllTests`), up from 388 in this worktree — 12 added. `EndToEndIncidentTests.realSlowdownProducesOneIncident` failed twice on a machine running three other agents and passed in isolation and on re-run; it measures real CPU separation and is load-sensitive, not affected by naming.

## Not verified

Criterion #4 (on screen, in the running app's inventory and popover) is **not verified**: the user was working on the machine and the session was instructed not to launch the app, screenshot, or drive the UI. It needs a look at the Apps & Processes list and the menu bar popover.

## Judgement calls worth a second opinion

- `Unidentified process (com.apple.geod)` now replaces `com.apple.geod` for ~29 processes whose only available name is a reverse-DNS identifier. That is criterion #2 read literally. Activity Monitor shows the bare identifier instead, so the two tools will differ, and the label is longer in a narrow column. If the preferred reading is 'only when truncated', the change is one line in `resolve`.
- Naming a version-named executable after its install directory is a derivation from the path, not a declared name. It is bounded to two levels and to executables that are literally version numbers, but it is a heuristic and is labelled as nothing in the UI.
<!-- SECTION:NOTES:END -->
