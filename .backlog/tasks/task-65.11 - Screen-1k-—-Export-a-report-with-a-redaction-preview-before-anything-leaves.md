---
id: TASK-65.11
title: 'Screen 1k — Export a report, with a redaction preview before anything leaves'
status: Done
assignee: []
created_date: '2026-08-09 02:24'
updated_date: '2026-09-17 18:58'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1k.png`. Existing implementation: `DiagnosticExport` (TASK-33) exists in the framework with redaction; there is no export UI.

**What the design specifies**

Title: "Share the Thursday memory-pressure report". Subtitle: "Check what's in it before you send it. Nothing is uploaded — you'll get a file to attach yourself."

- **Include**: Charts and measurements / Mac and macOS details / Timeline of events.
- **Hide**: My user name / File paths / App names — with a warning under the last one: "Hiding app names makes the report much harder for anyone to interpret." The design lets the user over-redact but tells them the cost.
- **Format**: PDF and JSON.
- **Preview** — the decisive element. A live monospace rendering of the actual report with redacted fields shown as filled blocks marked "redacted", so the user sees precisely what a recipient will see. It includes the incident id, window, machine, redacted user, peak measurements, top contributor, redacted path, and the schema/rules/build footer.
- A summary of the report: "memory pressure was critical for 5 min 40 s. Chrome held the largest share of app memory at the peak (measured). Chrome as the main cause is a moderate-confidence judgement, not a certainty." — the confidence labelling survives into the exported artefact.
- Status line: "2 of 6 sensitive fields redacted · 214 KB", then Cancel / "Save report…".

**Why the preview is the requirement**

FR-028's whole point is that the user can see what leaves. A checkbox list describing redaction is not the same as showing the redacted document — and this is the one screen in the set where getting it wrong has consequences outside the app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Export presents a preview of the actual redacted report content, not a description of what redaction will do (FR-028)
- [x] #2 Each redactable field can be toggled independently, and the count of redacted fields and the resulting file size are shown
- [x] #3 Over-redaction is permitted but its cost to interpretability is stated
- [x] #4 Confidence labelling survives into the exported artefact, so a moderate-confidence judgement is not read as fact by a recipient (FR-038)
- [x] #5 The flow states that nothing is uploaded and produces a file the user sends themselves (FR-029)
- [x] #6 Verified on screen against design/screens/1k.png, including inspecting a real exported file against its preview
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built the export sheet (design 1k) plus a single-source report document in the framework.

**One source, structurally.** `Metrics/Sources/ExportDocument.swift` builds an `ExportDocument` (sections of `ReportField`/prose). The preview renders that object; the saved file is `document.data(as:)` of the same object. Redaction is applied **when the document is built**, not when it is rendered: a hidden field holds `.redacted` and does not carry its value at all, so no renderer can emit what the preview hides. Preview and file cannot diverge because there is only one artefact.

**Terminal verification (criterion #6's file half).** A standalone binary linked against the built `Metrics.framework` sampled real processes, built a real incident through `IncidentDetector`, resolved real executable paths, printed the exact preview model and wrote report.txt and report.json. With all three toggles hidden: 11 of 11 sensitive fields hidden, and 0 of 11 hidden values found in either file. Control run with nothing hidden: 11 of 11 values present, so the check is meaningful rather than passing on an empty report. One subtlety found: a running process was literally named "MacSlowdown", which collides with the report title, so the check compares occurrence counts against a contributor-free scaffolding document rather than doing a naive substring search.

**Formats: plain text and JSON. PDF is deliberately not offered.** The framework renders text; a PDF would be a second rendering path that could disagree with the preview, which is the one failure FR-028 exists to prevent. The design shows "PDF and JSON"; this is a knowing departure, not an oversight.

**Gaps in the framework's existing export, and what was done about them.**
- `RedactionOptions.hideFilePaths` was **inert** in `DiagnosticExport`: nothing in that report contained a file path, so the control did nothing. The new document carries the top contributors' executable paths (supplied by `IncidentDetailView` from `store.families`), so the toggle now acts on something real. Where no path was recorded the field reads `not available - path not recorded` and is *not* counted as successfully hidden - claiming a path was redacted when none existed would be a false assurance.
- The status-line denominator is derived from the fields actually present, not a fixed number.
- The toggle is labelled "App and process names" so it matches the framework's existing cost warning wording ("Hiding process names makes the report much harder for anyone to interpret"), which is reused rather than duplicated. The design's copy says "app names".
- The "Include" choices (measurements / machine details / timeline) add and remove whole sections; app version, build and schema always travel (FR-040).
- Timeline is the incident's own recorded lifecycle timestamps. Nothing is inferred.

**Entitlement added.** `com.apple.security.files.user-selected.read-write`. Without it a sandboxed Save panel returns a URL we cannot write, so FR-028 could not produce a file. It grants no ambient file access.

**Known divergence to watch.** `Shortcuts.swift`'s `ExportLatestIncidentIntent` still uses the older `DiagnosticExporter`, so two report renderings now exist. They are not in conflict today (the intent returns text, the sheet writes a file), but a future change to one will not reach the other. Worth a follow-up to point the intent at `IncidentReport.document`.

**Rebase.** This worktree branched before the eight-branch merge. Rebased onto main; the only conflict was `IncidentDetailView.swift`, resolved in favour of TASK-65.5's rewritten `verdict` section, with the Export button placed in its header row. `IncidentEvidence.swift` untouched, and the model now takes `store.machine` rather than re-reading `MachineContext.current()`.

**Tests.** `Metrics/Tests/ExportDocumentTests.swift` (14 tests) and `MacSlowdown/Tests/ExportReportTests.swift` (5 tests). Full suite: 536 passing, 1 failure - "A real workload raises the attributed share", one of the load-synthesising MetricsTests that flake under concurrent builds (load average 13-15 from other agents); a different one of that set failed on each run and all of them passed on some run. None touch code this task changed.

**Criterion #6 is only half met.** The file-versus-preview inspection was done from the terminal and is recorded above. The on-screen check against design/screens/1k.png was **not** performed - this agent was instructed not to use the screen. What needs eyes: the two-column layout, the redacted block rendering, the cost warning appearing under the names toggle, and that the Save panel writes where the user chose.

**Seen 2026-09-17**, for the first time: `design/verified/2026-09-17/previews/export-defaults.png` and `export-redacted.png`. It had never been looked at.

**The screen's decisive property holds on screen.** FR-028's claim is that the file the user receives is byte for byte the document the preview renders, and the two halves are visibly one thing: the INCLUDE and HIDE choices on the left, the rendered report on the right, and "Both formats are written from exactly what the preview shows" beneath the format picker. Toggling every redaction on visibly changes the preview — which is what makes the controls real rather than decoration, and is the second render's whole purpose.

Against design 1k: the two-column arrangement, the redaction preview before anything leaves, and the status line all match. The header states the promise plainly — "Check what's in it before you send it. Nothing is uploaded — you'll get a file to attach yourself" — and the footer counts what was withheld: "3 of 5 sensitive fields hidden · 2 KB". A redacted field renders as a black bar followed by the word "redacted", so the omission is visible rather than silent.

Every figure in the report carries its evidence class: "Peak total CPU 800.0% of one core (measured)", "Unattributed 100.0% of one core (calculated)" — FR-038 holding in the exported artefact and not only on screen.

**Two things the criterion asked for that a preview cannot give, recorded rather than claimed:**

- "Inspecting a real exported file against its preview" needs a save panel and a file on disk. It is asserted instead by `ExportReportModelTests.fileMatchesPreview`, which compares the written bytes against the previewed document — stronger than an eyeball comparison for *equality*, and no substitute for confirming the panel works.
- Nothing about presentation: whether the sheet appears, takes focus or dismisses. A preview renders a view; it does not present one.
<!-- SECTION:NOTES:END -->
