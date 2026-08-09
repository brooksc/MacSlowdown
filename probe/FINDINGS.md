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

## TASK-3: application-family identity (FR-003)

**Verdict: FR-003 is feasible sandboxed.** Path is the primary anchor; code
signature is enrichment, not the foundation.

| Identity source | Unsandboxed | Sandboxed | Notes |
|---|---|---|---|
| `proc_pidpath` | 1042/1063 | **1042/1063** | Unaffected by sandbox; works other-uid |
| Outermost `.app` from path | 153/1063 | **154/1063** | Only ~15% of procs live in a bundle |
| Code signature bundle ID | 1041/1063 | **810/1063** | 231 lost to EPERM under sandbox |
| Code signature team ID | 75/1063 | **67/1063** | Third-party only; Apple binaries have none |
| `NSRunningApplication` | 119 apps | 119 apps | GUI only, no helpers |

`SecCodeCopyGuestWithAttributes(kSecGuestAttributePid)` **works sandboxed** and
returns identity for 212/338 *other-uid* processes — i.e. we can name processes
whose CPU we cannot read. Failures decode as `kPOSIXErrorBase` (100000) plus
errno: `100001` = EPERM (231), `100002` = ENOENT (21, exited), `100013` = EACCES.

**Helper grouping works, and works identically sandboxed.** Grouping by
outermost `.app` in the executable path:

```
Helium.app      -> 24 processes    1Password.app -> 4
ChatGPT.app     -> 15 processes    Xcode-beta.app -> 4
Dock.app        ->  5 processes    XProtect.app  -> 4
```

### Three consequences for the data model

1. **The signed bundle ID does NOT group.** Helpers report their own identifier
   (`net.imput.helium.helper.renderer`), not the parent's (`net.imput.helium`).
   Grouping must key on the outermost `.app` path, not the signature. Use the
   signature for *identity* and policy stability, the path for *family*.
2. **Application-family covers only ~15% of processes.** 154/1063 live inside a
   `.app`; the rest are daemons and CLI tools with no family. The §6 data model
   must treat "standalone process" as a first-class case, not a degenerate
   family-of-one.
3. **Identity resolution costs 760 ms per full sweep** — roughly 400x the 1.8 ms
   metrics sweep. It MUST be cached by `(pid, start time)` and resolved once per
   process lifetime. Never per-sweep. This is the dominant cost in the system.

### Policy identity across app updates (FR-016)

Where a signature is available, `teamID + bundleID` is the stable key and
survives app updates and path changes. Where it is not (Apple platform binaries,
231 sandboxed denials), fall back to the outermost `.app` path. Both must be
recorded so a policy can survive one source becoming unavailable.

### Known false-grouping risk

`ChatGPT.app` absorbed 15 processes including `node_repl` and
`codex-code-mode-*` — subprocesses whose executables live inside the bundle.
Attributing them to ChatGPT is arguably correct but not certain. This is exactly
the case FR-003 requires to be "labeled and reversible", and FR-039 to be
user-correctable.

## TASK-27: application unresponsiveness (FR-046) — NOT AVAILABLE

Measured sandboxed, launched via `open`:

| Route | Result |
|---|---|
| `NSRunningApplication` | No responsiveness state at all. Exposes `isActive`, `isHidden`, `isTerminated`, `ownsMenuBar`, `activationPolicy` — **a beachballing app reports identically to a healthy one**. |
| Accessibility API | `AXIsProcessTrusted` = false. Sandboxed apps cannot obtain it. |
| System hang reports | `/Library/Logs/DiagnosticReports` **unreadable**. `~/Library/...` redirects into our own container, so the real directory is unreachable even by path. |
| Process lifecycle (`sysctl`) | **Available** — name, pid, ppid, start time for every process. |

**A hang that does not exit is undetectable.** There is no public signal for it, and
the system's own hang detector writes somewhere the sandbox cannot read.

**FR-046 is partially satisfiable.** The requirement reads "publicly observable
unresponsive state, **repeated relaunch**, or similar failure signals", so the
relaunch half is deliverable: repeated exit-and-restart is fully visible through
lifecycle tracking. Direct hang detection is not, and per the spec's own
instruction the app must omit it rather than approximate.

**Design implication:** screen 1f's "Final Cut Pro stopped responding" cannot be
detected. The nearest honest equivalent is "Final Cut Pro quit and relaunched
three times", which is a different — and narrower — claim.

