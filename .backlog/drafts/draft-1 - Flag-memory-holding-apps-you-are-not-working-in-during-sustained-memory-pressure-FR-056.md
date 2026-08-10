---
id: DRAFT-1
title: >-
  Flag memory-holding apps you are not working in, during sustained memory
  pressure (FR-056)
status: Draft
assignee: []
created_date: '2026-08-10 01:37'
updated_date: '2026-08-10 01:38'
labels:
  - core
  - ui
  - decision
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Product owner's idea, 2026-08-09.** Under memory pressure, tell the user which windowed applications are holding a lot of memory that they have not been working in — so the action is "you could close this" rather than a sorted list they must interpret.

**Status: blocked on spec review.** `requirements.md` now carries a drafted **FR-056** whose Human-review status reads *"Drafted 2026-08-09 from a product owner request — awaiting review."* Per CLAUDE.md's authority rule, nothing here is implemented until that row reads Approved. Read the FR first; it is the specification and this is only the work item.

## Why this one is unusual

Every input is already measured and verified in `probe/FINDINGS.md`, with no new entitlement and no new sandbox risk:

- `kCGWindowOwnerName` is readable for **every** window with no permission at all (measured 8/8). Window *titles* are not — 1 of 8, and that one was ours — so there is no per-document or per-tab context, only "this application owns windows".
- `NSWorkspace.frontmostApplication` gives the foreground application.
- Resident memory is readable for own-uid processes.
- The official memory pressure signal is already wired and pushed by the kernel (TASK-65.14).

Feasibility risk is therefore near zero, which is rare here. **The risk is entirely in the claim.**

## The three things that decide whether this is honest

1. **"Not frontmost" is not "not needed."** A background render, download, build or backup is doing precisely what the user asked, and we cannot see that it is working. The copy may say only *"not frontmost since T"* and *"holding N of measured resident memory"* — both measurements — and must never say idle, abandoned, forgotten, wasteful or leaking. FR-044's rule about never calling growth a leak applies with full force.
2. **We cannot close anything and must not imply we will.** FR-037 forbids process control outright, even dormant. The action is a plain instruction to the user, plus the safe actions FR-018/FR-019 already allow.
3. **No "this would free N."** FR-036 forbids claiming memory was freed without a measurement showing it was. If the user acts, we re-measure over a bounded window and are allowed to say "inconclusive" — which will often be the truthful answer, because macOS reclaims lazily and the pressure signal may not move at all.

## Open question worth resolving during design

Per-process audio is available with no permission (`kAudioHardwarePropertyProcessObjectList`, verified against real playback). Should an application currently producing audio be suppressed as a candidate? It is a cheap, real activity signal for exactly the "it is doing something in the background" case — but it covers only one kind of work, so it would half-solve the heuristic's weakness while implying we check for activity generally.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FR-056's Human-review status reads Approved before any code is written
- [ ] #2 Candidates are applications that own windows, hold more than a stated share of resident memory, and have not been frontmost for a stated period — each of the three presented as a measurement
- [ ] #3 No copy says idle, abandoned, wasteful, forgotten or leaking, and none asserts the application is at fault (FR-044)
- [ ] #4 No figure is offered for memory that would be recovered (FR-036)
- [ ] #5 Nothing quits, suspends or signals any process, and no interface element implies the app can (FR-037)
- [ ] #6 An application the user marked expected never appears (FR-016)
- [ ] #7 Applications whose memory cannot be read are named as unmeasurable rather than silently omitted (FR-055)
- [ ] #8 Before the foreground-history threshold has elapsed the feature yields no candidates, rather than a list carrying a caveat
- [ ] #9 Any follow-up measurement states what was re-measured over a bounded window and says inconclusive where the pressure signal did not move (FR-050)
- [ ] #10 The cost of tracking last-frontmost time is measured against the FR-030 instrumentation and recorded
<!-- AC:END -->
