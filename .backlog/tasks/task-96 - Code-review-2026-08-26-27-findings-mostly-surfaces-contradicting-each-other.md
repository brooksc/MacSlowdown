---
id: TASK-96
title: 'Code review 2026-08-26: 27 findings, mostly surfaces contradicting each other'
status: In Progress
assignee: []
created_date: '2026-08-26 19:24'
updated_date: '2026-08-26 20:45'
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
- [x] #1 Findings 1-5, 11 and 19 are fixed with regression tests
- [x] #2 Findings 6-10 are fixed or explicitly deferred with a reason
- [x] #3 Medium findings are triaged: fixed, filed separately, or recorded as accepted
- [ ] #4 Layout findings 14 and 15 are checked on screen rather than from geometry
- [x] #5 Anything deferred says so in the task rather than being silently dropped
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Findings 1-11 and 19 fixed, 2026-08-26

**The three that leave the Mac (3, 4, 5)** and **the four stale-copy contradictions (1, 2, 11, 19)** are in the first commit. **Findings 6-10** are in the second:

- **6** — `monitoringLine` now takes `incidentDates` rather than a count, so the window it *names* and the window it *counts* are decided in one place. It also reads `store.monitoringStartedAt` rather than the process launch date, which is what the sentence actually claims. With no start time it no longer offers a count at all: there is no window to count against, and "Monitoring is running." is the honest sentence.
- **7** — the popover's causal sentence takes its subject from `incident.attribution` while an incident is open, which is the rule `NowPresentation.bannerHeadline` already followed and stated in a comment. Live state is used only when the incident has recorded nothing of its own.
- **8** — the popover's action branches on `leadingRelaunchPattern` exactly as `MainWindowView.bringForwardButton` does, so it can no longer say "Show Xcode" beneath a headline about Dropbox.
- **9** — `relaunchCount` gains `relaunchTally`, which carries the count, whether the command is currently shared with another family, and a confidence. The inspector's label changes from "Relaunches while watching" to **"Relaunches, by name"**, shows the evidence class and confidence beside the number, and carries a caveat naming the commands counted — spoken as well as in a tooltip, so a VoiceOver user is not the only one who misses it. The clipboard diagnostics say the same.
- **10** — the rule moves into `SafetyPolicy.availability(of:for:resolved:)`: no application bundle, no activation. It was fixed at one call site under TASK-94 and left standing at two others, which is exactly why it belongs in the policy. **This also closes TASK-94 #3.**

Seven new tests across three suites. 1113 passing, no failures — including both load-sensitive end-to-end tests on this run.

### One judgement call worth recording

Finding 9's suggested fix was to match on `(command, executablePath)`. That is not available: `LifecycleEvent` carries the identity and the command but no path, and a process that has *exited* cannot be resolved for one. So the count is still by command, and the change is to say so plainly and attach the confidence rather than to pretend a scope we cannot compute. Narrowing it properly would mean recording each exiting process's path at exit time, which is a real change to the tracker and belongs in its own task if the caveat proves insufficient.

## Mediums and lows, 2026-08-26

**Budget references removed from the product** at the product owner's instruction ("remove all references to memory/cpu budget, we can look at optimizing later"). The sidebar warning and `isWithinMemoryBudget` are gone. Finding 12 was right twice over: the budget has been deferred and non-gating since 2026-08-08, *and* it was stated in resident size — the one statistic CLAUDE.md says never to state a memory budget in, since ours ranged 809–3323 MB over a single run with no behaviour change. FR-030's actual requirement, reporting our own cost, is untouched.

**Scope of that removal, stated so it can be corrected:** user-facing claims only. `probe/overhead/run.sh` still measures against `FR030Budget` and prints pass/fail, because it is the measurement instrument and the stated reason for the removal was "we can look at optimizing later" — which needs the instrument intact. Code comments explaining *why* a cadence, a retention or a flush interval was chosen also stay: they are the rationale record, and deleting them would leave the values unexplained. Say the word and either goes.

**13** — the Apps table gains a "Last minute" column beside "Now", so the key it sorts by is on screen and sortable. It was opening ordered by an invisible number under a header showing a different one, with the footer explaining the unrelated 10 s order hold — the shape of TASK-63, which cost an hour.

**14** — the Now table's age cell now always occupies its 64 pt and the header reserves a matching one. It appeared only while readings were stale, so every numeric column slid left of its heading at exactly the moment the table most needed reading. Reserved rather than mirrored, so the two cannot fall out of step again.

**16** — `DiskSignals.rates` returns nil when `deviceCount` changes. Mounting a drive added its entire lifetime byte count to an aggregate divided by one second.

**17** — a family keeps its series through a two-minute grace period after falling out of the tracked 40, and is **not** appended to while untracked, so the gap stays a gap.

**18** — `Severity.forBusyShareOfMachine` takes the threshold in force; the elevated band is a fraction of it, so it moves with the setting. `liveBreachingConditions` is now derived from `SystemObservation.breaches` rather than a second set of lines, which had drifted far enough to announce "elevated, thermal" for a `.fair` state the detector ignores.

**20** — "None of your open apps accounts for it" becomes "Most of it was not your apps".

**21** — new `ActionResult.handedOff(request:)`. Reveal-in-Finder and open-Activity-Monitor hand off to macOS and cannot see the result, so they say so instead of reporting success. `didRun` is false for it.

**22** — the Now screen's age clock ticks only while a reading is actually late. It was rebuilding the whole family tree once a second to redraw a caption that only changes when sampling falls behind.

**23** — the Alerts banner described a defect TASK-69 fixed; it now describes the state it is actually in (monitoring not yet started).

**24** — the menu bar sparkline is drawn from zero to at least one core, like `HistorySparkline`. It normalised to its own min…max, so an idle machine drew the same full-height zig-zag as a saturated one.

**25** — `StorageScreenModel.tick` has a caller. "Checked N s ago" only advanced when `refresh()` reset it, so it read "Checked 0 s ago" for the whole interval.

**26** — the self-cost line names both statistics and reports no CPU figure until a rate exists.

**Not done: 15 and 27.** 15 (the contributor row cannot fit the window's minimum width) is arithmetic off the code and I have now *added* a column to that table, so it needs the screen rather than another guess — it is AC #4. 27 (the Now contributor list does not visibly sum) is defensible under FR-055's presentation freedom and was flagged for consistency rather than as a violation; it needs a product decision about whether the Now table gets the popover's residual row, so it is not something to change unilaterally.
<!-- SECTION:NOTES:END -->
