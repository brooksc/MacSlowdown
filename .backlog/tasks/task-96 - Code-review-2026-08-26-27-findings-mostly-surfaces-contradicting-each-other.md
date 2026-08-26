---
id: TASK-96
title: 'Code review 2026-08-26: 27 findings, mostly surfaces contradicting each other'
status: In Progress
assignee: []
created_date: '2026-08-26 19:24'
labels:
  - core
  - ui
milestone: m-3
dependencies: []
priority: high
type: task
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A full read of `MacSlowdown/Sources/` and `Metrics/Sources/` against `CLAUDE.md`, `requirements.md`, `probe/FINDINGS.md` and the backlog, commissioned 2026-08-26. Nothing was verified on screen; layout findings are read off geometry in the code.

The dominant shape is the one this project keeps producing: **two surfaces answering the same question differently**, usually because a fix landed on one of them and a second site was never found. Three findings put a false or leaking statement into a file the user sends to someone else.

**High**
1. ✅ Incidents footer says closed incidents record no attribution, above rows naming applications — false since TASK-68.
2. ✅ Closed incident rows say their subject is busy "right now", in the present tense, from a recorded peak.
3. ✅ An exported report for a closed incident listed whatever was busy at export time, under that incident's heading. The screen behind the button got it right; the file did not.
4. ✅ "Hide app and process names" did not hide the name the report is about — the redactor only ever saw the *live* contributor list, while the Summary prose is built from the recorded one.
5. ✅ "Not thermal" and "storage did not run low" were asserted as measured facts from the absence of a *sustained* condition. A machine at serious thermal for 110 s of a 120 s threshold was described as having reported nothing.
6. ⬜ "No slowdowns since 9:14 AM" counts up to 90 days of persisted incidents against the launch time.
7. ⬜ The popover names the live CPU leader while the Now banner names the recorded one — the exact thing `NowPresentation.bannerHeadline`'s comment forbids.
8. ⬜ During a repeated-quit incident the popover's action offers to bring the CPU leader forward, not the subject of the headline above it.
9. ⬜ "Relaunches while watching" is counted by 16-byte command across the whole machine and shown, uncaveated and unlabelled, on one application's inspector.
10. ⬜ "Bring to front" is offered for daemons that cannot be activated — TASK-94's defect at a second site, plus TASK-94's own AC #3.
11. ✅ A Now footnote says applications have no retained history, under a table drawing their curves.

**Medium:** 12 memory budget stated in resident size (the statistic CLAUDE.md forbids) · 13 the Apps table sorts by a column that is not on screen · 14 the Now table's header detaches from its columns exactly when readings go stale · 15 the contributor row cannot fit the window's minimum width · 16 mounting a disk reports a fabricated write spike · 17 one sample of jitter deletes a family's whole retained series · 18 the verdict and the menu bar ignore the user's own thresholds · 19 ✅ the summariser's live fallback contradicted its own contract · 20 "none of your open apps accounts for it" said when up to 49% of it is your apps · 21 two safe actions report success without evidence · 22 the Now screen rebuilds the whole inventory once a second.

**Low:** 23 Alerts tab describes a defect TASK-69 fixed · 24 the menu bar sparkline has no baseline and amplifies calm · 25 `StorageScreenModel.tick` has no caller · 26 the self-cost line does not name its statistic and shows a measured 0.0% before measuring · 27 the Now contributor list does not visibly sum.

**Clean:** no FR-037 violation anywhere including dead code; rate handling sound apart from 16; identity is `(pid, start time)` throughout; the unattributed remainder is genuinely first-class; accessibility unusually thorough.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Findings 1-5, 11 and 19 are fixed with regression tests
- [ ] #2 Findings 6-10 are fixed or explicitly deferred with a reason
- [ ] #3 Medium findings are triaged: fixed, filed separately, or recorded as accepted
- [ ] #4 Layout findings 14 and 15 are checked on screen rather than from geometry
- [ ] #5 Anything deferred says so in the task rather than being silently dropped
<!-- AC:END -->
