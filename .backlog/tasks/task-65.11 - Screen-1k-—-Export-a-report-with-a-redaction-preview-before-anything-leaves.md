---
id: TASK-65.11
title: 'Screen 1k — Export a report, with a redaction preview before anything leaves'
status: To Do
assignee: []
created_date: '2026-08-09 02:24'
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
- [ ] #1 Export presents a preview of the actual redacted report content, not a description of what redaction will do (FR-028)
- [ ] #2 Each redactable field can be toggled independently, and the count of redacted fields and the resulting file size are shown
- [ ] #3 Over-redaction is permitted but its cost to interpretability is stated
- [ ] #4 Confidence labelling survives into the exported artefact, so a moderate-confidence judgement is not read as fact by a recipient (FR-038)
- [ ] #5 The flow states that nothing is uploaded and produces a file the user sends themselves (FR-029)
- [ ] #6 Verified on screen against design/screens/1k.png, including inspecting a real exported file against its preview
<!-- AC:END -->
