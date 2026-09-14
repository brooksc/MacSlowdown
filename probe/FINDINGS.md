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
BrowserApp.app  -> 24 processes    VaultApp.app   -> 4
AssistantApp.app-> 15 processes    Xcode-beta.app -> 4
Dock.app        ->  5 processes    XProtect.app   -> 4
```

*(Third-party application names are generalised throughout this document. The
counts are the measured ones; only the names are stand-ins, because a real
process inventory identifies the machine it came from — which is the same
reason FR-029 will not transmit one.)*

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

One assistant application absorbed 15 processes, including a bundled
JavaScript runtime and several helper executables shipped inside it —
subprocesses whose executables live in the bundle. Attributing them to the
application is arguably correct but not certain. This is exactly
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

Prompted by a real defect: the popover showed `MediaApp Helper (` and
`BrowserApp Helper (R`, which are `p_comm` truncated to 16 bytes by the kernel, and
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
   were spawned by an application: 14 `zsh` under TerminalApp, 11 `backlog` under
   AssistantApp, `chrome-native-ho` under BrowserApp. Today each is a standalone
   family — a TerminalApp session with fourteen shells appears as fourteen unrelated
   rows. `ppid` attributes them to the application responsible.

The one disagreement is instructive rather than alarming: `AssistantHelperSv`
runs from `AssistantHelper.app` but was spawned by AssistantApp. Both answers are
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
## SwiftUI's `Table` reenters its own `NSTableView` delegate when rows reorder

The running app logs this every ~2 s, from the Apps table (TASK-67):

```
WARNING: Application performed a reentrant operation in its NSTableView delegate.
This warning will become an assert in the future.
```

The string is AppKit's, extracted from the shared cache at
`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`. Note the path: the
copies under `/System/Library/dyld/` are listed by `ls` but cannot be opened.

**Reproduced without the screen**, in `MacSlowdown/Tests/`: the real view in an
`NSHostingView` inside an offscreen `NSWindow`, driven by the real `MonitorStore`
at a 1 s cadence, with fd 2 redirected to a pipe. AppKit emits this through
`NSLog`, so stderr catches it; it is *not* in `log show`.

Two traps, both hit while writing it:

- **A nested `RunLoop.run(until:)` does not drive the store.** The first harness
  looked correct, ran 57 layout passes, and reported a clean log — because the
  sampling task never got a turn, so the table held **zero rows** the entire time.
  Use an `async` test and `await Task.sleep`, which yields to the app's own run
  loop. Always assert the table was populated and did change, or a clean result
  means only that nothing happened.
- `xcodebuild` does not pass the shell environment to the test process. Gate a
  probe on `TEST_RUNNER_FOO=1`, which arrives as `FOO`.

**What reenters: row reordering, and nothing else we could find.** Measured over
8–25 s windows against one live store (warnings per run):

| Variant | Warnings |
|---|---|
| Frozen rows, never changed | 0 |
| New array each sample, identical rows | 0 |
| Same identities, changing values, fixed order | 0 |
| Rows rotated by **one** position each sample | 0 |
| Rows **shuffled** each sample — identical ids *and* values | **21** |
| 15 rows, re-sorted each sample | **6** |
| The shipping Apps table | **13–16** |

The shuffle control is the decisive one: identities, values and count are all
identical between updates and only the order differs. A single row moving is not
enough; a bulk reorder always is. Row count is irrelevant — 15 rows reordering
warns.

**Ruled out, each by its own variant.** None of these is the cause, and none of
them fixes it: the `sortOrder` binding; the selection binding; sortable
`TableColumn(value:)`; `DisclosureTableRow` (TASK-61); icons in the cell body;
the `safeAreaInset` footer; the `onChange` per-family history recording
(TASK-65.4); `.searchable`; `Section` in the rows builder; the data-driven
`Table(data)` initialiser; `.transaction { $0.disablesAnimations = true }`;
duplicate row identities (there are none — 0 in 743 flattened rows); and adding
`Equatable` to `InventoryRow`. So it is not TASK-56, -60, -61, -65.4 or -65.13:
those only change how much work each update does.

**Both tables are susceptible; only one triggers it.** Shuffling
`AllProcessesRow` warns 21 times, exactly like the Apps rows — the row type is
irrelevant. The All processes table measured **0 warnings across five 25 s runs**
because, as composed, its order does not really move: nearly every one of its
~720 rows ties at zero CPU and is held in place by the name tie-break, while the
Apps table's ~425 family rows carry aggregated CPU that jitters, so ranks swap on
every sample.

**Beware the obvious metric.** Counting rows whose *absolute index* changed
reported ~700 of 721 rows "moved" when a single process appearing at the top had
shifted everything below it by one. Compare rank within the ids common to both
orderings instead.

**No fix was made.** This is SwiftUI's `Table`, not our code, and every
workaround tried either did not work or is not ours to choose. The options, for
the product owner:

- **Accept it and file a Feedback.** It is noise today; AppKit says it becomes an
  assert, which would be a crash in a shipping build on some future macOS.
- **Stop re-sorting every sample** — hold the order and re-rank on a slower beat,
  or only when a rank changes materially. Reduces the frequency (a sample that
  moves nothing warns not at all) but does not eliminate it, and it is a
  behaviour change, not a bug fix.
- **Replace `Table` with `NSTableView` behind `NSViewRepresentable`**, where the
  update batching is ours. The only option that removes the reentrant call, and
  it means rebuilding sorting, disclosure, selection and accessibility by hand.
- **Rejected: making row identity encode position.** It would avoid the move path
  by replacing every row instead, and it would destroy selection and expansion
  stability across samples, which FR-027 requires.

Re-run the evidence with:

```
TEST_RUNNER_TASK67_PROBE=1 xcodebuild test -workspace MacSlowdown.xcworkspace \
  -scheme AllTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build \
  -only-testing:MacSlowdownTests/InventoryTableBisectProbe
```

### Damping the order cuts the warning ~85% (TASK-74)

The product owner took the second option. The displayed order is now held
between samples and re-ranked at most once every 10 s
(`MacSlowdown/Sources/StableOrder.swift`); rows that appear or disappear are
spliced in and out immediately, and a sort click or a search re-ranks at once.
**Only positions are held — every refresh emits the newest sample's rows**, so a
held order never puts a stale number on screen (FR-002, FR-032).

Measured with TASK-67's own harness, 20 s windows, 1 s cadence, ~500 rows, on a
machine also running other agents' builds:

| | warnings per 20 s |
|---|---|
| Before — re-ranked every sample | 12, 14 |
| After — order settled at 10 s | 2, 2, 1 |

That is roughly the arithmetic you would predict: a 20 s window permits about two
re-ranks instead of twenty, and each reorder costs one warning. **The reentrancy
is not fixed** — SwiftUI still reenters whenever rows genuinely move — so the
Feedback (drafted in `probe/feedback-swiftui-table-reentrancy.md`) still matters,
and `NSViewRepresentable` is still the only complete escape.

Re-run with:

```
TEST_RUNNER_TASK67_PROBE=1 xcodebuild test -workspace MacSlowdown.xcworkspace \
  -scheme AllTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build \
  -only-testing:MacSlowdownTests/InventoryTableReentrancyTests
```

---

# Per-application network attribution (`net-probe.swift`) — FR-051, TASK-40

**Verdict: per-process network attribution is NOT available to a sandboxed Mac
App Store build.** Aggregate, machine-wide throughput *is*, with no entitlement
beyond `app-sandbox`. The backlog's suspicion was right about the destination
and wrong about the reason: the private `NetworkStatistics` framework is not
merely off-limits by policy, it is **blocked by the sandbox at runtime**, and
the public per-process route (`libproc` socket descriptors) never carried byte
counters in the first place.

Measured on macOS 27 / M2 with `probe/run-net-probe.sh 6`, which drives a
verified loopback transfer (256 MB payload, local HTTP server, `curl` loop;
the script asserts `200 268435456` before sampling) across the window and reads
every counter twice. Sandboxed run is a signed `.app` launched with `open`,
entitlements = `com.apple.security.app-sandbox` only — **no**
`com.apple.security.network.client`, **no** NetworkExtension entitlement.

## What each route yields

| Route | Unsandboxed | Sandboxed | Carries per-process bytes? |
|---|---|---|---|
| `getifaddrs` + `struct if_data` | 26/46 entries have `if_data` | **26/46, identical** | No — per *interface* |
| `sysctl NET_RT_IFLIST2` + `if_msghdr2`/`if_data64` | 12736 B, 138 messages, 26 interfaces | **identical** | No — per *interface* |
| `libproc` `PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO` | **445/447 own-uid pids**, 523 socket FDs, 523/523 socket infos | **1/447 — self only**, 649 × EPERM, **0 sockets** | No — see below |
| `sysctl net.inet.{tcp,udp}.pcblist[_n]` | **48 bytes** (header, zero entries) | **48 bytes** | No entries at all |
| `NWPathMonitor` | `satisfied`, interfaces, expensive/constrained | identical | No counter of any kind in the API |
| exec `/usr/bin/nettop` | exit 0, 37 lines of `bytes_in,bytes_out` | **exit 70, `nettop: NStatManagerCreate failed`** | n/a — private framework |

Counts are from one representative run; the process table held 647–650 pids
(447 own-uid, 203 other-uid).

## The four things worth remembering

**1. `libproc` socket enumeration is one of the few places the sandbox itself is
the limit.** Everywhere else measured in this project, own-uid works and
other-uid is denied identically sandboxed and unsandboxed. Not here:
unsandboxed we get an FD list for **445 of 447** own-uid processes; sandboxed we
get **1 of 447** — our own — and 649 EPERM. So the "measurability is decided by
uid, exactly" rule does **not** generalise to file descriptors.

**2. It would not have helped anyway.** `struct socket_info`
(`sys/proc_info.h`) carries `soi_type`, `soi_protocol`, `soi_family`,
`soi_state` and `soi_rcv`/`soi_snd` (`sockbuf_info`). `sbi_cc` is **current
queue occupancy, not a cumulative counter**; there is no rx/tx byte or packet
total in the struct. Unsandboxed, under a transfer of hundreds of MB, `curl`
showed `1 socket, 196608 queued_B` — a queue depth, which cannot be
differenced into a rate. The one externalised socket struct that *is* public,
`struct xsocket` in `sys/socketvar.h`, likewise has occupancy and `so_uid` and
no byte totals and no pid.

**3. The kernel PCB tables are empty for a non-root user, sandbox or not.**
`net.inet.tcp.pcblist_n` returns **48 bytes** — the generation header with zero
socket entries — from the probe, and `sysctl -b net.inet.tcp.pcblist_n | wc -c`
returns 48 from a plain terminal too. Corroborated by `netstat -an` as a normal
user on macOS 27: it prints the UNIX-domain section and **zero Internet
connections**. Even if the table were populated, decoding it means hardcoding
kernel-private ABI: `xinpgen`, `xsocket_n`, `xsockstat_n` and `xtcpcb_n` are
**not in the public SDK** (zero hits for `pcblist` or `xsocket_n` across
`MacOSX.sdk/usr/include`).

**4. Aggregate interface counters wrap at 2^32 — including the "64-bit" ones.**
Measured, not inferred. During a 3.9 GB/6 s loopback transfer, `lo0` read
`before=1688087552 after=1281142784` through **`if_data64.ifi_ibytes`**, a
`u_int64_t` field. The kernel's loopback statistic is 32-bit-wide underneath, so
`NET_RT_IFLIST2` does not save you from wrap; a naive subtraction produces
1.8×10^19. `if_data.ifi_ibytes` (route 1) is declared `u_int32_t` and wraps for
the same reason. **Any FR-051 implementation must detect a counter that ran
backwards and correct modulo 2^32**, and must not present the corrected figure
without saying so.

## `nettop` and NetworkStatistics

`otool -L /usr/bin/nettop` shows it links
`/System/Library/PrivateFrameworks/NetworkStatistics.framework`. Nothing here
links or `dlopen`s it. The probe only *executes* `nettop`, because "shell out to
the system tool" is the workaround someone eventually proposes, and it should be
refused on evidence. It fails from inside the sandbox: **`NStatManagerCreate
failed`, exit 70**, while succeeding with 37 rows unsandboxed. So the private
route is closed by the sandbox as well as by App Review.

## NetworkExtension (researched, not measured)

`NEFilterDataProvider` **would** deliver what FR-051 asks for: on macOS
`NEFilterFlow.sourceAppAuditToken` identifies the originating process and
`handleInboundDataFromFlow:readBytesStartOffset:` / `handleOutboundData...`
give byte offsets per flow. The cost is the entitlement
**`com.apple.developer.networking.networkextension`**, value
`content-filter-provider` (app-extension packaging, App Store) or
`content-filter-provider-systemextension` (Developer ID). It is a restricted
entitlement granted only on request for stated use cases, and Apple DTS's
guidance (TN3134) is that a *distributed* macOS content filter must be
configured by an MDM configuration profile rather than by the app. A
general-purpose diagnostic utility is not a case Apple grants this for, and
building on it would put the whole product behind an approval we do not have.
**Treat this as a "no" with the entitlement named**, not as an option.

## Consequence for FR-051

Aggregate-only, exactly as FR-009 was scoped to aggregate-only for disk. What an
aggregate-only FR-051 can honestly say:

- machine-wide bytes in/out per second, per interface, from a delta of
  `if_data64` with wrap correction;
- which interface carried it (Wi-Fi, Ethernet, loopback, VPN `utun*`), and
  `NWPath`'s expensive/constrained flags;
- that sustained transfer coincided in time with an incident.

What it can **never** say, and must not imply:

- which application or process the bytes belonged to;
- how much any one app transferred;
- anything about latency — throughput is not latency, and FR-051 already says so.

Per-process attribution must therefore be reported as **explicitly unavailable**
in the UI, the same way other-uid CPU is surfaced as unattributed system
activity. Loopback deserves its own note: `lo0` carried 3.9 GB in 6 s here from
one local file transfer, so folding it into a single "network" figure would make
purely local traffic look like a WAN transfer.

## Reproducing

```sh
./run-net-probe.sh 6        # builds both, drives the load, prints both reports
```

The sandboxed report is written to
`~/Library/Containers/com.brooksc.MacSlowdown.Probe.net-probe/Data/net-probe-result.txt`.
The script kills the load generators by pattern as well as by pid: an orphaned
`python3 -m http.server` holding the port makes the next run measure a stream of
404s while appearing to have run under load. That happened once, and the
sandboxed pass under-reported by three orders of magnitude before the load check
was added.

# Crash vs. normal exit (`exit-status-probe.swift`) — FR-046

**Verdict: no.** A sandboxed Mac App Store build cannot tell a process that
crashed from one that exited normally, for any process it did not itself fork.
The exit *event* is available and is better than what we do today; the exit
*status* is not.

This is the question behind TASK-84 — `yes`, `swift-frontend` and
`mdworker_shared` disappearing is ordinary churn, and `LifecycleTracker` infers
those exits from a `(pid, start time)` vanishing between two
`sysctl KERN_PROC_ALL` snapshots, which carries no status at all.

Measured on macOS 27.0 (26A5388g) / M2, unsandboxed and in a signed sandboxed
`.app` launched with `open`. Four 60 s runs, ~765 processes per run. Every
terminated process was one the harness created; nothing else was signalled.

## kqueue `EVFILT_PROC` — the primary candidate

Two kqueues were registered over the whole process table each run: one asking
for `NOTE_EXIT | NOTE_EXITSTATUS | NOTE_EXIT_DETAIL | NOTE_SIGNAL`, one asking
for bare `NOTE_EXIT`. The status-bearing mask is refused at *attach* time with
`EACCES`; it does not fail silently at delivery.

| registration | unsandboxed | sandboxed |
|---|---|---|
| status mask, own-uid | **520/526** attached | **3/527** attached |
| status mask, other-uid | 0/238 (`EACCES`) | 0/236 (`EACCES`) |
| bare `NOTE_EXIT`, own-uid | 526/526 | 527/527 |
| bare `NOTE_EXIT`, other-uid | 238/238 | 236/236 |

The sandboxed 3 are **exactly the three children the probe forked itself**.
Own-uid processes the probe did not fork — including `sleep` and `bash`
processes the harness had just spawned from the same shell, same uid, same
session — are refused identically to `WindowServer`. So:

- **The sandbox is the binding limit here, and parentage is the residual.** This
  is the opposite of the usual pattern: per-process CPU/memory is denied by uid
  equally sandboxed and unsandboxed, so the sandbox costs nothing. Here the
  sandbox costs 517 of 520 processes.
- Unsandboxed, the 6 own-uid refusals are hardened/protected apps, not a random
  tail: `com.apple.Safari`, `loginwindow`, `ScreenTimeAgent`, `XprotectService`,
  `UsageTrackingAgent`, `dmd`.

Delivery matched attach exactly. Over the four runs, **every** `NOTE_EXIT`
delivered on the status mask carried `NOTE_EXITSTATUS` (unsandboxed 15/15 and
27/27; sandboxed 3/3, all three our own children), and sandboxed we observed
**0 statuses from 0 strangers** while the bare kqueue saw 16–23 stranger exits
in the same windows. Decoding, where it is available, is complete and correct —
`data` is a wait(2) status, verified against `waitpid` ground truth for all
three children in every run:

```
SIGSEGV -> data 11    WIFSIGNALED, SIGSEGV   -> CRASH
exit 7  -> data 1792  WIFEXITED, code 7      -> normal exit, nonzero code
SIGTERM -> data 15    WIFSIGNALED, SIGTERM   -> terminated by signal, not a crash
```

Note the middle row: **"nonzero" is not "crashed"**. A compiler exiting 1 on a
syntax error is a normal exit. Only a fatal signal is evidence of a crash, and
only some of those — `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGABRT`, `SIGTRAP`,
`SIGFPE`, `SIGSYS`. `SIGTERM`, `SIGINT`, `SIGHUP` and `SIGKILL` are ordinary
terminations; `SIGKILL` in particular is how a great deal of macOS shutdown
works and must never be reported as a crash.

`NOTE_EXIT_DETAIL` was set on every status-bearing event but `NOTE_EXIT_MEMORY`
(jetsam) never fired in these runs, so the jetsam distinction is **unmeasured**,
not unavailable.

## `NOTE_SIGNAL` is not a back door

`NOTE_SIGNAL` attaches only as part of the same refused mask, so sandboxed it is
available for our own children only. It is useless even where it works: 185
events in one unsandboxed run, **every one with `data = 0` and no signal number
anywhere in `fflags`**. It tells you a signal was delivered, never which. It
also fires constantly for healthy processes (`SWBBuildService` produced ten
events in half a second), so its rate is not a crash signal either.

## kqueue `NOTE_EXIT` *is* worth having anyway

Bare `NOTE_EXIT` attaches for **every** process, sandboxed, including other-uid
— 236/236 — and we observed other-uid exits delivered (1 unsandboxed, 2
sandboxed in separate runs). That is a rare exception to "measurability is
decided by uid, exactly": we can watch `WindowServer` exit even though we can
never read its CPU.

It is also cheap: **0.4 ms to register 763 pids** (0.0005 ms/pid), one file
descriptor for the whole set, event-driven with no polling, and the knote
auto-deletes when it fires. The status mask costs 4.5 ms for the same set
because 524 of the calls are round-tripping to an `EACCES`.

Compared with what `LifecycleTracker` does today, this is exact rather than
inferred: a process that starts and exits between two sweeps is invisible to
snapshot diffing and is not invisible to a kqueue. It changes no claim we are
allowed to make about *why* a process exited.

## The process table already carries `p_xstat`, and it is still not enough

`extern_proc.p_xstat` in the `sysctl KERN_PROC_ALL` row holds the uncollected
exit status of a zombie, and it is readable **sandboxed, for strangers**, at no
new API cost — the product already makes this call. Decoded values were correct
every time (a stranger `caffeinate` read `p_xstat=9`, SIGKILL; a stranger CLI
tool read 0, a clean exit).

The catch rate is what kills it. Polling the whole table at **4 Hz** — 8–20×
faster than the product's 2–5 s cadence — caught **2 of 23** stranger exits in
the final sandboxed run, and 1 of 11 in another. At the moment `NOTE_EXIT`
fired, **0 of 9** strangers were still listed in `sysctl` at all: their parents
reap them immediately. Zombies survive long enough to be seen only when the
parent is slow, which is a property of the parent, not of how the child died.

So `p_xstat` is a real signal with a biased, single-digit-percent catch rate. It
can corroborate a crash we already suspect. It cannot be the basis for saying an
application crashed, and a detector built on it would silently under-report
exactly the well-behaved parents that reap fastest.

## The cheap ones, each a dead end

- **`proc_pidinfo` / `PROC_PIDT_SHORTBSDINFO`**: nothing survives the exit.
  `ESRCH` for our own child while it was still an unreaped zombie (the most
  favourable case that can exist), `ESRCH` after reaping, `ESRCH` for a pid that
  never existed. The zombie was simultaneously visible in `sysctl` with
  `p_stat=5` and the correct `p_xstat`, so this is `proc_pidinfo` declining, not
  the kernel having forgotten.
- **`NSRunningApplication`**: its entire property surface is 14 properties —
  `activationPolicy, active, bundleIdentifier, bundleURL,
  executableArchitecture, executableURL, finishedLaunching, hidden, icon,
  launchDate, localizedName, ownsMenuBar, processIdentifier, terminated`. There
  is no exit status, no exit code, no termination reason. `terminated` is a
  `Bool`. This is decisive on its own and matches the existing finding that a
  beachballing app is reported identically to a healthy one.
- **`NSWorkspace.didTerminateApplicationNotification`**: the notification hands
  you an `NSRunningApplication` and nothing else, so by the point above it
  cannot distinguish a crash from a quit *even when it arrives*. Whether it
  arrives is **not established**: across four configurations (unbundled tool
  with a plain run loop; unbundled with `NSApplication.run()`; bundled sandboxed
  with `finishLaunching`; bundled sandboxed with a real `NSApplication` event
  loop and the kqueue watch moved to a worker thread) we saw zero terminations
  *and* zero launches, with a victim `.app` demonstrably launching and quitting
  inside the window and demonstrably present in
  `NSWorkspace.shared.runningApplications` (policy `.accessory`). Zero launches
  means the plumbing control failed, so zero terminations proves nothing about
  delivery. The most likely explanation is that `LSUIElement` accessory apps do
  not generate these notifications, and confirming that would require launching
  and quitting a regular Dock app — which puts something on screen and was not
  done. It does not change the answer.

## Rules that come out of this

- **Never say "quit unexpectedly" from a disappearance.** The only thing an
  absent `(pid, start time)` supports is "no longer running". FR-046's
  repeated-relaunch framing is the honest one and this probe does not widen it.
- **Nonzero exit is not a crash.** If a status ever does become available, only
  fatal signals from the crash set may be called a crash, and `SIGKILL` and
  `SIGTERM` are not in it.
- **Never signal a process you did not create**, including to learn something
  about it. FR-037. The probe crashes only its own children and the harness only
  its own.
- The one strand worth acting on independently: `LifecycleTracker` could take
  its exit *events* from a bare `NOTE_EXIT` kqueue instead of snapshot diffing,
  which is cheaper, catches short-lived processes, and works across the uid
  boundary. That is an accuracy change to *when* we notice, not a change to
  *what we may claim*.

## Reproducing

```sh
probe/run-exit-status-probe.sh 60
```

Builds both binaries, spawns its own victims (a `SIGSEGV`, a `SIGTERM`, an
`exit 0`, an `exit 3`, plus an `LSUIElement` app that is `SIGKILL`ed and a
second that quits cleanly), runs the unsandboxed control and then the sandboxed
`.app` via `open`, and prints the diff. The `.app` is `SIGKILL`ed rather than
`SIGSEGV`ed on purpose: CrashReporter's default `DialogType` would put a "quit
unexpectedly" alert on screen for a segfaulting application. The sandboxed
report is written to
`~/Library/Containers/com.brooksc.MacSlowdown.Probe.exit-status-probe/Data/exit-status-result.txt`.

# A note on the OS these findings were measured against

**Everything above and below was measured on a macOS 27 beta**, builds in the
`26A5388g` family, on an M2 MacBook Air.

macOS 27 reached general release on 2026-09-14 and this machine is now on build
`26A428`, which carries no beta flag. The test suite passes on it unchanged
(1290, no failures), so nothing has visibly broken.

That is worth stating precisely, because a green suite and a re-measured
platform fact are different claims. The findings here are about what the kernel
and the sandbox permit — denial codes, which APIs return data for which
processes, what a signed `.app` can read. None of that is exercised by the test
suite, and a point release can change any of it quietly. Treat these as measured
on a beta until something re-runs the probes against final 27.

`TASK-45` asks the same question about macOS 26. It now has two axes: macOS 26,
which CI partly answers, and final macOS 27, which nothing has yet.

# TASK-103 — run-queue pressure: the proposed threshold is refuted

Measured 2026-09-03 on the M2 Air, 8 logical cores, macOS 27, via
`probe/Sources/loadavg-probe.swift` sampling `getloadavg` and the host CPU load
counters at one second.

FR-006's proposed amendment adds a condition breaching above **2.0 runnable
threads per logical core held for 60 s**. Both numbers came from one observation
(peak load 95.8 on 8 cores — about twelve per core — while CPU busy sat at
44–51%, correlation 0.68) and were explicitly flagged as a starting guess.

## What was measured

| Shape | Samples | Per-core median | Per-core peak | CPU busy median | Correlation |
|---|---|---|---|---|---|
| Baseline, ordinary desktop | 180 | 0.61 | 0.89 | 20.2% | 0.22 |
| `tuist xcodebuild build -jobs 6`, nice'd | 240 | **2.87** | **8.68** | 63.1% | 0.34 |

At a 2.0 boundary the build run breaches on **59.2% of samples**, and 113 of
those 142 samples are below FR-006's 85% CPU threshold. Even 4.0 breaches on 35%.

## Three findings, in the order they bite

**1. 2.0 per core is refuted outright.** A capped, nice'd build — the exact
workflow CLAUDE.md prescribes — sits at a median of 2.87 per core and peaks at
8.68. A condition at 2.0 held for 60 s would breach through most of every
compile. That is FR-046's history repeating: a condition that fires whenever you
build is worse than no condition, because it trains the user to ignore it. The
proposal cannot go to approved at this value.

**2. The high readings are dominated by I/O wait, not runnable work.** Of the 142
build samples at or above 2.0 per core, **141 had pagein above 1 MB/s**. macOS's
load average counts threads in uninterruptible waits alongside runnable ones, and
under a build that term dominates. Two consequences: the condition can never be
*described* as a CPU condition (which design 4b already says, and this measures),
and a large part of what it would report is a disk being busy — which may be worth
reporting, but is a different claim needing different words.

**3. The figure is 1-minute smoothed, so a 60 s duration double-counts it.**
`load1` moves in coarse steps of roughly 5 s and lags reality by tens of seconds:
at build start it read 7.43 for 16 s before stepping to 10.28, while CPU busy was
already swinging 62–78% second to second. It is an exponentially-weighted average
over a minute, so it *already encodes* a minute of history. Requiring it to hold
for a further 60 s means roughly two minutes of real elapsed time before a
breach — and it means the amendment's premise, that run-queue pressure is "felt
immediately, unlike CPU saturation", is not true of *this signal*. The thing that
is felt immediately is the queue depth; `getloadavg` is not a measurement of it
at an instant.

The correlation with CPU busy also fell from the original 0.68 to **0.34** under
build load, which strengthens the amendment's core claim — the two signals are
genuinely different — while removing the threshold that was supposed to exploit it.

## What this does not settle

The original observation stands: a machine at twelve per core was unusable while
CPU busy read 44–51%, and FR-006 saw nothing. The signal separates felt-slow from
busy — the boundary is simply much higher than proposed, somewhere above the 8.68
per core an ordinary build reaches, and near the 12 the unusable machine showed.
That is a narrow gap and it cannot be set from these two shapes.

Still needed before any number is fixed:

- A deliberately oversubscribed run, to find where the boundary actually falls.
  **Not run: it makes the machine unusable for minutes and needs the owner's
  go-ahead.**
- Observation across ordinary work over hours, for criterion #3 — which is the
  owner's real workload and cannot be synthesised.
- A decision on whether a separate, *unsmoothed* queue-depth reading is available
  at all. If the condition is to claim immediacy, `getloadavg` is the wrong input
  for it.

## Rule that comes out of this regardless

**Never put a 1-minute load average behind a sub-minute duration threshold.** The
smoothing is part of the measurement, and a duration on top of it is counting the
same history twice — the same error as presenting a cumulative total as a rate.

## Reproducing

```sh
swiftc -O -o probe/build/loadavg-probe probe/Sources/loadavg-probe.swift
probe/build/loadavg-probe 180 baseline
```

CSV on stdout, summary on stderr. The summary reports, for each candidate
threshold, how many samples breach and how many of those FR-006's CPU rule would
have missed — which is the comparison the amendment turns on.

---

## A sandboxed binary can hang forever before `main`, and the cause is its bundle id

**2026-09-14, final macOS 27 (26A428), M2.** The Tier 0 probe stopped working. Run
it and it produces no output at all, sits at 0% CPU, and never exits. It looks
exactly like an infinite loop in our own code. It is not: `sample` puts the single
thread in `_libsecinit_appsandbox`, on a synchronous XPC round-trip to `secinitd`
that never returns —

```
libSystem_initializer → _libsecinit_appsandbox → _xpc_pipe_routine
  → _xpc_pipe_mach_msg → mach_msg → mach_msg2_trap
```

This is during dyld's initialiser phase, so it is **before `main`**. No print
statement in the probe can ever run, which is why the symptom carries no
information.

**The cause is reusing a bundle id whose container was created by a different
code signature.** Established by elimination, each step a separate run:

| Variant | Result |
|---|---|
| Same binary, unsandboxed | completes in seconds |
| Trivial sandboxed hello-world, same entitlements | completes |
| Probe with a **fresh, never-used** bundle id | completes (twice, two different ids) |
| Probe with its original id, after `rm -rf ~/Library/Containers/<id>` | **hangs** |
| Probe with a fresh id, then the *other* signing mode on that same id | **hangs** |

So: it is not the sandbox, not ad-hoc signing, not the bundle location, and not
our code. Deleting the container directory does **not** repair it — whatever
`secinitd` consults survives that, and it is not readable without root. A poisoned
id can only be abandoned.

The original poisoning is visible in the dead container's metadata: its
`SandboxProfileDataValidationInfo` named
`application_bundle = …/.claude/worktrees/agent-a62dd287…/probe/build/VersionNameProbe.app`
— a *different probe*, in a worktree deleted weeks ago. Several probe binaries all
claimed the bare `com.brooksc.MacSlowdown.Probe`, so they shared one container and
one cached profile.

**Rules that follow.**

- **Every sandboxed probe gets its own leaf bundle id.** `build-probe.sh` and
  `build-with-metrics.sh` already derive `…Probe.$NAME`; `build-sandboxed.sh` was
  the one that hardcoded the shared parent, and now uses
  `…Probe.tier0.g<GENERATION>.<signer>`.
- **The id must encode the signing identity**, because one ad-hoc run poisons a
  real-signed id and vice versa. A hash of the identity string is enough.
- **`GENERATION` is the repair.** Bump it when a sandboxed probe hangs with no
  output; nothing else produces that symptom. Generations 1 and 2 of `.tier0` are
  burned on the author's machine.
- **Ad-hoc signing (`IDENTITY="-"`) is valid for sandbox measurement.** The
  signature carries `com.apple.security.app-sandbox`, the sandbox is genuinely
  applied, and the probe's answers match a real-signed run exactly. This is what
  makes the probe runnable on a CI runner, which holds no certificate. (Note it is
  *not* valid for an XCTest **host app** — that hangs for an unrelated reason, see
  `.github/workflows/tests.yml`.)

### Every Tier 0 finding re-confirmed on *final* macOS 27

The reason this mattered: every platform fact in this document was measured on a
macOS 27 **beta**, and the machine went to final 27 on 2026-09-14. Once the probe
ran again it reproduced all of them, sandboxed, on `26A428`:

```
sysctl KERN_PROC_ALL: 835 pids returned
proc_listpids       : 0 pids  [DENIED: EPERM(denied)]
PROC_PIDTBSDINFO   :  579/ 835 ( 69.3%)  errors: EPERM(denied)×256
PROC_PIDTASKINFO   :  579/ 835 ( 69.3%)  errors: EPERM(denied)×256
proc_pid_rusage    :    1/ 835 (  0.1%)  errors: EPERM(denied)×834
proc_pidpath       :  830/ 835 ( 99.3%)  errors: errno2×6
```

Enumeration still works, `proc_listpids` is still denied, `proc_pid_rusage` is
still self-only, and **256 other-uid processes against exactly 256 denials** — the
"measurability is decided by uid, exactly" rule holds on final 27 with no
exceptions in either direction.

macOS 26 remains unmeasured *for the sandbox*; `.github/workflows/sandbox-probe.yml`
runs this same probe on a `macos-26` runner and asserts these four answers.

### macOS 26: every Tier 0 answer matches macOS 27 (TASK-45)

**2026-09-14, macOS 26.6.2 (25G83), Swift 6.3.3, a 3-core GitHub Actions runner,
ad-hoc signed.** The question A-01 has carried since 2026-08-02 — everything was
measured on 27, and the app must ship on 26 — answered by
`.github/workflows/sandbox-probe.yml`:

```
sandboxed (heuristic): true
euid: 501  cores: 3
sysctl KERN_PROC_ALL: 545 pids returned
proc_listpids       : 0 pids  [DENIED: EPERM(denied)]
PROC_PIDTBSDINFO   :  298/ 545 ( 54.7%)  errors: EPERM(denied)×247
PROC_PIDTASKINFO   :  298/ 545 ( 54.7%)  errors: EPERM(denied)×247
proc_pid_rusage    :    1/ 545 (  0.2%)  errors: EPERM(denied)×544
proc_pidpath       :  544/ 545 ( 99.8%)  errors: errno2×1
```

**No divergence.** Enumeration via `sysctl KERN_PROC_ALL` is permitted under App
Sandbox on 26, `proc_listpids` is denied there too, `proc_pid_rusage` is self only,
and **247 other-uid processes produced exactly 247 denials** — the uid rule holds on
26 with no exceptions in either direction, as it does on both 27 beta and 27 final.
So the enumeration strategy ships on both OSes, `decision-1` needs no escalation,
and FR-009 per-process I/O and FR-043 footprint are no more restorable on 26 than
on 27.

The measurability *percentage* is lower (54.7% against ~69%) and that is not a
divergence: a CI runner runs proportionally more system daemons than a desktop, and
the denials still account for every other-uid process exactly. Percentages here are
a property of what happens to be running, never of the platform.

CPU figures read 14–20% of one core for `mdworker_shared`, which is the sanity check
on the fourth question: a wrong mach timebase or `proc_taskinfo` layout on 26 would
be off by about 42×, not plausible.

**What this does not cover.** The runner is 26.**6.2**, not 26.0, and is a
virtualised 3-core machine — so it answers the sandbox-policy question, which is
what was at risk, and not anything about physical hardware, P/E core asymmetry, or
thermals. The signature is ad-hoc rather than a development certificate; that is
established above as valid for sandbox measurement.