## TASK-28: audio activity (FR-019) — AVAILABLE, per-process

Better than the spec assumed. `kAudioHardwarePropertyProcessObjectList` (macOS
14.2+) works sandboxed with **no microphone permission and no entitlement beyond
`app-sandbox`**.

Verified by playing audio and re-measuring, so this is not a zero-reading
mistaken for a working API:

```
idle:     28 objects, 0 running,  DeviceIsRunningSomewhere = 0
playing:  28 objects, 1 running,  DeviceIsRunningSomewhere = 1
          ACTIVE: afplay [26397] running=1 input=0 output=1
```

Per audio process we get the pid — resolvable to a name — plus
`kAudioProcessPropertyIsRunning`, `IsRunningInput` and `IsRunningOutput`. The
input/output split matters: **output** covers playback, **input** covers
microphone use, which is what "don't interrupt a call" needs.
`kAudioDevicePropertyDeviceIsRunningSomewhere` gives a device-level fallback.

**Caveat:** output was verified against real playback; **input was not**.
Triggering it would mean starting a microphone capture on the user's machine.
The property is read identically, so the risk is low, but it is unverified.

FR-019 can therefore be implemented fully rather than "omitted if not reliably
available", and its Medium-High confidence rating can be raised.

## Aggregate disk I/O via IOKit — AVAILABLE sandboxed

Not covered by Tier 0; verified separately for FR-009. Measured in a signed,
sandboxed `.app` launched via `open`:

```
IOServiceGetMatchingServices  kr=0
devices=3  bytesRead=1701567834112  bytesWritten=761366163456
```

`IOBlockStorageDriver` statistics are readable with no entitlement beyond
`app-sandbox`, so machine-wide disk throughput is available. Per-process I/O
remains unavailable (`proc_pid_rusage` is denied), which is why FR-009 was
narrowed to aggregate-only in spec v1.2.

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

---

# Human-meaningful process names (`name-probe.swift`)

Prompted by a real defect: the popover showed `Spotify Helper (` and
`Helium Helper (R`, which are `p_comm` truncated to 16 bytes by the kernel, and
by the observation that iStat Menus shows `Cheetah3D` and `Safari` with icons.

Measured on macOS 27.0 (26A5388g), signed and sandboxed with
`com.apple.security.app-sandbox` and nothing else. 800 processes.

## The headline: bundle metadata is readable under the sandbox

**Reading an application's `Info.plist` from disk is not denied.** 145 of 151
processes living in a `.app` yielded a display name; 5 were denied and 1 had no
usable key. This was the open question — the sandbox restricts writes and
user-data reads far more than it restricts reading installed application
bundles — and the answer is that `CFBundleDisplayName` / `CFBundleName` are
available for essentially every app we can see.

| Source | Processes | Share of table |
|---|---|---|
| `proc_pidpath` | 776 | 97% |
| Inside a `.app` | 151 | 19% |
| `NSRunningApplication.localizedName` | 110 | 14% |
| `Info.plist` display name (`.app` only) | 145 | 18% |
| **Either source** | **187** | **23%** |
| Icon available (real, not the generic one) | 188 | 24% |

Widening to every bundle type raises the count only modestly:

| Bundle kind | Processes | |
|---|---|---|
| `.framework` | 269 | almost never yields a useful name |
| `.app` | 140 | |
| `.appex` | 48 | yields names, but often internal ones |
| `.bundle` | 2 | |
| **Named from any bundle kind** | **183** | 23% |

`.appex` adds real value for System Settings panes — `AppleIDSettings` becomes
`Apple Account`, `ClassroomSetting` becomes `Classroom` — but also produces
names no better than the truncation they replace, such as
`BiometricsAndPasswordSettingsAppIntentsExtension`. Prefer
`NSRunningApplication` where both exist: it returned
`Apple Account (System Settings)`, which says what the process *is* as well as
what it is called.

## What this does and does not fix

345 processes have a `p_comm` at or near the 16-byte limit. Of those, **108 are
rescued** by a friendly name; **237 remain fragments** — `MTLCompilerServi`,
`SetStoreUpdateSe`, `iCloudNotificati`, `com.apple.CloudP`.

That is not a gap in our technique. Those processes are Unix daemons and XPC
services with no display name anywhere on disk; there is no API that invents
one, and neither does any other tool. The reference interface handles exactly
this by not trying: it names real applications, shows `WindowServer` under its
own raw name, and rolls everything else into a single `macOS` row.

