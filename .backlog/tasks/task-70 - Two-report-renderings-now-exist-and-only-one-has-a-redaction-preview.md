---
id: TASK-70
title: 'Two report renderings now exist, and only one has a redaction preview'
status: To Do
assignee: []
created_date: '2026-08-09 05:17'
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
- [ ] #1 Every path that produces a report -- including the App Intent -- renders from the same document, so redaction cannot differ between them (FR-028)
- [ ] #2 The App Intent path either offers the same redaction choices or states plainly which fixed redaction it applies; it never produces a less redacted report than the interactive path without saying so
- [ ] #3 A test asserts that a field hidden by a given set of options is absent from the output of every path, not merely masked in one
- [ ] #4 The decision to omit PDF is confirmed or reversed deliberately, with the preview-divergence risk stated either way
- [ ] #5 The user-selected file entitlement is verified to work in a signed sandboxed build, and its scope is recorded
<!-- AC:END -->
