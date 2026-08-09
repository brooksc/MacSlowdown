# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

**MacSlowdown** — a native macOS performance-monitoring and diagnostic app. It
continuously observes system resource conditions, detects *sustained*
degradation, attributes it to application families, preserves bounded evidence
before/during/after the event, and explains it without overstating causation.

Phases 1-3 (m-1 … m-3) are built: sandboxed menu bar app plus a `Metrics`
framework carrying the sampler, identity resolution and naming, family grouping,
attribution, bounded history, incident detection and summarisation, notifications,
safe actions, export and privacy controls, and the FR-030 overhead harness.

- Run: `./run-menubar.sh`
- Test: `nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath .build`
  — currently **670 passing**. Two bundles: `MetricsTests` (plain) and
  `MacSlowdownTests` (app-hosted; `AppDelegate` skips launch work under XCTest so
  a test run does not start monitoring or put a status item in your menu bar).
- FR-030 measurement: `probe/overhead/run.sh 300` — standalone but **no longer a
  gate**; the numeric budget is deferred (see Performance budget below). Run for
  at least 300 s; a 90 s run reads high (TASK-62).

**Three tests measure the real machine and fail on a busy one.** They are not
flaky in the usual sense — they synthesise CPU load and assert on separation, so
they report the machine's state honestly and decline to run when it is too busy:
`CPUWorkloadTests.workloadIsAttributed`, `CPUWorkloadTests.singleCoreWorkload`,
`EndToEndIncidentTests.realSlowdownProducesOneIncident` (which fails at its own
"baseline CPU too high" guard), `EndToEndIncidentTests.cadenceRisesUnderLoad`.
Re-run any failure in isolation with `-only-testing:` on a quiet machine before
treating it as a regression. Building several things at once will fail them.

The app-hosted bundle occasionally fails to bootstrap under load
("Early unexpected exit"). Re-run before investigating; it is the test runner,
not the product.

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
- **Commit and push after every major update.** The remote is a private GitHub
  repo and exists as a backup, so work that only lives on this machine is work
  that can be lost. "Major update" means a completed task, a resolved spike, a
  decision record, or a spec amendment — not every intermediate edit. Push at
  the end of a milestone without being asked; ask before pushing anything that
  would be visible outside the private repo.
- Build sandboxed test binaries with `probe/build-sandboxed.sh` — it needs only
  `swiftc` + `codesign`, no Xcode project. Sandbox behavior must always be
  verified in a signed `.app`; an unsandboxed binary proves nothing about it.
  `probe/Sources/` holds one file per question already answered; read
  `probe/FINDINGS.md` before writing a new one.
- **A UI criterion is not met by a passing unit test.** Several tasks carry
  criteria left deliberately unchecked because nothing was seen on screen. If you
  cannot look, say "not verified" and why, rather than inferring from tests.
- **Ask before using the screen.** Launching the app, driving the UI, taking
  screenshots or triggering a TCC prompt collides with whatever the user is
  doing. Permission lasts about 5 minutes. Terminal work, builds, tests, probes,
  git and Backlog need no permission.

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
- **Naming: `Info.plist` is readable under the sandbox.** 145 of 151 processes in
  a `.app` yield `CFBundleDisplayName`/`CFBundleName`; with
  `NSRunningApplication.localizedName` 187 of 800 carry a real name and 188 a real
  icon. Resolution order is running-application, outermost `.app`, `.appex`, then
  the command. `.framework` is excluded — 269 processes live in one and it never
  yields a better name. **`p_comm` is 16 bytes**: measure truncation in *bytes*,
  and never show the fragment as if it were the name (FR-002).
- **`NSWorkspace.icon(forFile:)` never returns nil** — it returns a generic icon.
  Compare against `icon(for: .unixExecutable)` or the interface claims an icon it
  does not have.
