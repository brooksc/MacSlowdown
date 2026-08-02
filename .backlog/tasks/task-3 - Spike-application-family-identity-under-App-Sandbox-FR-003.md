---
id: TASK-3
title: 'Spike: application-family identity under App Sandbox (FR-003)'
status: Done
assignee: []
created_date: '2026-08-02 01:05'
updated_date: '2026-08-02 01:24'
labels:
  - m1-core-monitor
  - spike
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Last item that could force an architecture rewrite. FR-003 is Phase 1 scope and marked "Review required".

Questions:
1. Can we obtain bundle ID and team ID for an arbitrary PID while sandboxed? Candidates: SecCodeCreateWithPID, SecCodeCopyGuestWithAttributes(kSecGuestAttributePid) + SecCodeCopySigningInformation.
2. If not, does path-walking work? proc_pidpath succeeds for 1037/1058 pids INCLUDING other-uid, so walking up to the .app bundle may be viable.
3. Do helper processes group to their parent app? Helpers are often re-parented to launchd (spec open question).

If stable signed identity is unavailable, grouping degrades to path heuristics, which changes the §6 data model and FR-016 policy identity and FR-039 corrections.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Documented whether signed bundle/team identity is reachable sandboxed for arbitrary PIDs
- [x] #2 Browser/Electron helper fixtures verified to aggregate to their parent app (FR-003 acceptance criteria)
- [x] #3 Chosen identity scheme survives app update and PID reuse
- [x] #4 Findings appended to probe/FINDINGS.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
VERDICT: FR-003 is feasible sandboxed. No architecture rewrite needed.

Path is the primary anchor, code signature is enrichment:
- proc_pidpath: 1042/1063 sandboxed, IDENTICAL to unsandboxed, works other-uid
- SecCodeCopyGuestWithAttributes: 810/1063 sandboxed (1041 unsandboxed), and
  returns identity for 212/338 other-uid procs -- we can NAME processes whose
  CPU we cannot READ
- Outermost .app grouping works identically sandboxed: Helium 24 procs,
  ChatGPT 15, Dock 5, 1Password 4, Xcode 4

Three data-model consequences:
1. Signed bundle ID does NOT group -- helpers report their own identifier
   (net.imput.helium.helper.renderer), not the parent's. Group by outermost
   .app path; use the signature for identity and FR-016 policy stability.
2. Only ~15% of procs (154/1063) belong to an application family. Standalone
   daemons/CLI tools must be first-class in the section 6 model, not a
   family-of-one.
3. Identity costs ~760ms per full sweep, ~400x the 1.8ms metrics sweep. MUST be
   cached by (pid, start time), resolved once per process lifetime. This is the
   dominant cost in the system and shapes the sampler architecture.

FR-016 policy identity: teamID+bundleID is the stable key across app updates
where available; outermost .app path is the fallback. Record both.

Known false-grouping risk: ChatGPT.app absorbed node_repl and codex-code-mode
subprocesses whose executables live inside the bundle. Exactly the "labeled and
reversible" case FR-003 requires and FR-039 makes user-correctable.

Full detail in probe/FINDINGS.md.
<!-- SECTION:NOTES:END -->
