---
id: TASK-57.1
title: Version strings and bundle IDs are shown as application names (FR-002)
status: To Do
assignee: []
created_date: '2026-08-09 02:14'
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
- [ ] #1 No row in the inventory or the popover displays a version-number path component as an application name
- [ ] #2 No row displays a raw bundle identifier where a display name is obtainable; where none is obtainable the row is labelled as unidentified rather than given a plausible-looking fragment (FR-002)
- [ ] #3 The processes currently naming themselves 2.1.220 and 2.1.226 are identified, and the task notes record what they are and which resolution step produced the wrong name
- [ ] #4 Verified on screen in the running app's inventory and popover, not by unit test alone
- [ ] #5 Test coverage includes a process whose executable path contains a version-numbered directory
<!-- AC:END -->
