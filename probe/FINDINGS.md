# Tier 0 sandbox feasibility findings

**Date:** August 1, 2026
**Host:** macOS 27.0 (build 26A5388g), Apple M2 (4P + 4E, 8 logical), Swift 6.4
**Method:** identical Swift binary run (a) unsandboxed and (b) inside a signed
`.app` whose only entitlement is `com.apple.security.app-sandbox`. Built with
`swiftc` + `codesign` only — see `build-sandboxed.sh`. The sandbox is applied at
exec from the code signature, so running the inner binary from a terminal is
genuinely sandboxed (confirmed: `NSHomeDirectory()` returns the container path).

**Verdict: GO.** Per-process CPU and memory are reachable from a sandboxed Mac
App Store app, at full parity with unsandboxed for own-uid processes. The naive
enumeration API is blocked, but a working alternative exists. Three requirements
lose their per-process dimension and must be rescoped.

---

## Capability matrix

| Capability | API | Unsandboxed | Sandboxed | Cost | Verdict |
|---|---|---|---|---|---|
| Process enumeration | `proc_listpids` | 1052 pids | **0 — EPERM** | — | **Blocked** |
| Process enumeration | `sysctl KERN_PROC_ALL` | 1061 | **1058** | ~1.5 ms | **Use this** |
| Process identity (pid, comm, uid, ppid, start) | `kinfo_proc` | ✓ | ✓ all pids | incl. above | Available |
| Per-process CPU time | `proc_pidinfo(PROC_PIDTASKINFO)` | 714/1052 | **720/1058** | ~0.3 ms/400 | Available, own-uid only |
| Per-process resident memory | `pti_resident_size` | ✓ | ✓ own-uid | incl. above | Available |
| bsdinfo + taskinfo in one call | `PROC_PIDTASKALLINFO` | ✓ | **400/400** | 1 syscall | Prefer — halves syscalls |
| Executable path | `proc_pidpath` | 1031/1052 | **1037/1058** | ~5 ms full sweep | Available, incl. other-uid |
| Memory **footprint** | `proc_pid_rusage.ri_phys_footprint` | 714/1052 | **1/1058 (self only)** | — | **Blocked** |
| Per-process disk I/O | `proc_pid_rusage.ri_diskio_*` | ✓ | **Blocked** | — | **Blocked** |
| Per-process wakeups | `proc_pid_rusage.ri_interrupt_wkups` | ✓ | **Blocked** | — | **Blocked** |
| GUI app + bundle identity | `NSRunningApplication` | 119 apps | **119, 113 w/ bundleID** | trivial | Available |
| Aggregate CPU | `host_processor_info` | ✓ | ✓ | trivial | Available |
| Memory pressure / VM stats | `host_statistics64(HOST_VM_INFO64)` | ✓ | ✓ | trivial | Available |
| Swap usage | `sysctl vm.swapusage` | ✓ | ✓ | trivial | Available |
| Thermal state / low power | `ProcessInfo` | ✓ | ✓ | trivial | Available |
| Storage capacity | `URLResourceValues` | ✓ | ✓ | trivial | Available |

Own-uid is the ceiling in **both** modes: 720 of 1058 processes. The other 338
are root/system-owned and denied with `EPERM` even unsandboxed as a normal user.
**The sandbox costs us nothing on process coverage** — only `proc_pid_rusage`.

## Accuracy validation

- **CPU:** synthetic single- and dual-core spinners read **100.0% / 100.0%**
  against `ps` **100.0 / 99.9**. Sandboxed spinner: **97.1%**.
- **Memory:** sandboxed `pti_resident_size` **37.1 MB / 107.7 MB** vs `ps rss`
  **37.0 MB / 103.4 MB** (second process sampled seconds apart). Sandboxed and
  unsandboxed values are byte-identical.

## Two bugs found that would have shipped

1. **CPU times are mach ticks, not nanoseconds.** `pti_total_user`,
   `pti_total_system`, `ri_user_time`, `ri_system_time` are all in mach absolute
   time units. On Apple Silicon the timebase is 125/3 (41.667 ns/tick), so
   treating them as nanoseconds under-reports CPU by ~42×. On Intel the timebase
   is 1:1, which is why much published sample code omits the conversion. Always
   scale by `mach_timebase_info`.
2. **`proc_pid_rusage`'s pointer convention is a trap.** The signature is
   `int proc_pid_rusage(int, int, rusage_info_t *)` where `rusage_info_t` is
   itself `void *`. The kernel writes to `buffer`, **not** `*buffer`. Passing the
   address of a pointer variable (the natural Swift reading) writes 296–464 bytes
   onto the stack and aborts. Rebind the struct's own address to the parameter type.

Also worth knowing: `Duration.components.attoseconds` is only the sub-second
remainder — the whole seconds live in `.seconds`. Using attoseconds alone
silently truncates any duration ≥ 1 s.

## Overhead (FR-030: ≤1% of one core)

| Sweep contents | Cost | 1 s cadence | 2 s cadence |
|---|---|---|---|
| sysctl + `PROC_PIDTASKINFO` only | **1.8 ms** | 0.18% | 0.09% |
| + `proc_pidpath` + failing `rusage` calls | 17.6 ms | 1.76% ✗ | 0.88% |

