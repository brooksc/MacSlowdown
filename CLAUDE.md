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
  — currently **1317 passing** (full run, 2026-09-14).
  Run `tuist generate --no-open` after adding a source or test file, or the new
  file is silently not compiled — that has cost several runs. Two bundles:
  `MetricsTests` (plain) and
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

**The governing product decision, 2026-09-06.** Two independent product reviews
converged: **a measured resource condition is not a slowdown the user
experienced.** The product measures resources and reports them as slowdowns, and
no threshold, duration or attribution work closes that gap because the gap is not
measurement error. A capped build and a real slowdown are the same measurement;
only the person knows which is which. This governs copy everywhere (FR-063),
makes sustained CPU load record-but-not-announce by default (FR-014 amendment 1),
and is why the next substantive feature is the user telling *us* it feels slow
(FR-064) rather than any further tuning of what we detect. Plan and tasks:
TASK-109 through TASK-116. **Do not expand scope before TASK-114 reports.**

**Reviewing rather than building?** `REVIEW.md` is a reading order that starts at
the thesis and the scenarios, then the approach, then the implementation, and names
where the weak joints are. It is a map, not an authority.

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
- **A sandboxed probe that prints nothing and never exits is not looping — its
  bundle id is poisoned.** Reusing an id whose container was created by a
  different code signature blocks forever in `_libsecinit_appsandbox`, before
  `main`, so no print can run. Deleting the container does not fix it. Bump
  `GENERATION` in `probe/build-sandboxed.sh`; every probe needs its own leaf id.
  Ad-hoc signing (`IDENTITY="-"`) is valid for sandbox measurement — it is how CI
  runs the probe — but never for an XCTest host app.
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

> **Re-measured on final macOS 27 (`26A428`) on 2026-09-14, and they all hold.**
> Everything here was originally measured on a 27 *beta* (`26A5388g` family), so
> the probe was re-run sandboxed against final 27: enumeration still returns the
> full table, `proc_listpids` is still denied, `proc_pid_rusage` is still self
> only, and 256 other-uid processes produced exactly 256 denials. Output is in
> `probe/FINDINGS.md`. **macOS 26 measures the same** (TASK-45, done): the same
> probe runs sandboxed on a `macos-26` runner via
> `.github/workflows/sandbox-probe.yml` and every answer matches, so these facts
> now hold on 26.6.2, 27 beta and 27 final alike.
>
> **The toolchain is also still a beta.** `/Applications/Xcode-beta.app` (27.0,
> `27A5218g`) is what `xcode-select` points at; `/Applications/Xcode.app` is
> 26.6 and is the same stable Xcode CI uses. Switching to it locally needs no
> download — it is already installed — and would make local builds and CI agree.

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
- **A smoothed signal must not carry a duration threshold shorter than its own
  smoothing.** `getloadavg` averages over a minute, so requiring it to hold for
  60 s counts the same history twice — the same class of error as presenting a
  cumulative total as a rate. Check what a signal already averages before
  putting a clock on it. (FR-006, TASK-103)
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

**A design exists, and it has been revised once against real use.** `design/`
holds the Claude Design canvas and 28 rendered artboards, with `TASK-65` as the
conformance umbrella. Treat the mocks as **directional**: structure, information
hierarchy and copy intent are the requirement; the placeholder machine and
invented numbers are not. `design/README.md` is the index — read it before
touching a screen, because it records which turn supersedes which.