**Design consequence.** The ceiling for friendly naming is roughly a quarter of
the process table, and that quarter is the part users recognise. The remainder
should be aggregated rather than listed under fragments — which is the same
shape as FR-055's unattributed-activity bucket, and should probably share it.

## Rules

- Resolve names in this order: `NSRunningApplication.localizedName`, then the
  outermost `.app` `Info.plist`, then `.appex`, then `p_comm`.
- Cache by `(pid, start time)` alongside the existing identity resolution. This
  is filesystem work and must never run on the per-sweep hot path.
- A name that falls through to `p_comm` at exactly 16 bytes is **known
  truncated**. Label it as such (FR-002) rather than presenting the fragment as
  though it were the name.
- `NSWorkspace.icon(forFile:)` never returns nil — it returns a generic icon.
  Compare against `icon(forFileType: "public.executable")` or the interface will
  claim an icon it does not have.

## Reproducing

```sh
swiftc -O -o build/NameProbe.app/Contents/MacOS/NameProbe Sources/name-probe.swift
codesign --force --sign "$IDENTITY" --entitlements Probe.entitlements \
  --options runtime --timestamp=none build/NameProbe.app
./build/NameProbe.app/Contents/MacOS/NameProbe
```

## How iStat Menus actually does it (researched, not measured)

Worth recording, because the reference interface looks like a counter-example to
several of our conclusions and is not one.

iStat Menus ships in **two editions**. The Mac App Store edition is sandboxed
like ours. Bjango's own documentation for it says: *"It can not control fan
speeds. The iStat Menus Helper is needed to view some stats."*

That Helper is **downloaded separately from `download.bjango.com`, not from the
App Store**, and runs outside the sandbox. Temperatures, fan speeds and CPU
frequency in the MAS edition come from it — not from the sandboxed app.

So the market leader confirms our boundary rather than contradicting it. It
reaches sensor data by asking the user to install a separate unsandboxed binary,
which is precisely the privileged-helper pattern A-03, A-04 and FR-037 forbid us.
Fan *control* is unavailable in the MAS edition even with the Helper installed.

**Trap:** the App Store listing copy advertises the full sensor feature set,
including "Fan speeds can be controlled." That text is carried over from the
direct edition and contradicts Bjango's own help pages. A competitor's store
listing is not evidence of sandboxed capability.

**One lead worth probing.** GPU *utilisation* may be separable from GPU
temperature and frequency: another Mac App Store monitor claims to read Apple
Silicon GPU utilisation through the public `IOAccelerator` API with no private
API and no elevated privileges, while explicitly omitting temperature and fans.
Single-vendor self-description, unverified here — see TASK-59.

## Parent PID as a grouping signal (`parent-probe.swift`)

Asked directly: can `ppid` group processes instead of, or better than, the
executable path? Measured sandboxed, 831 processes.

**It cannot replace path grouping. 82% of the table is parented by launchd.**

| | Processes |
|---|---|
| Parent is launchd or the kernel — `ppid` says nothing | 683 (82%) |
| Parent is a live, identifiable process | 148 (18%) |
| Parent had already exited | 0 |

macOS launches most helpers through launchd and XPC rather than by forking from
the application, so for four processes in five the parent is pid 1. Restricted
to processes living inside a `.app`:

| Of 166 bundled processes | |
|---|---|
| Parent is launchd, `ppid` uninformative | 107 (64%) |
| Parent is in the same bundle — `ppid` agrees with the path | 56 (34%) |
| Parent is in a *different* bundle | 1 |
| Parent is in no bundle | 2 |

**But it adds two things the path cannot.**

1. **Corroboration.** For the 56 where the parent is in the same bundle, `ppid`
   independently confirms what the path claims. That is exactly the evidence
   needed to promote a member from `.uncertain` to `.certain` and stop showing
   the uncertainty marker for it.

2. **Attribution the path misses entirely.** 25 processes live in no bundle but
   were spawned by an application: 14 `zsh` under Warp, 11 `backlog` under
   ChatGPT, `chrome-native-ho` under Helium. Today each is a standalone
   family — a Warp session with fourteen shells appears as fourteen unrelated
   rows. `ppid` attributes them to the application responsible.

The one disagreement is instructive rather than alarming: `SkyComputerUseSe`
runs from `Codex Computer Use.app` but was spawned by ChatGPT. Both answers are
defensible, which is what "uncertain" is for.

