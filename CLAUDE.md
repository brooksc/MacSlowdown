# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

**MacSlowdown** — a native macOS performance-monitoring and diagnostic app. It
continuously observes system resource conditions, detects *sustained*
degradation, attributes it to application families, preserves bounded evidence
before/during/after the event, and explains it without overstating causation.

Phase 1 (m-1, core monitor) is built. Tuist project, sandboxed menu bar app,
`Metrics` framework with the sampler, identity resolver, family grouping,
attribution and bounded history, plus the FR-030 overhead harness. Run it with
`./run-menubar.sh`; test with `tuist xcodebuild test -scheme AllTests`.

## Working practice

- Work is tracked in Backlog (`.backlog/`, MCP server `backlog`). Check
  `task_list` before starting; move a task to In Progress when you begin and
  record findings in its notes when you finish.
- **Milestones use Backlog's native `milestone` field** (`m-0` … `m-4`, mapping
  to the spec's phases), not labels. Filter with `task_list --milestone`.
  Labels are for type and state only: `core`, `ui`, `infra`, `spike`,
  `decision`, `risk`, `parked`, `blocked-by-sandbox`, `blocked-external`,
  `non-mas`, `out-of-scope`. Parked and out-of-scope work carries no milestone.
- Probes and findings live in `probe/`. When a spike settles a question, append
  it to `probe/FINDINGS.md` and reflect any durable rule here.
- Build sandboxed test binaries with `probe/build-sandboxed.sh` — it needs only
  `swiftc` + `codesign`, no Xcode project. Sandbox behavior must always be
  verified in a signed `.app`; an unsandboxed binary proves nothing about it.

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
  lifts it. sysctl returns the full table (~1058 procs). **Accepted with known
  risk — see `.backlog/decisions/decision-1`**: Apple withdrew this same sysctl
  on iOS 9, so keep `ProcessSampler.processTable()` the single point of contact
  and never reach around it. That seam is what makes the decision reversible.
- **Per-process CPU/memory:** `proc_pidinfo` works sandboxed for own-uid processes
  (720/1058). Other-uid is denied — *and is equally denied unsandboxed*, so the
  sandbox costs nothing here. Use **`PROC_PIDTASKINFO`**, not TASKALLINFO: the
  sysctl enumeration already supplies name, uid, ppid and start time, so
  TASKALLINFO's bsdinfo half is 136 redundant bytes per process for the same
  syscall count.
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
- **Identity: path is the anchor, signature is enrichment.** `proc_pidpath`
  works for 1042/1063 procs sandboxed (unaffected by the sandbox);
  `SecCodeCopyGuestWithAttributes` works for 810/1063. Group by the **outermost
  `.app`** in the executable path — the signed bundle ID does *not* group,
  because helpers report their own identifier, not the parent's.
- **Only ~15% of processes belong to an application family** (154/1063 live in a
  `.app`). Standalone daemons and CLI tools are a first-class case in the data
  model, not a family-of-one.
- **Identity resolution costs ~760 ms per full sweep** — ~400× the metrics
  sweep, and the dominant cost in the system. Resolve once per process lifetime,
  cached by `(pid, start time)`. Never per-sweep.
- Security-framework `OSStatus` failures decode as `kPOSIXErrorBase` (100000)
  plus errno: 100001 = EPERM, 100002 = ENOENT, 100013 = EACCES.
- **Window titles are unavailable** without Screen Recording permission (measured:
  1/8 windows expose `kCGWindowName`, and that one is our own). Per-tab and
  per-document context is out. `kCGWindowOwnerName` **is** available for every
  window with no permission, which covers foreground/visible state.
- **Test TCC-sensitive capabilities via `open`, never by exec'ing from a shell.**
  macOS attributes permissions to the *responsible process*, so a binary launched
  from a terminal inherits the terminal's grants. The window-title probe reported
  8/8 titles that way and 1/8 when launched properly.
- **Application hangs are undetectable.** No public API exposes unresponsive
  state; `NSRunningApplication` reports a beachballing app identically to a
  healthy one, Accessibility is untrusted, and the system's hang reports in
  `/Library/Logs/DiagnosticReports` are unreadable (`~/Library/...` redirects
  into our own container). FR-046 is deliverable only as **repeated relaunch**
  detection via lifecycle tracking — never claim hang detection.
- **Per-process audio IS available**, with no microphone permission and no extra
  entitlement: `kAudioHardwarePropertyProcessObjectList` (macOS 14.2+) gives a
  pid plus `IsRunning` / `IsRunningInput` / `IsRunningOutput` per audio process.
  Input covers microphone use, output covers playback. Verified against real
  playback, not just a zero reading.
- **The binding limit is uid, not the sandbox.** Other-uid processes
  (`WindowServer`, `mds_stores`, `backupd`, `coreaudiod`, `launchd`) are denied
  identically sandboxed and unsandboxed; only root sees them. ~40 percentage
  points of busy CPU is therefore unattributable in the MAS build. Surface this
  as an explicit "unattributed system activity" category — never let contributor
  lists silently fail to sum (FR-013, FR-038).

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

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md MCP for all task and project management activities.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_backlog_instructions()` to load the tool-oriented overview. Use the `instruction` selector when you need `task-creation`, `task-execution`, or `task-finalization`.

- **First time working here?** Read the overview resource IMMEDIATELY to learn the workflow
- **Already familiar?** You should have the overview cached ("## Backlog.md Overview (MCP)")
- **When to read it**: BEFORE creating tasks, or when you're unsure whether to track work

These guides cover:
- Decision framework for when to create tasks
- Search-first workflow to avoid duplicates
- Links to detailed guides for task creation, execution, and finalization
- MCP tools reference

You MUST read the overview resource to understand the complete workflow. The information is NOT summarized here.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->
