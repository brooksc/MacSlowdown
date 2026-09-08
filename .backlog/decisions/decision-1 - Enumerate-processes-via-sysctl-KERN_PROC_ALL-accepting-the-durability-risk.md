---
id: decision-1
title: 'Enumerate processes via sysctl KERN_PROC_ALL, accepting the durability risk'
date: '2026-08-02 05:56'
status: accepted
---
## Context

MacSlowdown needs the list of running processes. `proc_listpids` is explicitly
denied under App Sandbox and Apple DTS has stated no entitlement lifts it.
`sysctl KERN_PROC_ALL` is a separately gated operation that works, uses only
public API, and requires no entitlement beyond `com.apple.security.app-sandbox`.
All of this is measured in `probe/FINDINGS.md`.

Two risks were identified before deciding:

1. **App Review.** No Apple statement blesses sysctl as the sanctioned
   alternative, and a reviewer could read "enumerate the process table after the
   designated API was denied" as working around the sandbox. Research found **no
   precedent of any app being rejected for this**, and rejections in this area
   cluster around entitlement requests, of which we make none. a third-party menu bar monitor 7 and
   Pulse both ship per-process CPU on the Mac App Store, though neither confirms
   the mechanism — iStat's MAS build uses a separately installed Helper for some
   stats.

2. **Durability.** Apple deliberately closed this exact sysctl on **iOS 9**,
   with the stated rationale that apps "are not permitted to see what other apps
   are running". macOS has not followed and permits far more introspection —
   `ps`, `top` and Activity Monitor all exist for users — but the sandbox already
   gates sysctl per node, so closing `kern.proc` would require no new machinery.
   This is the sharper of the two risks: a rejection is discovered at submission,
   whereas an OS change breaks installs already in the field.

## Decision

**Use `sysctl KERN_PROC_ALL` and proceed.** The capability it unlocks is the
product; without a process list what remains is a gauge, which §1.2 of the
specification explicitly says is not the product.

The risk is accepted on the basis that it is reversible at bounded cost.

## Consequences

- **The seam stays minimal and swappable.** Enumeration lives in exactly one
  function, `ProcessSampler.processTable()`. Nothing in the module structure,
  identity model, grouping, attribution or UI depends on how the list arrives.
  Keep it that way: no caller should ever reach around it.

- **A fallback exists and is documented, not built.** `NSRunningApplication`
  returns 119 apps (113 with bundle identifiers) and `proc_pidinfo` succeeds for
  118 of those 119 pids, so enumeration could degrade to GUI applications while
  keeping real CPU and memory. Building it now would be speculative; the point of
  recording it is that the retreat is known, costed and short.

  The cost of that fallback is helper processes: Chrome's 23 renderers and
  Xcode's `swift-frontend` are not `NSRunningApplication` entries, so
  helper-heavy applications would show only their main process and under-report
  badly. Their usage would move into the unattributed bucket, which at least
  keeps the totals honest.

- **Failure must degrade honestly, not silently.** If a future macOS denies the
  call, `processTable()` returns empty. The interface must then say that process
  information is unavailable on this system, per FR-002, rather than showing an
  empty list that reads as "nothing is running". Tracked as a task.

- **The question is still worth asking Apple**, framed as durability rather than
  permission: is `sysctl KERN_PROC_ALL` expected to remain available on macOS,
  given it was withdrawn on iOS 9 for this use? Not a gate on any milestone.

- **Revisit if** macOS beta notes mention process-table restrictions, the call
  begins returning EPERM on a beta, or App Review raises it.