**PID reuse.** `ppid` is a bare pid with no start time, so a recycled parent pid
would link a process to an unrelated one. No impossible parents were observed in
this snapshot, but the hazard is real over time and the guard is cheap: a real
parent must have started **before** its child. Reject any parent whose start
time is later.

**Rule.** Use `ppid` as corroboration and as a fallback for unbundled processes,
never as the primary key. Validate every parent link against start time.

## PID recycling is not hypothetical (measured, same machine)

`pid_t` is 32-bit, but macOS does not use the range: allocation wraps at
**99999**. That is a ~100k space, not 2^31.

On this machine, uptime 12 days:

- Highest live pid: **99763**
- A freshly spawned process: **45952**

The counter has **already wrapped at least once** and is reallocating from low
numbers while long-lived processes still hold pids near the top. Recycling is
not a rare theoretical hazard here; it is the current state of the machine.

This is why identity is `(pid, start time)` everywhere, and why any use of
`ppid` must reject a parent whose start time is later than its child's. The
guard costs one comparison.

## Measurability is decided by uid, exactly (`uid-probe.swift`)

828 processes:

| | Processes | Denied |
|---|---|---|
| Our uid | 599 | **0** |
| Every other uid (root and 38 service accounts) | 229 | **229** |

The correlation is total. Not one process of ours was denied, and not one
process of another uid was readable. There is no grey area to reason about: a
"System processes" grouping keyed on `uid != getuid()` is exactly the set we
cannot measure, with no false members either way.

**"Parented by launchd" is a different and much larger set — do not conflate
them.** 690 processes are launchd-parented, and **464 of those are ours and
fully measurable**. Launchd parentage says nothing about whether we can read a
process; only uid does.

## Can the unattributed total be assigned to those processes?

Partly, and the distinction matters (FR-038).

The total is already computed by subtraction — `host busy − sum of what we
measured` — and that subtraction is a **measurement**, not an estimate. What it
contains is the open part: other-uid process time, kernel and interrupt time,
and any short-lived process that started and exited between samples.

So the honest claim is "this much activity was not attributable, and these 229
processes were running during the interval" — which is what the interface says
today. What must never happen is assigning a share of it to any individual
process. The 229 can be **named and counted**, never **measured**.

# GPU utilisation IS available sandboxed (`gpu-probe.swift`) — FR-052

Measured on macOS 27.0, Apple M2, signed and sandboxed with only
`com.apple.security.app-sandbox`. FR-052 had been heading toward being dropped
alongside the sensor-class signals. That would have been wrong.

**One `IOAccelerator` service is readable: `AGXAcceleratorG14G`.** Its
`PerformanceStatistics` dictionary exposes:

```
Alloc system memory, Allocated PB Size, Device Utilization %,
In use system memory, In use system memory (driver), Renderer Utilization %,
SplitSceneCount, TiledSceneBytes, Tiler Utilization %,
lastRecoveryTime, recoveryCount
```

**The figure responds to real work.** Verified against a Metal compute load, not
a zero reading — a number that never moves proves nothing:

| | Readings |
|---|---|
| Before load | 0, 9, 31, 68, 16, 36, 39, 41 |
| Under load | 97, 98, 98, 98, 98, 95, 98, 98, 98, 97, 98, 98, 98, 98, 98, 98 |

**Read the baseline honestly: the machine was not idle.** Ordinary window
compositing produced readings up to 68%, so a *single* sample cannot distinguish
real GPU work from a busy desktop. What distinguishes them is persistence — the
load pinned the figure at 97–98% for four seconds, which incidental compositing
never did. That is the same sustained-not-transient rule the incident detector
already applies (FR-006), and FR-052 must be built on it rather than on
instantaneous values.

**What is not there, confirmed by enumerating every key:**

- **No temperature.** No key in any service contains "temp".
- **No frequency or clock.** No key contains "freq" or "clock".
- **Nothing per-process.** No pid, process or client key exists. This is
  **machine-wide only**, and claiming per-application GPU attribution from it
  would be a fabrication.

This is exactly the boundary seen everywhere else: utilisation is public
registry data; temperature and frequency are SMC-class and need the external
helper the Mac App Store edition of iStat Menus asks users to install.

