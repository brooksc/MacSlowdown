---
id: TASK-65.13
title: >-
  Screen 1m — All processes: the peer view, with unmeasurable processes shown
  honestly
status: To Do
assignee: []
created_date: '2026-08-09 02:25'
labels:
  - ui
  - core
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1m.png`. The second half of the Apps & processes segmented control (screen 1d is the first). Existing implementation: our inventory groups everything into families with a "System processes" group; there is no flat process view.

**What the design specifies**

Header: segmented control with "All processes · 412" selected, a "Show unmeasurable · 234" toggle, and a search field. Columns: Process, CPU, Resident memory, PID, Started — with each row's owning application as a subtitle where it has one ("swift-frontend / Xcode", "Chrome Helper (Renderer) / Google Chrome", "mdworker_shared / Spotlight worker · user level").

Below the measurable rows, a distinct section: **"234 processes we can't measure"** with the rule stated on the screen — "Name, PID, parent and start time are readable. CPU and memory are not. **They sort to the end and never count as zero.**"

Each unmeasurable row shows name, a descriptor ("WindowServer / parent launchd · protected", "backupd / Time Machine · parent launchd · protected", "mds_stores / Spotlight system indexer · protected", "coreaudiod / Core Audio · protected", "kernel_task / Kernel · protected"), literal "Not measurable" in both metric columns, PID and start time. Then "229 more unmeasurable processes".

Footer census: "412 processes · 178 measurable · 234 not measurable · only 63 belong to an app", and "Updated 1 s ago".

**Why the sort rule is the requirement**

"They sort to the end and never count as zero" is the whole screen. A process whose CPU cannot be read is not a process using no CPU, and sorting it as 0% would put the busiest processes on the machine at the bottom of a CPU-sorted list. CLAUDE.md establishes that measurability is decided exactly by uid, so the set is precisely known — 599 own-uid readable, 229 other-uid denied, no exceptions. `InventoryRow.memorySortKey` already uses -1 for unmeasurable, so the intent exists in the code; this screen is where it has to hold for the user.

The descriptors ("Time Machine", "Spotlight system indexer", "Core Audio") are a curated mapping from daemon name to human meaning — worth treating as data, not a switch statement, and worth checking how many of the 234 can be named at all.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A flat all-processes view exists alongside the application-grouped view, with each process showing its owning application where it has one
- [ ] #2 Unmeasurable processes are shown with name, PID, parent and start time, and their CPU and memory read 'not measurable' rather than a number
- [ ] #3 Unmeasurable processes sort to the end under every sort order and are never treated as zero
- [ ] #4 Unmeasurable processes can be hidden and shown, and the count is stated either way
- [ ] #5 A census footer states total, measurable, unmeasurable, and how many belong to an application
- [ ] #6 Well-known system daemons carry a human-meaningful descriptor, and the proportion of the unmeasurable set that can be described this way is recorded
- [ ] #7 Verified on screen against design/screens/1m.png, including sorting by CPU with unmeasurable rows shown
<!-- AC:END -->
