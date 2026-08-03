---
id: TASK-33
title: Redactable diagnostic export (FR-028)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:26'
labels:
  - core
milestone: m-3
dependencies: []
priority: medium
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No transmission occurs automatically
- [ ] #2 Paths, usernames, process names can be redacted
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DiagnosticExport.swift: RedactionOptions, DiagnosticExport, DiagnosticExporter.

- AC#1 No transmission occurs automatically. Building a report writes nothing and sends nothing -- the type exposes text and byteCount and has no method that could save or send. Producing and delivering are separate steps and only the caller can perform the second.
- AC#2 File paths, usernames and process names can each be redacted. The important part, and the one easy to get wrong: process names appear inside PROSE findings as well as structured fields, so redaction reaches them there too. A test asserts the name does not survive anywhere in the text -- a name left in a finding would defeat the whole redaction.
- AC#3 The export records app version, build and schema version (FR-040), so a report stays interpretable after the app changes.

Every finding keeps its evidence class in the export ([measured], [calculated], heuristic with confidence), so a support recipient can weigh a hypothesis the same way the user could.

Defaults redact user name and file paths but NOT process names, because removing those makes a report nearly useless. Rather than silently choosing for the user, costWarning surfaces 'Hiding process names makes the report much harder for anyone to interpret' when they select it -- the cost is stated before sending rather than discovered after.
<!-- SECTION:NOTES:END -->
