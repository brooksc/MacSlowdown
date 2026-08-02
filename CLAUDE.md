# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

**MacSlowdown** — a native macOS performance-monitoring and diagnostic app. It
continuously observes system resource conditions, detects *sustained*
degradation, attributes it to application families, preserves bounded evidence
before/during/after the event, and explains it without overstating causation.

Greenfield. As of this writing the repo contains only `requirements.md` — no
source, no build system, no commits.

## Authority

`requirements.md` is the authoritative specification for scope and behavior
(see its §11). Before implementing anything, find the governing FR and satisfy
its **acceptance criteria** literally — they are the definition of done.

- Features not in `requirements.md` require a spec update first. Don't invent scope.
- If a requirement is infeasible under the target macOS or the sandbox: document
  the limitation, propose a compliant alternative, and ask. Don't silently
  substitute.
- UI/interaction design is produced separately (Claude Design) and is a design
  *input*; this spec still governs behavior, safety, privacy, accessibility.

## Hard constraints (do not violate)

- **App Sandbox / Mac App Store only.** No privileged helpers, launch daemons,
  or elevated components (A-03, A-04, FR-037).
- **No process control.** No suspending, quitting, force-quitting, CPU limiting,
  renicing, or QoS manipulation of other processes. Not even behind a flag or a
  dormant code path — FR-037's acceptance criterion forbids unreachable
  privileged UI in the shipping build. FR-020–024 are deferred and *escalated*.
- **Public APIs only.** No undocumented sensor access, no private frameworks.
- **Local by default** (A-05, FR-029). Nothing containing process identity,
  paths, or incident contents leaves the machine without separate explicit
  consent. A fresh install transmits no process inventory.
- **Never fabricate a measurement.** Unavailable data is labeled unavailable
  (FR-002, FR-010, FR-043, FR-052). Omit a metric rather than approximate it.

## Verified sandbox facts (see `probe/FINDINGS.md`)

Measured on macOS 27 / M2, sandboxed vs unsandboxed. Don't re-derive these:

- **Enumerate with `sysctl KERN_PROC_ALL`, never `proc_listpids`.** The latter is
  denied under App Sandbox (EPERM) and Apple DTS has confirmed no entitlement
  lifts it. sysctl returns the full table (~1058 procs).
- **Per-process CPU/memory:** `proc_pidinfo(PROC_PIDTASKALLINFO)` works sandboxed
  for own-uid processes (720/1058). Other-uid is denied — *and is equally denied
  unsandboxed*, so the sandbox costs nothing here. Prefer TASKALLINFO over
  separate BSDINFO+TASKINFO calls; it halves the syscalls.
- **`proc_pid_rusage` is fully blocked** (self only). That means **no**
  phys_footprint, **no** per-process disk I/O, **no** per-process wakeups.
- **CPU times are mach ticks, not nanoseconds.** Scale by `mach_timebase_info`
  (125/3 on Apple Silicon) or CPU reads ~42× too low. Intel's 1:1 timebase is
  why sample code omits this.
- **`proc_pid_rusage` writes to `buffer`, not `*buffer`** despite its
  `rusage_info_t *` signature. Passing the address of a pointer smashes the stack.
- Memory must be reported as **resident size**, not footprint. Activity Monitor
  shows footprint, so our numbers will legitimately differ — label it.
- Cache `proc_pidpath` by (pid, start time); re-reading every sweep costs ~5 ms
  and breaks the FR-030 budget at 1 s cadence. sysctl + taskinfo alone is 1.8 ms.

## Correctness rules that are easy to get wrong

These recur across many FRs and have burned similar products:

- **Rates come from deltas of monotonic counters.** Never present a cumulative
  total as a current rate. Handle counter reset and wrap. (FR-008, FR-009, FR-051)
- **PIDs are reused.** Identity is `(pid, start time)`. Application-family
  history must survive PID replacement. (Data model §6, FR-043, FR-045)
- **CPU percentages are ambiguous.** Pick core-relative or machine-relative,
  label it consistently, and account for P/E core asymmetry. (FR-004)
- **Memory pressure ≠ percent RAM used.** Use the official pressure signal;
  never describe cached memory as wasted. (FR-007, DR-08)
- **Never claim memory was freed** unless a measurement shows it was. (FR-036)
- **Never call growth a "memory leak."** It's a *suspected* anomaly with
  alternative explanations. (FR-044)
- **Never treat an API's success return as a performance improvement.** Verify
  outcomes by re-measuring over a bounded window; "inconclusive" is a valid
  result. (FR-050)
- **Sustained, not transient.** Detection requires duration thresholds and
  recovery hysteresis; a single spike is not an incident. (FR-006, FR-011)
- **Label every conclusion** as measured fact / derived calculation / heuristic
  hypothesis / user-provided. (FR-038)

## Language and copy

User-facing text is part of the requirements, not decoration. Causal language
must carry a confidence label (FR-013). Avoid "optimize," "clean," "boost,"
"free up memory," "fix." Prefer stating what was measured, over what interval,
and what remains uncertain.

## Performance budget

The tool must not become part of the slowdown (FR-030). Initial targets:
idle CPU median ≤1% of one core, resident memory ≤100 MB, disk writes
≤10 MB/hour absent incidents. Sampling is two-stage (FR-031): normal cadence
~2–5s, investigation cadence ~1s.

Treat these as tests, not aspirations — per-process sampling across hundreds of
processes at a 2s cadence can blow the budget on its own. Separate sampling
cadence from UI refresh (DR-03).

## Accessibility

Non-negotiable per FR-034: VoiceOver labels, full keyboard operation, increased
contrast and reduced transparency support. **Severity is never conveyed by
color alone.**

## Phasing

1. Core monitor — status surface, inventory, grouping, bounded history, search,
   machine context, overhead instrumentation.
2. Incident diagnosis — pressure, swap, I/O, storage, thermal, power,
   unresponsiveness, incident lifecycle, notifications, reports.
3. Safe response — activate/reveal, open system tools, policies, mute, export,
   post-action verification.
4. Advanced context — baselines, optional network/GPU/wakeup, profiles.

Don't build Phase N+1 infrastructure during Phase N.

## Undecided — ask, don't assume

Not yet chosen, and not inferable from the repo:

- Build system (Tuist vs. Xcode project), test framework, CI.
- Module boundaries and persistence format.
- Whether incidents persist across restarts, and default retention.
- Whether summaries use an on-device model or deterministic templates (FR-013).
- Whether raw temperature is exposed beyond public thermal state.

Resolved by the Tier 0 probe: per-process I/O (FR-009) and wakeups (FR-048) are
**blocked** sandboxed — scope FR-009 to aggregate-only and drop FR-048 from the
MAS release. FR-043 must use resident size.

Still unproven: audio activity (FR-019), unresponsiveness (FR-046), per-app
network (FR-051), GPU (FR-052). Validate with a spike before designing features
that depend on them; if a signal isn't reliably available, the spec's answer is
to omit the feature, not approximate it.

**Largest open risk:** whether App Review accepts `sysctl KERN_PROC_ALL` for
process enumeration given that `proc_listpids` is explicitly denied. No
entitlement is requested and the API is public, but there's no Apple statement
blessing it. This cannot be settled by testing — it needs a DTS incident.

## Conventions

- Swift preferred; SwiftUI for most UI, AppKit or public lower-level APIs where
  SwiftUI is insufficient (A-02, DR-10). Concurrency isolation around samplers
  and persistence.
- Target: macOS 26 and 27, Apple Silicon. Intel not required.
- `nice` long-running build/test commands so the GUI stays responsive.
