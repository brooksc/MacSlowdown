---
id: TASK-110
title: >-
  "It feels slow now" — let the user report a slowdown, and keep the evidence
  (FR-064)
status: In Progress
assignee: []
created_date: '2026-09-06 16:53'
updated_date: '2026-09-08 17:23'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
type: feature
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**The single most valuable thing in either review, and the only instrument that can tell us what we miss.**

The product cannot distinguish a busy machine from a slow one and has no way to learn. A verdict on our own alerts ("was this useful?") can only ever measure the events we detected — it is precision with no recall, and it is blind to the afternoons someone lost while we recorded nothing unusual. Those are the failures that lose a user permanently.

A user-initiated report samples the population that matters.

**What it is.** One gesture, from a persistently reachable place — the menu bar is the obvious candidate — that says *it's slow now*. No form, no category, no severity. A second affordance offers "a few minutes ago" for the case where they only think to tell us afterwards.

**What happens.** The surrounding evidence is preserved on the same footing as an incident, marked user-provided (FR-038), kept under the same retention and privacy rules (FR-029), and never transmitted. **A report that matches no detected condition is a first-class result, not an error** — it is in fact the most informative kind, because it is a slowdown we missed.

**What it must not do.** Ask the user to describe or classify it; they are trying to get back to work. Respond by insisting nothing was wrong — everything we measured may well have looked normal, and that is a fact about our instruments, not about their afternoon. Take the report and never refer to it again, which makes the gesture extractive.

**Why this and not the verdict tap first.** They answer different questions and both may eventually be wanted, but this one is strictly more informative: it captures misses as well as hits, and it does not depend on us having interrupted in the first place. Keep "was this a slowdown?" separate from "was this alert useful?" — a real slowdown can still produce a late or unhelpful alert.

Blocks TASK-111 (the field trial), which has nothing to measure without it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A slowdown can be reported in one gesture from a persistently reachable surface, with no form and no required classification
- [ ] #2 A retrospective report covering the recent past is possible
- [ ] #3 Evidence around a report is retained under the same retention and privacy rules as an incident
- [ ] #4 A report matching no detected condition is preserved and shown as a result in its own right
- [ ] #5 Nothing about a report leaves the machine
- [ ] #6 Reports are visible afterwards, so the gesture returns something to the user
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Model, storage and retention built (2026-09-08).** No UI — deliberately, by instruction: a design revision is in flight and where the control lives is design's decision. Everything behind the gesture now works and is tested.

`Metrics/Sources/SlowdownReport.swift` — `SlowdownReport` (id, reportedAt, timing, experiencedAt, evidence). `SlowdownReportTiming` is `.now` or `.recently(secondsAgo:)` and carries no severity, category or free text, per FR-064. `SlowdownReportEvidence` holds the retained samples spanning the window, a named `SlowdownSampleCoverage` (a report with nothing behind it records *why* rather than inventing an empty series — `.noHistoryRetained`, `.windowOlderThanRetainedHistory`, `.noSamplesInWindow`), the attribution with a `SlowdownAttributionOrigin` saying whether it came from the coincident incident or from one sample at report time, the conditions in force, and the coincident incident's id. `SlowdownReport.make` is a pure function over supplied evidence so it can be called from whatever surface design chooses. `SlowdownDetectionOverlap` counts reports that coincided with detection against reports that did not — counts only, no rate, because the denominator is reports a person happened to make and anything phrased as recall would be a measurement of our instruments dressed as one of the machine.

`Metrics/Sources/SlowdownReportStore.swift` — a second store beside `IncidentHistoryStore`, following its shape exactly: schema version 1, numeric date encoding (TASK-72's ISO-8601 truncation would move a date by up to a second and change which incident a report is said to coincide with), retention enforced on every write, on load, and by `enforceRetention` for the sampling loop, plus a count bound (`defaultLimit` 100, lower than incidents' 200 because each report carries up to 180 samples). Kept a separate file from incidents on purpose: a report is not an incident and must never become one, and a schema step on either would otherwise force one on both. Queries: `reports(in:)` (matched on `experiencedAt`, so a retrospective report filed in the evening belongs to the afternoon) and `reportsWithoutDetection()`.

32 new tests, full suite 1183 passing / 0 failing. The no-coincident-condition case is tested explicitly, including through a real file and a second store. Sample thinning keeps only readings actually taken and records that resolution was lost (`observedSampleCount`); nothing is averaged into a synthetic point.

Six new symbols are staged in `probe/seam-allowlist.txt` awaiting the UI half and TASK-114.

**Still open, for the product owner:** the retrospective offsets the interface should offer (the model takes any); the `SlowdownReportPolicy` defaults (180 s lead-in, 60 s trailing, 180 samples); and whether the reports store should be included in the privacy tab's `storedCategories` list and in "delete all history" — `StoredData.recordedEvidenceFiles` will pick the file up by pattern, but the category list is hand-written and does not yet name reports.
<!-- SECTION:NOTES:END -->