**Cost: 2.54 ms per read**, mean of 20. That is *more than the entire per-process
metrics sweep* (1.8 ms), because each read matches services afresh and builds a
full property dictionary. At a 2 s cadence it is ~0.13% of one core, which fits
FR-030 — but the service handle must be looked up once and retained, not
re-matched every sample.

## Rules

- FR-052 is deliverable in the MAS build, scoped to **machine-wide utilisation
  only**. Never per-application.
- Report it only as a sustained condition, never from a single sample. Idle
  desktops read as high as 68%.
- Match the `IOAccelerator` service once and hold the handle. Re-matching per
  sample costs more than everything else we measure combined.
- `Device Utilization %` is the headline; `Renderer Utilization %` and
  `Tiler Utilization %` are available if a breakdown is ever wanted.
- GPU temperature and frequency remain unavailable and must not be implied.

## The overhead harness was measuring the wrong thing

Found while re-measuring FR-030 after adding friendly names.

`OverheadHarness` resolved identity only for the top few contributors, but the
app calls `FamilyGrouper.group` on **every** sweep, which resolves identity for
every process in the table. The harness was measuring a cheaper loop than the
one that ships. It now calls `FamilyGrouper.group`, so the figure reflects the
real path.

The corrected figure exposes a cliff:

| | Cost |
|---|---|
| Cold grouping, 844 processes, first sighting | **819 ms** |
| Warm grouping, everything cached | **2.90 ms** |
| Sampler sweep alone | 2.03 ms |
| Identity + naming, per process, cold | 0.821 ms |

**282× between the first sweep and every one after it.** That one-off dominates
any short measurement:

| Run length | CPU, % of one core | Budget |
|---|---|---|
| 90 s | **1.348%** | OVER |
| 300 s | 0.963% | OK, 4% headroom |

Same code, same machine. A number that moves that much with run length is not a
number to rely on — see TASK-62.

**Naming was not the cause.** Identity plus naming costs 0.821 ms per process
against roughly 0.76 ms for identity alone; the signature call dominates. The
breach was pre-existing work the harness had never measured.

**Rule: an overhead harness must exercise the path the app actually runs.** A
harness that samples a cheaper loop reports a budget nobody is held to, and it
will report success right up until a user notices.

## Test-host flakiness worth recognising

The app-hosted `MacSlowdownTests` bundle occasionally fails to launch under load:

```
MacSlowdown (91102) encountered an error (Early unexpected exit, operation never
finished bootstrapping - no restart will be attempted.)
```

Observed once while the machine was busy; an immediate re-run passed with all
350 tests. This is the test runner failing to bootstrap, not a product defect —
`MetricsTests` completes normally in the same run. Re-run before investigating.

## The code signature is 94% of identity resolution (`split-probe.swift`)

Cold pass over 801 processes, sandboxed:

| Step | Total | Per process |
|---|---|---|
| `proc_pidpath` | 2.5 ms | 0.003 ms |
| **Code signature** | **773.9 ms** | **0.966 ms** |
| Naming (Launch Services + `Info.plist`) | 18.7 ms | 0.023 ms |

Naming, which was the suspect, is 2% of the cost. The signature is 94%.

**The signature only decides how confident a family membership is**, and that
classification runs solely for processes inside a `.app`. About 85% of the table
is standalone, where membership is trivially certain because the process is its
own family. Paying for a signature there buys nothing.

Skipping it for non-bundled processes took a cold pass from **819 ms to 244 ms**.

Consequence to know about: a standalone process now has no `bundleID`, so an
application policy keyed on bundle identifier will not match one. Policies match
on display name in that case. Resolve a signature on demand if a policy ever
needs one for a daemon.

## Steady-state cost per sweep (`sweep-probe.swift`)

Everything cached, 2 s cadence:

| | ms |
|---|---|
| `ProcessSampler.snapshot` | 2.77 |
| `FamilyGrouper.group` | 1.86 |
| Attribution (with naming) | 0.56 |
| `PowerSignals.current` | 0.33 |
| `DiskSignals.counters` | 0.29 |
| `history.record` | 0.27 |
| `resolver.prune` | 0.22 |
| `LifecycleTracker.events` | 0.21 |
| Everything else | <0.05 each |
| **Total** | **6.61 ms → 0.33% of one core** |

## FR-030 is a *median*, so measure a median

The harness reported a mean over the whole run, which folded process launch and
the first-sighting pass into the figure. The same build read **1.348% over 90 s**
and **0.963% over 300 s** — the number described how long you watched.

