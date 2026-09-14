---
id: TASK-45
title: Re-validate all Tier 0 findings on macOS 26
status: Done
assignee: []
created_date: '2026-08-02 01:19'
updated_date: '2026-09-14 19:41'
labels:
  - risk
  - spike
milestone: m-1
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A-01 requires macOS 26 AND 27. Every Tier 0 finding was measured on macOS 27.0 (26A5388g) only.

Sandbox profile behavior is exactly the kind of thing that differs across major releases. Specifically unverified on macOS 26:
- Whether sysctl KERN_PROC_ALL is permitted sandboxed (our entire enumeration strategy)
- Whether proc_listpids is denied there too
- Whether proc_pid_rusage is denied there too
- Whether the mach timebase and PROC_PIDTASKALLINFO layouts match

If sysctl enumeration is denied on macOS 26, the app cannot ship to that OS and A-01 needs a product decision.

Requires a macOS 26 VM or second machine -- not available on the current host.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 probe/build-sandboxed.sh run on macOS 26 and output captured
- [x] #2 Any divergence from macOS 27 recorded in probe/FINDINGS.md
- [x] #3 If enumeration differs, escalate as an A-01 scope decision
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PARKED: needs a macOS 26 machine or VM, which is not available on this host (running macOS 27.0, build 26A5388g). Cannot be verified here.

What must be re-checked when a macOS 26 environment exists, in priority order:
1. Whether sysctl KERN_PROC_ALL is permitted under App Sandbox. The entire enumeration strategy rests on it; if it is denied on macOS 26, the app cannot ship there and A-01 needs a product decision.
2. Whether proc_listpids is denied there too (expected, but unconfirmed).
3. Whether proc_pid_rusage is denied there too, which decides whether FR-009 per-process I/O and FR-043 footprint could be restored on that OS.
4. That the mach timebase and proc_taskinfo layout match, since the CPU maths depends on both.

probe/build-sandboxed.sh runs standalone with only swiftc and codesign, so it can be executed on a macOS 26 machine without setting up the full project.

2026-09-14 — **a macOS 26 environment now exists, and it is not enough.** GitHub Actions runs the full suite on `macos-26` on every push to main (`.github/workflows/tests.yml`). Run 34882840420 was green on macOS **26.6.2** (25G83), Xcode **26.6** (17F113), Swift **6.3.3** — 1311 tests, both bundles, which is the local 1317 minus exactly the 6 machine-sensitive tests CI skips.

What that does and does not settle:

- **Settles nothing on this task's acceptance criteria.** All three are about `probe/build-sandboxed.sh` against a signed `.app`, and **CI builds unsigned** — `CODE_SIGNING_ALLOWED=NO`, because the runner holds no Apple Development certificate and ad-hoc signing makes the app-hosted test bundle hang (entitlements apply, the sandbox then blocks the host app launching as a test host). So the four questions in the notes above — sysctl `KERN_PROC_ALL` permitted, `proc_listpids` denied, `proc_pid_rusage` denied, layouts matching — are all still **unanswered on 26**. Criteria stay unchecked.
- **Does settle** that the code compiles and the logic holds on the stable 26 toolchain, which is a different and much lesser claim. The engine, detector, attribution, gate, coverage record and all seven scenario suites behave identically on 26.6.2 and on final 27.
- **Changes the premise the parking rested on.** 'Requires a macOS 26 VM or second machine — not available on the current host' is no longer true of the *logic*. It remains true of the *sandbox*, which is the whole of this task. The unparking move is to get `probe/build-sandboxed.sh` to run on a 26 runner — it needs only `swiftc` + `codesign`, and ad-hoc signing may well suffice for a standalone probe binary, since the hang was specific to an XCTest host app. Worth one attempt before assuming a second machine is required.

The macOS 27 axis noted in CLAUDE.md is a separate question and is not touched by this.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
**No divergence. The enumeration strategy ships on both macOS 26 and 27.**

Answered 2026-09-14 on macOS **26.6.2** (25G83), Swift 6.3.3, ad-hoc signed, on a 3-core GitHub Actions runner — `.github/workflows/sandbox-probe.yml`, now a standing job. Output recorded in `probe/FINDINGS.md`.

The four questions, in the order the notes ranked them:

1. **`sysctl KERN_PROC_ALL` IS permitted under App Sandbox on 26** — 545 pids returned. This was the one that could have stopped the app shipping to 26; `decision-1` needs no escalation and A-01 needs no product decision.
2. **`proc_listpids` is denied on 26 too** — EPERM, as expected but never confirmed until now.
3. **`proc_pid_rusage` is self only on 26** — 1/545, EPERM×544. So FR-009 per-process I/O and FR-043 footprint are no more restorable on 26 than on 27; the aggregate-only narrowing stands on both.
4. **The mach timebase and `proc_taskinfo` layout match.** Checked by plausibility rather than by printing the timebase: CPU read 14–20% of one core for `mdworker_shared`, and a wrong timebase on Apple Silicon is off by about 42×, which would be unmissable.

**And the uid rule holds exactly**: 247 other-uid processes, exactly 247 denials, no exceptions in either direction — the same as 27 beta and 27 final. The measurability *percentage* is lower (54.7% against ~69%) and that is not a divergence: a runner runs proportionally more system daemons than a desktop, and the denials still account for every other-uid process.

**What this deliberately does not claim.** The runner is 26.6.2, not 26.0, and is a virtualised 3-core machine. It answers the sandbox-*policy* question, which is what was at risk. It says nothing about physical hardware, P/E core asymmetry, or thermals on 26. The signature is ad-hoc rather than a development certificate — established in `probe/FINDINGS.md` as valid for sandbox measurement, since the signature carries the entitlement and the sandbox is genuinely applied.

**Getting here required fixing the probe**, which had stopped running at all on final macOS 27: a sandboxed binary that reuses a bundle id whose container was created by a different code signature blocks forever in `_libsecinit_appsandbox` before `main`, printing nothing. That is written up in `probe/FINDINGS.md` and `CLAUDE.md`, and `probe/build-sandboxed.sh` now derives a per-signer, generation-scoped id. The same session also re-confirmed every Tier 0 fact on final macOS 27 (26A428), which closes the separate beta caveat CLAUDE.md was carrying.
<!-- SECTION:FINAL_SUMMARY:END -->