- **PID recycling is not theoretical.** macOS wraps allocation at **99999**; on a
  machine with 12 days of uptime the counter had already wrapped, with live
  processes holding pids near 99999 while new ones came from ~45000. Identity is
  always `(pid, start time)`, and any `ppid` use must reject a parent that started
  *after* its child.
- **`ppid` corroborates, it does not group.** 82% of the table is parented by
  launchd, because macOS launches helpers through launchd and XPC. Where it does
  point at a real process it confirms a path claim the signature could not, and it
  attributes unbundled processes to the app that spawned them — 13 shells under a
  terminal rather than 13 unrelated rows. **"Parented by launchd" is NOT
  "unmeasurable"**: 464 of 690 launchd-parented processes are ours and readable.
- **Measurability is decided by uid, exactly.** 599 own-uid processes, 0 denied;
  229 other-uid, 229 denied. No exceptions either way, so a "System processes"
  group keyed on `uid != getuid()` is precisely the unmeasurable set.
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
- **An overhead harness must exercise the path the app actually runs.** Ours
  measured only the top few contributors while the app groups every process every
  sweep; it reported a budget nobody was held to. Cold grouping of 844 processes
  costs **819 ms** against **2.90 ms** warm, so a short run and a long one
  disagree wildly. Measure over 300 s and treat first-sighting cost separately.
- **A notification that macOS accepts is not a notification the user saw.**
  Banners are suppressed while our own app is frontmost unless a
  `UNUserNotificationCenterDelegate` returns `.banner` from `willPresent`. Verify
  alerts by seeing them, not by `center.add` returning without error — the same
  rule as FR-050's "an API's success return is not an outcome".

## Language and copy

User-facing text is part of the requirements, not decoration. Causal language
must carry a confidence label (FR-013). Avoid "optimize," "clean," "boost,"
"free up memory," "fix." Prefer stating what was measured, over what interval,
and what remains uncertain.

## Performance budget — deferred, still measured

**The numeric budget no longer gates work** (product owner, 2026-08-08). Focus is
functionality and UX; optimisation comes later, against evidence. Do not block a
feature, fail a task, or redesign for size because a figure is over budget.

What has *not* changed: the tool must not become part of the slowdown. That
objective still drives adaptive sampling (FR-031: normal cadence ~2–5 s,
investigation ~1 s) and keeping sampling cadence separate from UI refresh
(DR-03). Keep measuring, keep reporting, don't gate.

Reference figures to revisit before release: idle CPU median ≤1% of one core,
disk writes ≤10 MB/hour absent incidents.

Two measurement facts that outlive the deferral:

- **Never state a memory budget in resident size.** Ours ranged 809–3323 MB over
  one 1191 s run with no behaviour change, while `phys_footprint` held 218–397 MB.
  ~3 GB of the peak was clean, shared, file-backed icon-cache mappings the kernel
  evicts for free. Use **`phys_footprint`, median over ≥300 s**.
- **The headless harness is not representative** — it runs no SwiftUI. Same day:
  harness 0.830% CPU / 20.7 MB, running Debug app 292 MB footprint median. Judge
  the app by the app.

At deferral the footprint median was 292 MB, most of it one avoidable allocation
pattern (`NSImage.tiffRepresentation` per icon cache miss, ~+148 MB per call).
See TASK-55.1, TASK-55.2.

## Accessibility

Non-negotiable per FR-034: VoiceOver labels, full keyboard operation, increased
contrast and reduced transparency support. **Severity is never conveyed by
color alone.**

## Where the work stands

Read the Backlog entry before starting any of them — each records what was
measured and what was deliberately not done.

**A design now exists.** `design/` holds the Claude Design screens (16 app screens,
menu bar icon states, six app-icon directions) as rendered references, with
`TASK-65` as the conformance umbrella and one subtask per screen. Treat the mocks
as **directional**: structure, information hierarchy and copy intent are the
requirement; the placeholder machine and invented numbers are not.