It now reports steady state separately, and judges the budget on that, while
keeping the whole-run figure and the startup cost visible so nothing is hidden:

| Run | Steady state | Whole run | Startup |
|---|---|---|---|
| 90 s | 0.836% | 1.019% | 203 ms |
| 300 s | 0.887% | 0.946% | 216 ms |

Steady state now agrees to within 0.05 points across run lengths, which is what
makes it a figure worth holding anyone to.

**Rule: judge a budget on the statistic the requirement names.** Averaging a
one-off startup cost into an idle median measures the observer, not the app.

## Two probe traps worth not repeating

- **`String(format: "%-20s", (name as NSString).utf8String!)` crashes.** The
  temporary `NSString` is released before the format reads the pointer. Pad in
  Swift with `padding(toLength:withPad:startingAt:)` instead.
- Compile probes against `Metrics/Sources/*.swift` directly when they need
  internal API. Widening `public` to satisfy a probe puts test-only surface in
  the shipping framework.

## An executable's file name is not always a name (`version-name-probe.swift`)

The inventory showed four rows called `2.1.220` and one called `com.apple.Safari…`
(TASK-57.1). Neither came from a fallback taking a path component, which was the
hypothesis. Both came from the *file name of the executable itself*.

**Claude Code installs one binary per version and names the file after the
version.** `~/.local/bin/claude` is a symlink to
`~/.local/share/claude/versions/2.1.226`, so `proc_pidpath` returns that path,
`p_comm` is `2.1.226`, and nothing else on disk carries a name — no `.app`, no
`.appex`, no Launch Services registration. Eight processes were running under
four version numbers on the measured machine. The command was the correct answer
by every rule we had; the rule was wrong.

The Safari row is the same shape from the other end: `p_comm` cut at 16 bytes
made `com.apple.Safari.History` read as `com.apple.Safari…`, which a user reads
as Safari. **The executable file name is not truncated**, so the path recovers
the whole identifier — 29 processes were showing a cut-off reverse-DNS fragment.

**A declared name can also be an identifier.** `PressAndHold.app` declares
`CFBundleName` = `com.apple.PressAndHold`, and `CoreSimulatorService` registers
with Launch Services under its own identifier. Having a source for a string does
not make the string a name, so the check has to sit after the declared name, not
only on the path fallback.

**Rules.**

- Treat a bare version number and a reverse-DNS identifier as *non-names*
  wherever they come from — Launch Services, `Info.plist`, or `p_comm`. Show
  them as `Unidentified process (…)` with the evidence beside the label, never
  as the application's name (FR-002, FR-038).
- Where the executable is version-named, the directory above it names the
  program: `.../claude/versions/2.1.226` is `claude`. Search **at most two**
  levels and skip structural components (`bin`, `versions`, `Contents`, …).
  Never accept a directory directly under `/Users` or `/home` — that is an
  account name, and it is not a process name (A-05).
- Only members that live *inside* a bundle may name the family. A spawned member
  carries its own name, and members arrive in dictionary order, so any-member
  naming made the row's title depend on that order.

Measured after the change: 0 of 797 processes still display a version or a bare
identifier; all eight `claude` processes resolve to `claude`.

---

# Our own memory: resident size is the wrong number for FR-030 (TASK-55.1)

**Date:** August 8, 2026 · macOS 27.0 (26A5388g), M2, 8 logical cores
**Probes:** `Sources/self-memory-probe.swift` (built with `build-probe.sh`),
`memlog.sh` and `footprintlog.sh` against the running app.

TASK-55.1 opened on three readings taken minutes apart from the running Debug
app — 418.4 MB and 307.4 MB on the Now screen's `MacSlowdown itself:` line, and
2.26 GB on the Apps & Processes row — against TASK-55's closing figure of 92 MB
and FR-030's 100 MB budget.

## The two surfaces never disagreed. Resident size is just unstable.

Both surfaces read `pti_resident_size`, from the same sweep. Nothing in the code
makes them differ for a one-process family, and nothing was found that does.

What differs is *when*. Over a 755 s log of the running app, resident size read
**3321 MB**, then fell to **884 MB in about ten seconds** without the app doing
anything, and held at **809–874 MB** for the remaining 555 s. Over the same
window `phys_footprint` never moved: **396 MB** before the fall, 396 MB after.

