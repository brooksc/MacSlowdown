---
id: TASK-65.13
title: >-
  Screen 1m — All processes: the peer view, with unmeasurable processes shown
  honestly
status: In Progress
assignee: []
created_date: '2026-08-09 02:25'
updated_date: '2026-08-09 05:06'
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
- [x] #1 A flat all-processes view exists alongside the application-grouped view, with each process showing its owning application where it has one
- [x] #2 Unmeasurable processes are shown with name, PID, parent and start time, and their CPU and memory read 'not measurable' rather than a number
- [x] #3 Unmeasurable processes sort to the end under every sort order and are never treated as zero
- [x] #4 Unmeasurable processes can be hidden and shown, and the count is stated either way
- [x] #5 A census footer states total, measurable, unmeasurable, and how many belong to an application
- [x] #6 Well-known system daemons carry a human-meaningful descriptor, and the proportion of the unmeasurable set that can be described this way is recorded
- [ ] #7 Verified on screen against design/screens/1m.png, including sorting by CPU with unmeasurable rows shown
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built as `AllProcessesView` plus `AllProcessesRow`/`AllProcesses` (model, filtering, ordering, census) and `SystemProcessDescriptors` (the daemon table). Slots into TASK-65.4's segmented control, which had left the All processes side as a stated placeholder.

**The sort rule.** `AllProcesses.listing` partitions into measurable and unmeasurable, sorts each independently, and always returns measurable first. That is what makes "they sort to the end" true under *every* order rather than only descending CPU. The negative sort keys (-1) are kept as a second line of defence and are tested separately: a measured zero is 0, a refusal is -1. A key alone is not enough — sorting CPU ascending would float every refusal to the top, directly above the genuinely idle processes. Ten orderings are asserted (CPU, memory, name, PID, started, each direction).

Unmeasurable rows read a literal "Not measurable" in both metric columns, keep name/PID/parent/start time, and carry a subtitle of the form "Time Machine · parent launchd · protected". Lineage rejects a parent whose start time is later than its child's, since PIDs are reused.

**Descriptor coverage — measured.** The table is data (`byCommand` dictionary + `byPrefix` rules), not a switch, so coverage is countable via `SystemProcessDescriptors.coverage(of:)`. Against the real other-uid set on this machine (226 processes, 189 distinct names after 16-byte truncation): **223 described, 98.7%** (186/189 distinct, 98.4%). The three misses were `io.tailscale.ipn…` (third-party), `tracd`, and the probe's own `ps`. 182 exact entries, 12 prefix rules.

Two gotchas worth keeping: `p_comm` is 16 bytes, so table keys longer than that are also indexed by their 15- and 16-byte truncations, and a truncation shared by two entries with different meanings is dropped rather than resolved arbitrarily. Prefix rules match bidirectionally for the same reason — `com.apple.DriverKit…` arrives as `com.apple.Driver`.

Census footer states total · measurable · not measurable · how many belong to an app, and reuses `InventoryCensus.freshness` so it cannot disagree with the Apps footer. The "Show unmeasurable · N" toggle states the count either way and defaults to on.

Tests: 29 new in `MacSlowdown/Tests/AllProcessesTests.swift`. Full suite 567 passing; the only failure was the known load-synthesising `EndToEndIncidentTests.realSlowdownProducesOneIncident`, which passes in isolation.

**AC #7 not verified** — no screen use was permitted in this session. Sorting by CPU with unmeasurable rows shown, the section header, and the two-line name cell all need a look before this is closed.

Also noted: `main` at 1a3966b does not compile its app-hosted test bundle — `IncidentsViewRenderTests` calls `IncidentRow(incident:)` while the merged `IncidentsView` takes `entry:`. Pre-existing, not from this work, and left untouched.
<!-- SECTION:NOTES:END -->
