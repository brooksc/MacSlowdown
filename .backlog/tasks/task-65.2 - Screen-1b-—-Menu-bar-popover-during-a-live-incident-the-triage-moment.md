---
id: TASK-65.2
title: Screen 1b — Menu bar popover during a live incident (the triage moment)
status: To Do
assignee: []
created_date: '2026-08-09 02:21'
labels:
  - ui
milestone: m-2
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1b.png`. No implementation exists — the popover renders the same way whether or not an incident is open.

**What the design specifies**

This is the screen the product exists for. The popover changes shape during an incident:

- Headline states the condition and how long it has lasted: "CPU has been maxed for 6 min".
- A sentence naming the likely cause with its magnitude and the consequence in the user's terms: "Most of it is **Xcode** — 412% CPU, about 4 of your 10 cores. Your Mac will feel sluggish until it finishes."
- A sparkline of total CPU over the last 15 minutes, with the incident start marked on the axis ("12:26 … started 12:35 … now").
- "Share of the busy time" — a contributor list explicitly labelled as adding up to 100%, so the arithmetic is checkable. Unattributed system activity is in it at 38%.
- A note reconciling the two percentage conventions in play: Xcode at 412% of one core versus its 44% share of busy time. The design does not hide the ambiguity, it explains it.
- Three actions: "See the evidence", "Show Xcode", "Mute".
- A standing line: "MacSlowdown doesn't quit or pause apps for you — you stay in control of anything with unsaved work."

**Why it matters**

FR-013 and FR-038 require causal language to carry confidence labelling and evidence. This screen is where that lands in front of the user. The two-convention note is the design solving a problem CLAUDE.md flags as easy to get wrong (FR-004).

Depends on incident state already exposed by MonitorStore (`openIncident`), so the data is there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 While an incident is open the popover leads with the condition and its duration, not the normal-state layout
- [ ] #2 The cause sentence names the contributor, its magnitude, and the expected consequence, and carries a confidence label per FR-013
- [ ] #3 A short history sparkline shows the incident start relative to now
- [ ] #4 The contributor list is labelled as a share of busy time that sums to 100%, and reconciles that with the per-core percentages shown elsewhere (FR-004)
- [ ] #5 The three actions are present and none of them quits, pauses or otherwise controls another process (FR-037)
- [ ] #6 Verified on screen against design/screens/1b.png with a real incident, not a fixture
<!-- AC:END -->