`vmmap` explains it. 3.0 GB of the 3.3 GB resident total was mapped files under
`/Library/Caches/com.apple.iconservices.store/*.isdata` — 3012 regions of the
system icon store, clean, shared and file-backed. The kernel evicts those for
free the moment anything else wants the pages, which is exactly what happened.

**Rule: resident size is not a cost you are charged for.** It counts clean shared
file-backed pages that cost nothing to drop. Two honest readings of our own
resident size can differ by 2.5 GB minutes apart. Quoting one as *the* memory
figure — on either surface — reports the machine's page cache, not our footprint.

`phys_footprint` is the stable number, and it is the one Activity Monitor shows.
We cannot read it for other processes (`proc_pid_rusage` is self-only, see above),
which is why FR-043 reports resident size for *them*. For **ourselves** it is
readable, and it is the only figure a budget can be held against.

Long-run figures for the running Debug app, 1191 s:

| Statistic | Resident size | phys_footprint |
|---|---|---|
| Range over the run | 809 – 3323 MB | 218 – 397 MB |
| Median after t=150 s | 837 MB | **292 MB** |
| Trend | flat after eviction | flat, two discrete steps |

Steady, not climbing. The steps up (291 → 327 MB) coincide with new applications
being sighted for the first time; between them the figure is flat to ±2 MB over
17 minutes. That is a fixed cost per newly-seen application, not unbounded growth
— it is **not** evidence of a leak, and must not be described as one (FR-044).

## Where the 292 MB goes: `NSImage.tiffRepresentation` costs 70 MB per icon

`ProcessIconCache` decides whether an icon is real or a generic placeholder by
comparing `candidate.tiffRepresentation` against the generic icon's. FR-002
requires that distinction. The comparison is what costs.

Measured by `self-memory-probe`, sandboxed, 117 naming bundles on this machine —
each stage in its own process so one cannot contaminate the next:

| Stage | Resident | phys_footprint |
|---|---|---|
| `sysctl KERN_PROC_ALL`, 808 pids | +0.6 MB | +0.6 MB |
| `proc_pidpath`, 775 paths | +0.2 MB | +0.3 MB |
| `Info.plist` names, 113/117 | +2.3 MB | +1.2 MB |
| `NSWorkspace.runningApplications` | +0.5 MB | +0.2 MB |
| **one** `icon(for: .unixExecutable).tiffRepresentation` | **+196 MB** | **+148 MB** |
| 117 × `icon(forFile:)`, pooled, images retained | +18.5 MB | **+5.9 MB** |
| 117 × `tiffRepresentation`, pooled | +1698 MB | +1693 MB |
| 117 × the app's exact sequence, unpooled | +7017 MB | +7958 MB |

`tiffRepresentation` of an icon from IconServices is **70 MB**. The image carries
representations to 1024×1024 across every scale, and asking for TIFF flattens all
of them into one contiguous `Data`. Doing it 117 times moves ~8 GB through malloc.

Two things follow that are easy to get backwards:

- **Holding the icons is nearly free.** Retaining all 117 `NSImage`s costs 5.9 MB
  of footprint, and rasterising them at 16 pt adds 2.5 MB. The cache is not the
  problem; the equality test performed once per cache miss is.
- **Draining the autorelease pool does not give it back**, and neither does
  releasing the cache — measured, not assumed. Pooling each call cuts the peak
  from 8109 MB to 1843 MB, but 1.8 GB stays resident in malloc's large-block
  free list. `vmmap` on the running app shows the same shape: a
  `Malloc Large (empty)` region of 320 MB virtual, 103 MB resident. The app's
  292 MB steady footprint is largely this high-water mark, not live objects.

## A 32 pt rasterised comparison is equivalent and costs 0.17 MB

Draw both icons into a 32×32 RGBA bitmap and compare the PNG bytes. Measured over
the same 117 bundles:

| Method | Agrees with `tiffRepresentation` | Footprint cost |
|---|---|---|
| `NSImage.name()` | **0/117 — does not discriminate** | +0.03 MB |
| 32 pt rasterised comparison | **117/117** | **+0.17 MB** |

All 117 bundles classified as "real", so agreement alone would also be scored by
a method that always answers "real". The negative control settles it: for
`/bin/ls` and `/usr/bin/true` both methods answer *generic*, and for a
non-existent path both answer *real* (IconServices returns the generic **document**
icon there, which is not the unix-executable icon either method compares against).
The cheap method discriminates; it is not just agreeing by accident.

## Landed, and re-measured against the shipping code

