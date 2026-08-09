---
id: TASK-70
title: 'Two report renderings now exist, and only one has a redaction preview'
status: Done
assignee: []
created_date: '2026-08-09 05:17'
updated_date: '2026-08-09 06:37'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-65.11 while building the export sheet, and flagged by it as a divergence to watch.

TASK-65.11 added `Metrics/Sources/ExportDocument.swift`, where redaction happens when the document is **built** rather than when it is rendered: a hidden field holds `.redacted` and does not carry its value at all, so no renderer could emit what the preview hides. The preview and the saved file are the same object, and a terminal check confirmed 11 of 11 sensitive values absent from both output formats when hidden, against a control showing 11 of 11 present when not.

**`Shortcuts.swift`'s `ExportLatestIncidentIntent` still uses the old `DiagnosticExporter`.** So there are now two ways to produce a report, and only one of them has the structural guarantee. They are not in conflict today, but the App Intent path is exactly where a user is least able to inspect what is produced — it runs unattended, from a shortcut, possibly into another app.

FR-028's purpose is that the user can see what leaves. A second path without the preview quietly reintroduces the risk the first path was built to remove.

Two other things recorded by that task, worth keeping with it:

- **`RedactionOptions.hideFilePaths` was inert** in `DiagnosticExport` — that report contained no file paths, so the control did nothing. The new document carries contributors' executable paths so the toggle acts on something real, and where no path was recorded the field reads "not available — path not recorded" and is **not** counted as successfully hidden.
- **PDF is deliberately not offered.** A PDF would be a second rendering path that could disagree with the preview, which is the failure FR-028 exists to prevent. Plain text and JSON are offered, both from the document. This is a knowing departure from design 1k and should be confirmed rather than silently inherited.
- **An entitlement was added**: `com.apple.security.files.user-selected.read-write`, without which a sandboxed Save panel hands back a URL we cannot write. It grants no ambient access, but entitlements are where App Review rejections cluster, so it should be understood rather than discovered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every path that produces a report -- including the App Intent -- renders from the same document, so redaction cannot differ between them (FR-028)
- [x] #2 The App Intent path either offers the same redaction choices or states plainly which fixed redaction it applies; it never produces a less redacted report than the interactive path without saying so
- [x] #3 A test asserts that a field hidden by a given set of options is absent from the output of every path, not merely masked in one
- [x] #4 The decision to omit PDF is confirmed or reversed deliberately, with the preview-divergence risk stated either way
- [ ] #5 The user-selected file entitlement is verified to work in a signed sandboxed build, and its scope is recorded
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Done.** Every report-producing path now renders `ExportDocument`, and the second renderer is deleted rather than left dormant.

**What changed**

- `Metrics/Sources/DiagnosticExport.swift` → `RedactionOptions.swift`. `DiagnosticExport` and `DiagnosticExporter` are **removed**. A renderer nothing calls is still a renderer waiting to be called, and leaving it would have preserved exactly the divergence this task exists to close. `RedactionOptions` survives, plus `hiddenFieldNames` / `includedFieldNames` / `fieldsLeftInComparedTo(_:)` / `isAtLeastAsRedacted(as:)` / `disclosure` / `weakerThanDefaultWarning` — the vocabulary a path uses when it must *state* redaction instead of showing it.
- `IncidentReport.contributorPaths(in:)` moved path-gathering next to the builder, so the "File paths" toggle cannot act on a different set of paths in two reports of the same incident.
- `Shortcuts.swift`: `ExportLatestIncidentIntent` builds through `UnattendedIncidentReport.make` → `IncidentReport.document`. It offers the same three redaction toggles and a format choice; AppIntents demands literal defaults, so `declaredDefaults` restates them and a test asserts `declaredDefaults == RedactionOptions.default`.
- `ExportDocument.json` now encodes with `.withoutEscapingSlashes` — see the trap below.

**What the App Intent does about choices it cannot ask for**

It offers them, with the sheet's defaults, and *says* what it did. The dialog reads: any weakening warning **first**, then "Hidden: …; included: …", then "n of m sensitive fields hidden, N bytes. Nothing was sent anywhere.", then the cost warning if names were hidden. Turning a toggle off is allowed — doing it silently is not, so a report less redacted than `RedactionOptions.default` opens with "This report is less redacted than MacSlowdown's default, which also hides …". Tested, including that the values really are in the text it hands over, so the warning is not theoretical.

**Verification, to the TASK-65.11 standard** — `probe/Sources/export-paths-probe.swift`, sandboxed, built against the shipping `Metrics` sources. Real load, real incident from the real `IncidentDetector` (CPU saturation, peak 100%, opened and closed), 732 processes, 662 families, 503 contributors. Ten actually-sensitive values (the operator's user name, five contributor names, four executable paths) searched in files **written to disk** by both paths in both formats:

```
hidden:  40 of 40 sensitive values absent when hidden
control: 40 of 40 present when nothing is hidden
bytes:   8 of 8 renderings identical across both paths
```

The run contained a live process named `MacSlowdown`, the same collision TASK-65.11 hit, so occurrences are counted against a contributor-free scaffold document rather than tested for a bare substring.

**A real hole this found:** `JSONEncoder` escapes forward slashes by default, so a path is written `\/Users\/…` and *any* check that the raw path is absent from the JSON passes while the path is present. The old JSON absence assertions were weaker than they looked. Encoding is now `.withoutEscapingSlashes`; the control assertion is what caught it. Recorded in `probe/FINDINGS.md`.

**Tests:** 679 passing, 0 failing (baseline 670; +16 new, −7 with the deleted exporter). `EndToEndIncidentTests.realSlowdownProducesOneIncident` failed on a first, busy run and passed in isolation — the documented load-sensitive case, not a regression.

**#4 PDF — confirmed, not inherited.** PDF stays unoffered. It would be a rendering the preview cannot produce, so the preview would become a claim about the file rather than a view of it — the one failure FR-028 exists to prevent. A knowing departure from design 1k. Reversing it later is only safe if the PDF is generated *from `ExportDocument`* and a test asserts its content agrees with the other renderings. `ReportFormat.unofferedFormatsExplanation` states the position in the interface, and `formatsMapOntoTheDocument` pins `allCases.count == 2`.

**#5 entitlement — left unchecked, deliberately.** Scope recorded: `com.apple.security.files.user-selected.read-write` extends the sandbox to exactly the file the user picks in the Save panel, via Powerbox, only at the moment they pick it. No ambient file access. Read-write rather than read-only because we write. Only the interactive sheet needs it — the App Intent returns text and touches no file. Verified from the terminal that a **Release** build signs with exactly two entitlements (`app-sandbox`, `files.user-selected.read-write`) and none of Xcode's injected debug ones, so `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` in `Project.swift` is doing its job. **Not verified: that the Save panel round-trip actually writes.** That needs a person at the screen, and I did not use it.

**For a human**

1. Run the Save panel once in a signed sandboxed build and check a file appears where you chose (criterion #5).
2. `IncidentDetailView.contributorPaths` (off-limits here — TASK-68 owns that area) still computes the paths dictionary inline. It is equivalent to `IncidentReport.contributorPaths(in:)` and the parity tests use the shared one, but whoever next edits that file should swap it so there is one implementation rather than two that happen to agree.
3. `CLAUDE.md` still says 670 passing; it is 679 after this. Left alone to avoid colliding with the other agents in this session.
<!-- SECTION:NOTES:END -->
