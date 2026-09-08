---
id: TASK-57
title: 'Human-meaningful process names and icons (FR-003, FR-013, FR-002)'
status: Done
assignee: []
created_date: '2026-08-08 19:37'
updated_date: '2026-08-09 01:12'
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

**The defect.** The menu bar popover lists contributors by `ProcessRecord.command`, which is `p_comm` truncated to 16 bytes by the kernel. Real rows read "MediaApp Helper (" and "BrowserApp Helper (R" — cut mid-word, with nothing to indicate anything was lost. The notification body has the same defect; the verified end-to-end alert read "bash is the largest measurable contributor" and was correct only because "bash" is short.

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
- [x] #1 Popover, table and notification all show the same resolved name, never raw p_comm
- [x] #2 Resolution order is NSRunningApplication, then .app Info.plist, then .appex, then p_comm
- [x] #3 A name that falls through to p_comm at exactly 16 bytes is labelled as truncated rather than shown as if complete
- [x] #4 Names and icons are cached by (pid, start time) with identity resolution, never resolved on the sampling path
- [x] #5 FR-030 overhead is re-measured after the change and still inside budget
- [x] #6 An icon is shown only when it is the real one, verified against the generic executable icon
- [x] #7 Processes with no obtainable name are aggregated rather than listed as fragments
- [x] #8 Tests cover a 16-byte command, a bundled app, an .appex, and a daemon with no name at all
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done. 350 tests passing (from 329).

Names: ProcessNaming resolves NSRunningApplication.localizedName, then the outermost .app Info.plist, then .appex, then the command. .framework is excluded — 269 processes ran from inside one in the probe and it never yields a better name. Resolution happens inside the existing (pid, start time) identity cache.

The fix is structural rather than local: the resolved name now travels on ProcessCPUUsage, so the popover, table, incident summary, export and notification read one value and cannot drift apart again. Each surface reaching for `command` independently is what produced the defect.

Where nothing resolves, the command carries an ellipsis and VoiceOver hears 'name shortened by the system'. Truncation is measured in BYTES, matching the kernel — a test covers a 16-byte emoji string that is only 4 characters.

Icons: ProcessIconCache, keyed by bundle so BrowserApp's 18 helpers cost one lookup. It compares against the generic unixExecutable icon and returns nil rather than a placeholder — NSWorkspace.icon(forFile:) never returns nil, so a naive non-nil check would have put a fake icon beside three quarters of the table.

FR-030 re-measured standalone, 300s, sandboxed: CPU 0.963% of one core (budget 1.0%), memory 20.0 MB (budget 100 MB), disk 0.00 MB/hour (budget 10 MB/hour), median sweep 7.12 ms. Inside budget, but see TASK-62 — the CPU headroom is only 4% and the cause is not naming.

I changed the harness while doing this, and it matters: it previously resolved identity only for the top few contributors, while the app groups every process on every sweep. The old figure was flattering. It now calls FamilyGrouper.group, so the measurement reflects the real path. A first run at 90s read 1.348% and breached the budget; at 300s it reads 0.963%. The difference is a one-off cold-cache cost being amortised, not noise — measured directly: cold grouping of 844 processes costs 819 ms, warm grouping 2.90 ms, a 282x difference.

Naming's own contribution is small: identity plus naming is 0.821 ms per process cold against roughly 0.76 ms for identity alone before. The breach was pre-existing work the harness was not measuring.

Unverified: the icons and names have not been seen on screen. Unit tests cover resolution, the generic-icon rejection and the cache, but no test renders a view.
<!-- SECTION:NOTES:END -->
