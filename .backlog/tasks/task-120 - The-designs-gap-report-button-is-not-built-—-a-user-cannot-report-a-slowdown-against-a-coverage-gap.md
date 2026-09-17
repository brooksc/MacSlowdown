---
id: TASK-120
title: >-
  The design's gap-report button is not built — a user cannot report a slowdown
  against a coverage gap
status: Done
assignee: []
created_date: '2026-09-17 02:31'
updated_date: '2026-09-17 18:17'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: high
type: feature
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-09-16 by comparing the built Overview against design **5c**, screen by screen.

The built coverage record follows 5c closely — the headline pattern, the explanatory paragraph, the hatched strip, and the three-state legend are all there, in some places word for word. **One element of 5c is missing entirely**: the button beneath the strip.

Design 5c:

> **[ Something happened then ]**  Files a report against the gap, so at least the time is recorded.

There is no occurrence of that button, or anything playing its part, anywhere in the source. The only report gesture built is `SlowdownReportPresentation.reportNowTitle` — **"It feels slow right now"** — which is present-tense only, on the Overview and in the menu bar popover.

**Why this matters more than a missing button.** It is the bridge between two things the product already treats as central:

- **S-2** is the scenario where the episode is over before anyone looks, and the coverage record exists precisely so the user can ask "what happened at 11:22". When the answer is "we weren't watching", 5c's button is the one action that turns a dead end into data.
- **FR-064** is the governing decision that the user telling us it felt slow is the next substantive feature, because a measured condition is not an experienced slowdown. A gap is the case where we have *no* measurement at all, so the user's report is not merely the better evidence — it is the only evidence there will ever be.

**The engine is already there.** `SlowdownReportTiming.recently(secondsAgo:)` exists, `SlowdownReport.make` accepts it, and a scenario test already asserts that a retrospective report is dated from the experience rather than the filing. So this is a built-but-unreachable capability of the kind `probe/SEAM-AUDIT.md` tracks, not new machinery — what is missing is the affordance and the plumbing from a specific gap to `secondsAgo`.

**One design question to settle before building.** 5c's button files against *the gap as a whole* ("so at least the time is recorded"). The retained evidence for such a report is, by definition, nothing — there were no readings. So the report must be honest that it has no samples, which `SlowdownSampleCoverage.hasSamples` already expresses and a scenario test already covers. Worth confirming the copy says so rather than presenting an empty evidence section.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A gap on the Overview coverage strip offers a way to report that something happened during it
- [x] #2 The resulting report is dated from the gap rather than from the moment it was filed, using the existing recently(secondsAgo:) timing
- [x] #3 The report states plainly that no readings were retained for that period, rather than showing an empty evidence section
- [x] #4 It is counted in SlowdownDetectionOverlap as a report without a coincident detection, since by construction there can be no detection
- [ ] #5 Seen on screen — the button, and the report it produces — not inferred from a passing test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Built 2026-09-17.** `OverviewView.gapReportAction`, shown only when the visible window has a gap, with `SlowdownReportPresentation.gapReportTitle` / `gapReportCaption` carrying 5c's words.

**#1** The button sits under the coverage strip, and `OverviewPresentation.reportableGap` returns the *same* gap `gapNote` names — both read `gaps.first`, neither picks its own. A test asserts the sentence contains the range the button files against; a button and a sentence disagreeing about which stretch they mean is FR-060's failure in miniature.

**#2** Dated from the **middle** of the gap via `secondsAgo(ofMiddleOf:now:)`, not from either edge: a report is a point and the policy builds a window around it, so aiming at an edge would centre that window half outside the stretch the user is pointing at.

**#3** No new copy was needed. `keptReadings` already resolves `.noSamplesInWindow` to "We weren't recording during those minutes, so this is kept as the time you gave us and nothing else. It still counts." The outcome sentence is composed from the report the store actually returned rather than asserted from the gap — if the coverage ever resolved to something else, the screen would say that instead of a comfortable fiction.

**#4 exposed a model fault older than this task.** `conditionsInForce` is documented as what is breaching *now*, and `MonitorStore.reportSlowdown` passed the open incident's set to every report regardless of when it pointed at. So a retrospective report filed while any unrelated incident happened to be open came back `coincidedWithDetection` — inflating the one figure FR-064 exists to produce. The picker's "an hour ago" had the same defect; the gap button only made it unmissable, since by construction a gap can have no detection at all.

The rule now lives in `SlowdownReport.make` rather than in each caller, because there is no correct per-surface variation of it: a retrospective report keeps conditions only from an incident that genuinely *covers* the reported moment. Live attribution is withheld from a retrospective report for the same reason — it describes the machine now. Seven tests in `GapReportTests`, including both sides of the narrowing (a report about now is unaffected; a retrospective report inside a real episode keeps that episode's conditions).

**#5 is not met and is left unchecked.** The button has not been seen on screen. It appears only when the coverage log has a gap, and neither a preview with an empty store nor a freshly launched app in the VM has one — producing a gap means stopping the app for a stretch and restarting it, which the capture script does not yet stage. What *would* settle it: run `probe/vm-capture.sh`, kill the app for two minutes, relaunch on Overview, and confirm the button appears beneath the strip and that pressing it yields the "It still counts" reply. Recorded rather than inferred from the passing tests.
<!-- SECTION:NOTES:END -->