**The remote design project is authoritative; `design/` is a reference import.**
Never push a local canvas over it (a session came within one approval of
destroying Claude Design's work that way). `DesignSync get_file` **cannot fetch
the canvas** — it caps at 256 KiB and the document is 298 KB, and it truncates
without an error. Ask the product owner to export the project instead. Details
and the project UUID are in `design/README.md`.

**The design is closed as of 2026-09-09.** Turns 5 and 6 answered everything
outstanding and the commentary was then stripped, leaving screens and the rules
that are specifications rather than argument — 4b's allowed/never list for the
run-queue quantity, and 5c's watched/crossed/not-watched grammar. Do not expect
further design turns without a new question.

Turn 4 (2026-08-31) was superseded in part by turn 5, but its surviving word: it revised the Now table to four
columns, gave the state tiles a hold duration, replaced the repeated-quit
incident with a lifecycle record, endorsed the built menu bar icon over its own
earlier drawing, and retracted three claims measurement had forbidden — one of
which ("stored encrypted") this repo had already banned. **4b, the run-queue
screen, must not be built from its own numbers** — see the run-queue entry
below.

**The largest live risk is unverified UI.** A great deal is built and very
little of it has been looked at. Do not treat any of these as done; a session
that cannot look must leave the criterion unchecked and say so, because several
sessions have now been burned inferring an on-screen fact from a green test.

The UI work that is blocked on a person at the screen, as of 2026-09-05:

| Task | What needs looking at |
|---|---|
| `TASK-65.24` | **Never seen on screen at all**: Settings' four tabs, the mute sheet, the export sheet, All processes |
| `TASK-65.22` | Apps & Processes — truncated names, a seven-line footer where the design has one, the long tail not aggregated. Partly addressed by the four-column change; needs re-checking against it |
| `TASK-65.23` | Menu bar icon polish — the glyph sits off-centre in its slot, the badge is illegible at 16 pt |
| `TASK-65.20` | First run never comes forward under `LSUIElement`, so nobody sees it |
| `TASK-83` | The Incidents sidebar row is spoken as "1" — the badge has replaced its name |
| `TASK-97` | The Now and Apps tables may not fit the window's minimum width. The four-column change cut the Apps table's minimum from ~644 pt to ~504 pt, so this may already be resolved — **measure, do not assume** |
| `TASK-15` | Accessibility baseline (parked, high). Needs a person with VoiceOver; several UI criteria elsewhere wait on it |

Everything built in the 2026-09-03 session — the four-column table, the state
tiles' hold duration, the severe filled badge — is **tested but unseen**.

- **On-screen verification** is the whole of the critical path. The tasks each
  carry a written, step-by-step check in their notes; TASK-75, TASK-51.1 and
  TASK-65.20 are the ones to do first, in that order, because the other checks
  are only meaningful once the window is the right size.
- **TASK-103** (spike, high) — run-queue pressure. Its proposed threshold is
  **refuted by measurement**; see the run-queue entry under Settled below.
  Blocked on a deliberately oversubscribed run, which needs the owner's
  go-ahead because it makes the machine unusable for minutes.
- **TASK-101** (spike, high) — the six challenges from two weeks of real use.
  C-01 (demote relaunch), C-02 (run-queue) and C-03 (live surfaces) are
  answered and acted on. **C-04, C-05 and C-06 are still unanswered.**
- **TASK-108** — notification volume. The "fewer notifications" dial the owner
  asked for already exists as `AlertSensitivity.relaxed`; the defect is that
  nobody can find it. Do not add a second control.
- **TASK-58** — richer popover over FR-005 history. Large; the user wants to scope
  it in conversation first. **Do not start it unprompted.**
- **TASK-38** — named configuration profiles (FR-025, FR-026). Design 4a argues
  profiles should be **dropped**: they put a mode switch in the navigation list,
  so a mis-click silently changes what counts as a slowdown. The build never had
  them. Needs a decision to close or to keep.
- **TASK-45 is done** (2026-09-14) — **macOS 26 answers the same as 27, so the
  enumeration strategy ships on both.** Measured sandboxed on 26.6.2 via
  `.github/workflows/sandbox-probe.yml`: sysctl permitted (545 pids),
  `proc_listpids` denied, `proc_pid_rusage` self only, and 247 other-uid
  processes against exactly 247 denials. `decision-1` needs no escalation and
  FR-009/FR-043 are no more restorable on 26 than on 27. It answers the
  sandbox-*policy* question only — the runner is 26.6.2, not 26.0, and is a
  virtualised 3-core machine, so nothing about physical hardware or P/E
  asymmetry on 26 is covered.
- **TASK-50** — the Apple DTS question on `sysctl KERN_PROC_ALL`. The user's
  action, not a work item.

Settled on 2026-09-03/05, so nobody re-derives them:

- **The run-queue threshold is refuted.** FR-006's proposed amendment breaches
  above 2.0 runnable threads per core held for 60 s. Measured: an ordinary
  capped, nice'd build sits at a **median of 2.87 per core and peaks at 8.68**,
  breaching 2.0 on 59.2% of samples — a condition that fires whenever you
  compile. Two further facts outlive the threshold question. **141 of 142**
  high-queue build samples had pagein above 1 MB/s, so macOS's load average is
  dominated by uninterruptible I/O waits under load and the condition can never
  be described as a CPU one. And `getloadavg` is a **1-minute exponentially
  weighted average** — it held 7.43 for 16 s at build start while CPU busy swung
  62–78% — so **never put it behind a sub-minute duration threshold**, which
  counts the same history twice. The founding observation still stands (twelve
  per core was unusable at 44–51% CPU), so the boundary is real and simply much
  higher. FR-006's amendment stays **proposed**. `probe/Sources/loadavg-probe.swift`.
- **Repeated relaunch no longer opens an incident** (FR-046 amendment 5,
  TASK-102). `IncidentCondition.opensAnIncident` is the rule and the case is
  the only `false`; `IncidentCondition.opening` is the set the detector
  watches. The case is **kept, not deleted** — it is in the persisted schema,
  it still records, and a machine with a genuine crash-loop makes the decision
  cheap to revisit. Nine days had produced ten of these and no other incident,
  all ten false.
- **A notification banner says only what is wrong.** The clause saying what was
  *not* wrong ("Memory pressure stayed normal") is gone: it spent a banner's
  last line on a negative finding, and the same clauses are already derived in
  `IncidentSummary.ruledOut` and shown under "Ruled out" in the incident detail.
  One fact, one home.
- **The Apps table is four columns** and the one CPU figure is the 60 s mean,
  which is also the visible sort key. The instantaneous reading survives as the
  sparkline's live end and in the accessibility label — never as a second
  number beside the first, which invites a meaningless subtraction.
- **Severe fills the menu bar badge.** It was previously separated from an
  ordinary open incident by colour alone, which FR-034 forbids.

Settled on 2026-08-09, so nobody re-derives them:

- **TASK-75** — the window grew to 3599 pt because a `NavigationSplitView`
  proposes no width when asking its detail column for an ideal size, so caption
  paragraphs under `fixedSize(horizontal: false, vertical: true)` wrap to about
  one word per line and answer with thousands of points. **It was never the row
  count** — an empty store demanded 9529 pt. The offscreen harness *can* answer a
  window-sizing question, but only by asking what the content demands
  (`sizeThatFits` with unconstrained height), never by supplying a size and
  watching SwiftUI clamp. The main window id is now `main-v2` so AppKit cannot
  restore the saved bad frame.
- **TASK-72** — incidents persist, schema-versioned, 30-day default, retention
  enforced every sample. Dates are encoded numerically: ISO-8601 truncates to
  whole seconds and made `Incident.covers()` disagree after a round trip.
- **TASK-71** — repeated quits open an incident with a sustained duration of
  zero, deliberately: `LifecycleTracker.minimumExits` already is FR-006's guard.
- **TASK-74** — the inventory holds its order for 10 s. Reentrancy warnings went
  from 12–14 per 20 s to 1–2. `StableOrder` holds positions, never rows, so the
  numbers stay live while the order is held.
- **The menu bar icon is not on a faster path than the window** (TASK-65.14).
  Both read the same `@Observable` store on the same main actor, and the icon's
  rate limiter puts it up to 2 s further behind. The design's claim to the
  contrary is deleted and a test stops it returning.
- **TASK-73** — `probe/seam-reachability.sh` is the standing check for
  built-but-unwired capabilities. Run it before finishing anything that adds
  public framework surface. Its blind spot is name collisions between types.

Earlier: TASK-62 (cold-start identity cut ~70%),
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

- Whether summaries use an on-device model or deterministic templates (FR-013).
  The owner is open to it and requires whatever ships in macOS 26/27, so
  Foundation Models is the candidate. Spike is `TASK-104`, not started.
- **C-04, C-05 and C-06** of the six challenges (`TASK-101`) are unanswered.
- Whether run-queue pressure becomes a condition at all, now that its proposed
  numbers are refuted and its signal turns out to be dominated by I/O wait and
  smoothed over a minute. The founding observation stands; the mechanism for
  acting on it does not yet. See `TASK-103`.
- Whether named configuration profiles (FR-025/FR-026, `TASK-38`) should be
  dropped, as design 4a argues. The build never had them.
- Whether to amend the spec for an optional user-installed helper. The Mac App
  Store edition of iStat Menus reaches sensors only through a separately
  downloaded, non-sandboxed binary — the pattern A-03/A-04/FR-037 currently
  forbid. Raised and **set aside by the user**; do not act on it.

Settled, and not to be re-opened:

- **Incident history persists across restarts, on by default, kept 30 days**
  (user-adjustable 7/30/90) *and* count-bounded at
  `IncidentHistoryStore.defaultLimit`. Written to `incidents.json` in the app's
  Application Support directory with a schema version. Retention is enforced on
  every write and on the sampling loop, not only when a screen is open. The
  FR-005 metric sample series is deliberately **not** persisted. Never say the
  store is encrypted — say "in MacSlowdown's own container, which no other app
  can read". See the settled-decision subsection under FR-029 and TASK-72.
- **FR-050 post-action verification is staged, not wired** (product owner,
  2026-08-09, TASK-78). `ActionVerifier.verify` has no caller on purpose: every
  action this build offers is observational — activate, reveal, open Activity
  Monitor, copy diagnostics — because FR-020–024 are deferred, so there is no
  outcome to measure and a before/after around one of them would be the false
  causal claim FR-050 exists to prevent. It is connected by whatever task lifts
  that deferral, and nothing sooner. Reason recorded in
  `probe/seam-allowlist.txt` and at `ActionVerifier` in
  `Metrics/Sources/ActionOutcome.swift`.
- Build system is **Tuist**; manifests are the source of truth. Test framework is
  **Swift Testing**. **CI runs on GitHub Actions** — `.github/workflows/tests.yml`
  builds and runs the full suite on a `macos-26` runner on every push to main
  (unsigned, so it cannot exercise the sandbox; it skips the four
  machine-sensitive tests). `.github/workflows/sandbox-probe.yml` runs the Tier 0
  probe sandboxed on macOS 26 and asserts its four load-bearing answers. Both are
  deliberately unscheduled: Actions storage is an account-wide quota shared with
  every other repository.
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

**Per-app network attribution (FR-051) is measurably impossible** (TASK-40,
`probe/FINDINGS.md`). No public API returns a per-process byte counter at all —
`libproc` FD enumeration reads 445/447 own-uid processes unsandboxed and 1/447
sandboxed, the PCB tables return zero entries either way, and `socket_info`
carries queue occupancy rather than a differenceable counter. `nettop` works only
through a private framework. Aggregate, machine-wide throughput **is** available
with no extra entitlement, so FR-051 can be narrowed exactly as FR-009 was — but
that narrowing is a spec change and is **not yet applied**; proposed wording is
in TASK-40's notes awaiting the product owner.

Two rules that came out of it: **`lo0`'s counters wrap at 2^32 even through the
64-bit `if_data64` field** (measured mid-transfer; naive subtraction gave
1.8×10^19), and loopback must be reported separately or one local file copy reads
as a WAN transfer. Also **the "measurability is decided by uid, exactly" rule does
not generalise to file descriptors** — FD enumeration is one of the few places the
sandbox itself is the binding limit.

Still unproven: unresponsiveness (FR-046). Validate with a spike before designing
features that depend on it; if a signal isn't reliably available, the spec's
answer is to omit the feature, not approximate it.

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
