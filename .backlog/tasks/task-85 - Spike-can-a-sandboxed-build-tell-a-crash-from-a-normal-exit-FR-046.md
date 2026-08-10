---
id: TASK-85
title: 'Spike: can a sandboxed build tell a crash from a normal exit? (FR-046)'
status: Done
assignee: []
created_date: '2026-08-10 02:05'
updated_date: '2026-08-10 02:05'
labels:
  - spike
  - core
milestone: m-2
dependencies: []
modified_files:
  - probe/Sources/exit-status-probe.swift
  - probe/Sources/victim-app.swift
  - probe/run-exit-status-probe.sh
  - probe/FINDINGS.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LifecycleTracker infers an exit from a (pid, start time) vanishing between two sysctl KERN_PROC_ALL snapshots. That carries no status, so the interface can say "quit unexpectedly" about a process that simply finished — the root of TASK-84, where `yes`, `swift-frontend` and `mdworker_shared` exiting is ordinary churn.

If exit status were reachable it would change the product materially: a crash is worth reporting at one occurrence, where a normal exit is not worth reporting at three.

Candidates measured, all public API, sandboxed and unsandboxed, against terminations the harness manufactured in processes it created itself (FR-037 forbids signalling anything else):

- kqueue EVFILT_PROC with NOTE_EXIT, NOTE_EXITSTATUS, NOTE_EXIT_DETAIL, NOTE_SIGNAL
- proc_pidinfo PROC_PIDT_SHORTBSDINFO across the exit
- extern_proc.p_xstat in the process table the product already samples
- NSWorkspace.didTerminateApplicationNotification and NSRunningApplication

Crash logs were deliberately not touched: /Library/Logs/DiagnosticReports is already established as unreadable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A yes/no answer to "can a sandboxed build distinguish a crash from a normal exit", backed by counts rather than impressions
- [x] #2 Every candidate API measured both sandboxed (signed .app, launched with open) and unsandboxed, with the difference stated
- [x] #3 A control that separates total unavailability from a parentage or uid restriction — i.e. a process the probe forked itself as well as processes it did not
- [x] #4 If the answer is no, the blocking restriction named: sandbox, uid, or parentage
- [x] #5 If the answer is yes, what is learned, how reliably, and the per-sample cost against LifecycleTracker's current zero
- [x] #6 Proposed FR-046 wording written down if the result implies a spec change, and not applied
- [x] #7 Probe source and a reproducible harness committed under probe/, and the finding appended to probe/FINDINGS.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Verdict

**No.** A sandboxed build cannot tell a crash from a normal exit for any process
it did not itself fork. The exit *event* is available and is better than what we
do today; the exit *status* is not. Full write-up in `probe/FINDINGS.md`
("Crash vs. normal exit (`exit-status-probe.swift`) — FR-046").

macOS 27.0 (26A5388g) / M2. Four 60 s runs, ~765 processes each, unsandboxed and
in a signed sandboxed `.app` launched with `open`. Every process terminated was
one the harness created.

## kqueue EVFILT_PROC — the answer

The status-bearing mask (`NOTE_EXIT|NOTE_EXITSTATUS|NOTE_EXIT_DETAIL|NOTE_SIGNAL`)
is refused at **attach** time with `EACCES`. It does not fail silently later.

| registration | unsandboxed | sandboxed |
|---|---|---|
| status mask, own-uid | 520/526 | **3/527** |
| status mask, other-uid | 0/238 | 0/236 |
| bare `NOTE_EXIT`, own-uid | 526/526 | 527/527 |
| bare `NOTE_EXIT`, other-uid | 238/238 | 236/236 |

The sandboxed 3 are exactly the probe's own forked children. `sleep` and `bash`
processes the harness had just spawned from the same shell — same uid, same
session — are refused identically to `WindowServer`.

**The sandbox is the binding limit, parentage is the residual.** That is the
opposite of the usual pattern (per-process CPU is denied by uid equally
sandboxed and unsandboxed, so the sandbox costs nothing there). Here it costs
517 of 520.

Delivery matched attach exactly: sandboxed, 3/3 statuses, all our own children,
0 statuses from the 16–23 stranger exits the bare kqueue saw in the same
windows. Where status *is* delivered it is complete and correct — `data` is a
wait(2) status, checked against `waitpid` ground truth every run (SIGSEGV → 11,
`exit 7` → 1792, SIGTERM → 15).

## Secondary routes

- **`NOTE_SIGNAL`**: rides the same refused mask, and is useless anyway — 185
  events in one run, every one `data = 0` with no signal number in `fflags`, and
  it fires constantly for healthy processes.
- **`proc_pidinfo` / `PROC_PIDT_SHORTBSDINFO`**: `ESRCH` for our own child while
  it was still an unreaped zombie, `ESRCH` after reaping, `ESRCH` for a pid that
  never existed. Dead end.
- **`extern_proc.p_xstat`** (already in the sysctl row we sample): genuinely
  readable sandboxed for strangers, decoded correctly every time — but the catch
  rate is fatal. At 4 Hz, 8–20× the product's cadence, it caught 2 of 23 stranger
  exits; at the instant `NOTE_EXIT` fired, 0 of 9 strangers were still listed.
  Zombies linger only when the parent is slow to reap, which is a property of the
  parent, not of how the child died. Corroboration at best, never a basis.
- **`NSWorkspace` / `NSRunningApplication`**: the notification carries only an
  `NSRunningApplication`, whose whole property surface (14 properties, all
  enumerated in FINDINGS) has no exit status, no code, no termination reason —
  only `terminated: Bool`. Dead end on API surface alone. Whether the
  notification is even delivered is **not established**: four configurations all
  reported zero terminations *and* zero launches, so the plumbing control failed;
  likely `LSUIElement` apps do not generate them, and confirming that needs a
  Dock app on screen.

## Worth acting on anyway (separate task, not done here)

Bare `NOTE_EXIT` attaches for **every** process sandboxed, other-uid included
(236/236), and other-uid exits were observed delivered. A rare exception to
"measurability is decided by uid, exactly" — we can watch `WindowServer` exit
even though we can never read its CPU. Cost: **0.4 ms to register 763 pids**,
one fd, event-driven, knote auto-deletes on fire.

`LifecycleTracker` could take its exit events from that instead of snapshot
diffing: cheaper, exact, and it catches processes that start and end between two
sweeps. It changes *when we notice*, not *what we may claim*.

## Proposed FR-046 wording (NOT applied)

Add to FR-046 as a stated limitation:

> Termination status is not observable. `kqueue`'s `EVFILT_PROC` accepts
> `NOTE_EXITSTATUS` only for a process the app itself forked — measured, 3 of 527
> own-uid processes in a sandboxed build, against 520 of 526 unsandboxed — so a
> Mac App Store build cannot distinguish a crash from an ordinary exit for any
> process it did not create. The app must therefore never describe an observed
> termination as a crash, a failure, or "quit unexpectedly". The only supported
> statement about a `(pid, start time)` that is no longer present is that it is
> no longer running, and the only supported pattern claim is repeated relaunch
> over a bounded window, labelled a heuristic hypothesis under FR-038.

## Constraints observed

No process the probe or harness did not create was signalled. The victim `.app`
is `SIGKILL`ed rather than `SIGSEGV`ed because CrashReporter's default
`DialogType` would put a "quit unexpectedly" alert on screen. Nothing was put on
screen; the victim app is `LSUIElement` and everything was launched with
`open -g`.
<!-- SECTION:NOTES:END -->
