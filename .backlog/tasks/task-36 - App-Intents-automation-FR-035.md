---
id: TASK-36
title: App Intents automation (FR-035)
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-03 06:37'
labels:
  - core
milestone: m-3
dependencies: []
priority: low
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Shortcuts.swift: ShowStatusIntent, MuteAlertsIntent, ExportLatestIncidentIntent, MacSlowdownShortcuts.

- AC#1 Commands are versioned. ShortcutsVersion.current is bumped when an intent's parameters or meaning change, so an existing shortcut keeps working or fails loudly rather than quietly doing something different.
- AC#2 Permission-aware and structured. Every intent returns a result with a dialog rather than throwing an opaque error, and each states what it could not do: no reading yet, not monitoring, no incidents to export, a non-positive mute duration. A shortcut can branch on those rather than just failing.

The scoping decision worth recording: the intents expose exactly what the interface exposes -- show status, mute, export -- and nothing more. There is no process-control intent because there is no process control. An automation surface offering more than the UI would be a way AROUND the FR-037 constraint rather than an extension of the product, and it is the kind of thing that would pass review once and look indefensible later.

Two honesty details carried through to automation:
- ShowStatus reports the unattributed share alongside total CPU. A status naming only what we can see would overstate how much we know (FR-055).
- ExportLatestIncident's dialog says how many fields were redacted and that nothing was sent, so an automated export cannot quietly become an automated disclosure (FR-028).

Not verified end to end in the Shortcuts app -- that needs the app installed and a screen session. The intents compile, are registered through AppShortcutsProvider, and their logic is straightforward store reads.
<!-- SECTION:NOTES:END -->