`ProcessIconCache` now compares 32 pt fingerprints. `icon-cost-probe.swift` is
compiled together with `Metrics/Sources` (see `build-with-metrics.sh`) so it runs
the shipping class rather than a copy that could drift; its `before` arm
reproduces the old comparison over the same bundles.

Each arm runs in its own process — malloc does not return large blocks promptly,
so measuring both in one process charges the second for the first's high-water
mark. Three consecutive pairs, 105 bundles classified in every run:

| Pair | Before, footprint growth | After, footprint growth | Before, peak | After, peak |
|---|---|---|---|---|
| 1 | +5659.1 MB | **+8.6 MB** | 7779.4 MB | **11.3 MB** |
| 2 | +8555.4 MB | **+7.7 MB** | 8593.3 MB | **10.4 MB** |
| 3 | +8552.4 MB | **+8.2 MB** | 8590.3 MB | **10.8 MB** |

Roughly **700× less**, and the peak now sits inside FR-030's 100 MB budget where
it previously exceeded it by 85×.

Correctness held: an `agree` arm running both classifications over the same 105
bundles in one process reports **0 disagreements**, and the negative control
(`/bin/ls`, `/usr/bin/true`, `/usr/sbin/notifyd`) comes back *generic* under both.
That control is the one that matters — every bundle on this machine classifies as
real, so zero disagreements alone would also be scored by a comparison that never
says "generic". It is kept in `Metrics/Tests/ProcessNamingTests.swift` rather than
only in the probe, because a comparison that drifts into always answering "real"
would put a placeholder beside three quarters of the table and call it the
application's icon — worse than the allocation it replaced (FR-002).

**Not yet measured: the running app.** The probe shows the icon path's cost fell
from ~8.5 GB to ~8 MB, but whether the app's 292 MB median footprint drops below
100 MB can only be confirmed by watching the running app, which needs the screen.
Treat the app-level figure as unverified until someone looks.

## The headless harness was never wrong, it was answering a different question

`probe/overhead/run.sh 300` on the same machine, same day:

```
sweeps: 145 over 302.0s
cpu:    0.830% of one core steady state (budget 1.0%) OK
memory: 20.7 MB resident, +13.0 MB growth (budget 100 MB) OK
disk:   0.00 MB/hour projected (budget 10 MB/hour) OK
```

20.7 MB is the true cost of the sampling path. The gap to the app's 292 MB is
AppKit, SwiftUI and the icon comparison above — none of which the harness links.
Both numbers are honest; FR-030's budget applies to the second.

## What is still unmeasured

The **Release** build has not been measured, and neither has a freshly launched
app. Both require putting a menu bar item on screen, which needs the user
present. TASK-55's 92 MB is consistent with a reading taken before the inventory
had been opened — the icon cost is incurred per application *first displayed*, so
a launched-but-unbrowsed app legitimately reads far lower than one that has shown
the full process table. That is a hypothesis fitting the evidence, not a
measurement.

**Rule for the next person: measure our own memory as `phys_footprint`, over at
least 300 s, and say which build and which screens were opened.** A figure without
those three qualifiers is not comparable to any other figure.

## Every report-producing path renders the same document (TASK-70)

`probe/Sources/export-paths-probe.swift`, sandboxed, on real data: 732 processes,
662 families, a real CPU-saturation incident opened and closed by the real
`IncidentDetector` (peak 100%), 503 contributors. Ten genuinely sensitive values
— the operator's user name, five contributor names, four executable paths —
searched in files written to disk by both report-producing paths in both formats:

```
hidden:  40 of 40 sensitive values absent when hidden
control: 40 of 40 present when nothing is hidden
bytes:   8 of 8 renderings identical across both paths
```

Two rules worth keeping:

- **Count occurrences against a contributor-free baseline, never test for a bare
  substring.** This run had a live process literally named `MacSlowdown`, and the
  report's own scaffolding says "MacSlowdown" in its title — a naive
  `!text.contains(name)` would have failed on a correctly redacted file. The same
  collision bit TASK-65.11.
- **`JSONEncoder` escapes forward slashes unless you ask it not to.** A path is
  written `\/Users\/…`, so a check that the raw path is absent from the JSON
  passes *while the path is present*. `ExportDocument` now encodes with
  `.withoutEscapingSlashes` so redaction is verifiable by reading the file. Any
  future absence check over JSON must confirm its control finds the value.
