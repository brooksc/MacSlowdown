---
id: TASK-57
title: 'Human-meaningful process names and icons (FR-003, FR-013, FR-002)'
status: To Do
assignee: []
created_date: '2026-08-08 19:37'
updated_date: '2026-08-08 20:18'
labels:
  - ui
  - core
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two related problems, now with measurements behind them — see probe/FINDINGS.md, "Human-meaningful process names".

**The defect.** The menu bar popover lists contributors by `ProcessRecord.command`, which is `p_comm` truncated to 16 bytes by the kernel. Real rows read "Spotify Helper (" and "Helium Helper (R" — cut mid-word, with nothing to indicate anything was lost. The notification body has the same defect; the verified end-to-end alert read "bash is the largest measurable contributor" and was correct only because "bash" is short.

**The opportunity.** Measured sandboxed on macOS 27: reading an application's Info.plist from disk is NOT denied. 145 of 151 processes living in a `.app` yield CFBundleDisplayName or CFBundleName. Combined with NSRunningApplication.localizedName, 187 of 800 processes (23%) can carry a real name and 188 a real icon — with no entitlement beyond app-sandbox.

Resolution order the probe supports:
1. NSRunningApplication.localizedName — best, because it says what the process is as well as what it is called ("Apple Account (System Settings)").
2. Outermost .app Info.plist.
3. .appex Info.plist — rescues System Settings panes (AppleIDSettings becomes Apple Account) but sometimes yields names no better than the truncation, such as BiometricsAndPasswordSettingsAppIntentsExtension.
4. p_comm, labelled as truncated.

**The limit, and it is not ours to fix.** 237 processes remain fragments after every source — MTLCompilerServi, SetStoreUpdateSe, com.apple.CloudP. These are daemons and XPC services with no display name anywhere on disk; no API invents one. The reference tool handles this by not trying: it names real applications, shows WindowServer under its raw name, and rolls the rest into a single "macOS" row. Aggregating is the honest answer, and it has the same shape as FR-055's unattributed bucket — consider sharing it rather than listing hundreds of fragments.

**Cost.** This is filesystem work. Identity resolution already costs ~760ms per full sweep and is cached by (pid, start time); name resolution must join that cache and never touch the per-sweep hot path (FR-030).

**Trap.** NSWorkspace.icon(forFile:) never returns nil — it returns a generic icon. Compare against icon(forFileType: "public.executable") or the interface will claim an icon it does not have.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Popover, table and notification all show the same resolved name, never raw p_comm
- [ ] #2 Resolution order is NSRunningApplication, then .app Info.plist, then .appex, then p_comm
- [ ] #3 A name that falls through to p_comm at exactly 16 bytes is labelled as truncated rather than shown as if complete
- [ ] #4 Names and icons are cached by (pid, start time) with identity resolution, never resolved on the sampling path
- [ ] #5 FR-030 overhead is re-measured after the change and still inside budget
- [ ] #6 An icon is shown only when it is the real one, verified against the generic executable icon
- [ ] #7 Processes with no obtainable name are aggregated rather than listed as fragments
- [ ] #8 Tests cover a 16-byte command, a bundled app, an .appex, and a daemon with no name at all
<!-- AC:END -->