**The largest live risk is unverified UI.** A great deal was built without anyone
looking at it — roughly two dozen acceptance criteria across the TASK-65 subtasks
are deliberately unchecked because they need a person at the screen. Do not treat
those tasks as done. In particular **nobody has confirmed the Incidents pane
renders** (TASK-51.1 fixed it without establishing the cause and said plainly that
if it is still blank, the fix is wrong).

- **TASK-66** (high) — the single highest-value item. `MonitorStore` never wires
  up capabilities the `Metrics` framework already has and tests: **low-storage
  incidents can never open** (FR-041/042 cannot fire in the running product),
  retained history is unreachable so no sparkline in the design is buildable,
  no `PolicyStore` owner so FR-016 is framework-only, and `LifecycleTracker` is
  undriven. Four tasks unblock behind it. This pattern — framework ahead of app —
  is worth checking for elsewhere.
- **TASK-67** — AppKit logs a reentrant `NSTableView` delegate warning every ~2 s
  from the inventory, and says it will become an assert. Noise now, crash later.
- **TASK-51.1** — Incidents empty state. Fixed but **not diagnosed**; needs eyes.
- **TASK-11.1** — the Dock icon is now a real route back when the menu bar item is
  hidden. Rests on `@Environment(\.openWindow)` resolving in `App` scope, which is
  **unverified at runtime**. If it no-ops, the fallback is Scene-level registration.
- **TASK-65.x** — the remaining design screens. Several are blocked behind TASK-66.
- **TASK-58** — richer popover over FR-005 history. Large; the user wants to scope
  it in conversation first. **Do not start it unprompted.**
- **TASK-15** (parked, high) — accessibility baseline. Needs a person with
  VoiceOver. Several UI criteria elsewhere are parked waiting on it.
- **TASK-45** (parked, high) — re-validate every Tier 0 finding on macOS 26.
  Everything measured so far is macOS 27 only, and the spec targets both.
- **TASK-50** — the Apple DTS question on `sysctl KERN_PROC_ALL`. The user's
  action, not a work item.

Recently settled, so nobody re-opens them: TASK-62 (cold-start identity cut ~70%),
TASK-63 (**not a defect** — the table always sorted CPU-descending; what looked
wrong was the alphabetical tail of a correctly sorted list seen from a scrolled
viewport), TASK-57.1 (the processes named `2.1.220` were Claude Code itself —
its binaries are named after their version), TASK-55.1 (resident size is the wrong
statistic for our own memory; `NSImage.tiffRepresentation` cost ~148 MB per icon
cache miss and is gone).

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

- Whether incidents persist across restarts, and default retention.
- Whether summaries use an on-device model or deterministic templates (FR-013).
- Whether to amend the spec for an optional user-installed helper. The Mac App
  Store edition of iStat Menus reaches sensors only through a separately
  downloaded, non-sandboxed binary — the pattern A-03/A-04/FR-037 currently
  forbid. Raised and **set aside by the user**; do not act on it.

Settled, and not to be re-opened:

- Build system is **Tuist**; manifests are the source of truth. Test framework is
  **Swift Testing**. No CI yet.
- Raw temperature is **not** exposed. Public thermal state only.

Resolved by the Tier 0 probe: per-process I/O (FR-009) and wakeups (FR-048) are
**blocked** sandboxed — scope FR-009 to aggregate-only and drop FR-048 from the
MAS release. FR-043 must use resident size.

**GPU utilisation (FR-052) is available** — `IOAccelerator`'s
`Device Utilization %`, verified sandboxed against a real Metal load. Machine-wide
only: there is no per-process key, and no temperature or frequency key. Report it
as a sustained condition, never from one sample — an idle desktop reads up to 68%
from ordinary compositing. Hold the service handle; re-matching costs 2.5 ms, more
than the whole metrics sweep.

Still unproven: unresponsiveness (FR-046), per-app network (FR-051). Validate with a spike before designing features
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