Comfortably within budget **if** paths are cached by `(pid, start time)` rather
than re-read every sweep, and the 1057 doomed `rusage` calls are dropped. The
naive "call everything every sweep" approach breaks the budget at 1 s cadence.

## Consequences for requirements

**Rescope — per-process dimension is unavailable sandboxed:**

- **FR-009** (disk I/O): aggregate only. Per-process I/O deltas are not
  obtainable. The spec already permits "may omit per-process detail in restricted
  builds" — take that path.
- **FR-048** (wakeups): drop for the MAS release. The spec's own instruction is
  to omit rather than approximate.
- **FR-043** (family memory): must use **resident size**, not phys_footprint.
  Note that Activity Monitor's "Memory" column shows footprint, so our numbers
  will legitimately differ from it — this needs explicit labeling per FR-002 and
  FR-036, and it resolves the §10 open question "which memory metric is primary"
  by elimination.

**Unaffected:** FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008,
FR-010, FR-041, FR-042, FR-045, FR-047, FR-049 and the whole incident model.

**Still unproven:** FR-019 (audio), FR-046 (unresponsiveness), FR-051 (network),
FR-052 (GPU). Not tested here; all remain Tier 3.

## Attribution gap: what we are blind to

The binding limit is not the sandbox — it is **uid**. Processes owned by other
users are denied identically whether sandboxed or not. Verified byte-identical
across both modes: `WindowServer` (uid 88), `mds`/`mds_stores` (0/308),
`backupd` (0), `coreaudiod` (202), `syspolicyd` (0), `launchd` (0), `hidd` (261)
are all DENIED. Only user-owned workers (`mdworker_shared`, `photoanalysisd`,
`bird`, `cloudd` at uid 501) are visible.

Measured share of busy CPU that cannot be attributed to any visible process:

| Mode | Denied procs | Unattributed CPU |
|---|---|---|
| Sandboxed (MAS) | 338 / 1058 | **53.1%** |
| Unsandboxed, same user | 338 / 1058 | (same coverage) |
| **root** | **0** | **12.9%** |

The 12.9% under root is this measurement's noise floor, not a permission limit:
processes that start or exit mid-window have no baseline sample and are skipped.
So the permission-driven blind spot is roughly **40 percentage points** of busy
CPU, and the 53% figure is an upper bound. The two runs were taken at different
machine loads (27.3% vs 16.1%), so this is directional rather than a controlled
comparison.

Practical consequence: attribution is strong for user-application slowdowns
(a synthetic spinner reads 100.0%) and absent for system-driven ones — Spotlight
indexing, Time Machine, WindowServer, audio. Those are common real causes of
unexplained slowdowns, so this is a headline-promise gap, not a footnote.

Design implication: surface **"unattributed system activity"** as a first-class,
labeled category rather than letting contributor lists silently fail to sum.
This is what FR-038 evidence classification and FR-013 confidence labeling are
for. Note also that Activity Monitor shows this data via a privileged helper
(`sysmond`), so users will compare and notice the difference.

## Capability by distribution tier

| Capability | MAS (sandboxed) | Developer ID, unsandboxed | Developer ID + root helper |
|---|---|---|---|
| Enumeration, own-uid CPU + RSS | ✅ 720/1058 | ✅ same 720 | ✅ all |
| Memory footprint (FR-043) | ❌ | ✅ | ✅ |
| Per-process disk I/O (FR-009) | ❌ | ✅ | ✅ |
| Per-process wakeups (FR-048) | ❌ | ✅ | ✅ |
| System procs (WindowServer, mds, backupd) | ❌ | ❌ | ✅ |
| Process control (FR-020–024) | ❌ | ❌ | ✅ |

**Unsandboxing alone does not close the attribution gap** — it only restores
`proc_pid_rusage`. The gap closes only at the root tier, which is exactly what
FR-037 defers and marks Escalated. This supports the existing MAS-first decision:
the middle tier is a metrics upgrade, not a different product.

## Open risk: App Review

`proc_listpids` is explicitly denied under the sandbox and Apple DTS has stated
plainly that **no entitlement lifts it** ([Apple Developer Forums](https://developer.apple.com/forums/thread/691857)).
`sysctl KERN_PROC_ALL` is a separately-gated operation that empirically works,
and is a widely-used public API — but there is **no authoritative Apple statement
blessing it as the sanctioned alternative**, and no public precedent found either
way for a monitoring app shipping on the Mac App Store this way.

The realistic risk is not the API call — it is whether a reviewer reads
"enumerate the process table after the designated API was denied" as working
around the sandbox. Rejections in this area cluster around *entitlement*
requests, and we request none. Still, this is the single largest unretired risk
in the project and it cannot be settled by testing.

**Recommendation:** open a DTS incident or Developer Forums question before
building Phase 1 on this foundation. A wrong answer here invalidates the
architecture, and it is far cheaper to ask now than at submission.

## Reproducing

```sh
./build-sandboxed.sh ./build          # signed, sandboxed .app
./build/Probe.app/Contents/MacOS/Probe

swiftc -O -o /tmp/probe Sources/main.swift   # unsandboxed control
/tmp/probe
```

`IDENTITY=...` overrides the signing identity.
