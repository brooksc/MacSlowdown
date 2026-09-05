# Reviewing MacSlowdown — a reading order

Written 2026-09-05 for a reviewer coming to this project cold, who has been asked to
start at the **thesis and the scenarios**, then the **approach**, and only then the
**implementation**.

This document is a map and an honest account of where the weak joints are. It is not
itself authoritative about anything: where it and `requirements.md` disagree, the
spec wins.

---

## Read in this order

### 1. The thesis — what problem this claims to solve

| Read | Why |
|---|---|
| `requirements.md` §1 | Problem statement, the five questions the product exists to answer, primary user outcomes, and the success definition |
| `requirements.md` §2 | Purpose and product boundary — what it deliberately is *not* |
| `requirements.md` §4 | Global assumptions and design constraints (A-01…), which constrain everything after |

**The five questions in §1 are the thesis in its most compact form.** Everything else
in the spec is downstream of them.

> **Start your review at the tension in §1.2.** The success definition is
> incident-centred: the product succeeds when "a user can open an incident and
> understand what happened." After two weeks of real use, **every piece of product-owner
> feedback concerned something else** — what the popover says right now, whether a
> number is an instant or a trend, whether a status word holds still, whether an
> ordering can be trusted. There was no legitimate incident to read; the ten recorded
> were all false positives from one condition, since demoted.
>
> `design/live-surfaces.md` makes this argument in full and is the single most useful
> document for a thesis-level review. It led to FR-057–FR-062. What it did **not** do
> is revisit §1.2 itself, which still defines success in terms of the surface nobody
> used. That question is open and nobody has answered it.

### 2. The scenarios — and an honest gap

**There is no scenarios document, and this is a real gap rather than an omission from
this map.** The spec has §1's five questions, §3's users and roles, and per-requirement
acceptance criteria, but no user journeys or worked scenarios. The closest things:

| Read | What it gives you |
|---|---|
| `requirements.md` §1 (the five questions) | The intended arc from "my Mac feels slow" to an answer |
| `requirements.md` §3 | Users and roles |
| `design/screens/*.png` — especially `1b`, `1e`, `1h`, `4a` | The nearest thing to scenarios that exists: concrete screens for the triage moment, the evidence room, the unattributable case, and the live monitor |
| `requirements.md` §9 | Release phasing, which encodes an assumed order of value |

A reviewer may reasonably conclude that writing the scenarios is the first missing
piece of work. If so, `1h` (the incident we cannot attribute) is the scenario most
worth writing first, because roughly **40 percentage points of busy CPU are
unattributable in a Mac App Store build** and that is the hard case the product is
least equipped for.

### 3. The approach — what was decided, and what the machine actually allows

This is where the project's real substance is, and most of it is *measured* rather
than assumed.

| Read | Why |
|---|---|
| `probe/FINDINGS.md` | **The most important document in the repo after the spec.** Every platform capability, measured against a signed sandboxed build rather than assumed. Long; skim the bold rules |
| `CLAUDE.md` — "Verified sandbox facts" and "Correctness rules that are easy to get wrong" | The same findings compressed to operating rules |
| `requirements.md` §7 | Mac App Store capability matrix — what the distribution model costs |
| `requirements.md` §10 | Open decisions (§10.0), the six challenges (§10.1), settled matters (§10.2), the single largest risk (§10.3) |
| `.backlog/decisions/decision-1 - …durability-risk.md` | Process enumeration via `sysctl KERN_PROC_ALL`, accepted with known risk |
| `probe/SEAM-AUDIT.md` | Capabilities built but not wired, and why each is staged |

**The constraints that shape everything, and that a reviewer should test the thesis
against:**

- Measurability is decided by **uid**, exactly. Other-uid processes are denied
  identically sandboxed and unsandboxed. ~40 points of busy CPU is unattributable.
- **No process control at all** — not even a dormant code path (A-03, A-04, FR-037).
  Every action the product offers is observational.
- Application **hangs are undetectable**. Per-app **network attribution is
  impossible**. Per-process **disk I/O and wakeups are blocked**.
- Identity is `(pid, start time)`; PID recycling is observed in practice, not
  theoretical.

A fair thesis-level question: given that the product cannot attribute ~40% of activity,
cannot see hangs, and cannot act on anything it finds — **is the incident-report framing
the right one, or is the honest live monitor the actual product?** Nobody has been asked
this directly.

### 4. The implementation — last

| Read | Why |
|---|---|
| `CLAUDE.md` — "Where the work stands" | Current state, and the table of UI work blocked on a person at a screen |
| `design/README.md` | The design index: 30 artboards across four turns, which supersedes which, and where the cloud project lives |
| `Metrics/Sources/` | The framework — sampling, identity, grouping, attribution, detection, summarisation |
| `MacSlowdown/Sources/` | The app — menu bar, windows, presentation rules |
| `requirements.md` §5 | The functional requirements — 55 present, numbered to FR-062, each with acceptance criteria. The gaps are deliberate: FR-020–024 (process control) are deferred and escalated, FR-048 (wakeups) was dropped as unmeasurable |

Build and test commands are at the top of `CLAUDE.md`. **1141 tests pass.** Three tests
measure the real machine and fail on a busy one — `CLAUDE.md` names them; re-run in
isolation before treating one as a regression.

---

## Where the weak joints are

Offered so the review can go straight at them, not to pre-empt its conclusions.

1. **The success definition may describe the wrong surface** (§1.2 vs
   `design/live-surfaces.md`). The most consequential open question in the project.
2. **No scenarios exist.** Requirements were written from a problem statement directly
   to acceptance criteria.
3. **One condition has produced every incident ever recorded, and all were false.**
   Repeated relaunch, now demoted (FR-046 amendment 5). The product has therefore never
   produced a true positive of any kind on the owner's machine — which is either a
   thresholds problem, a machine that is genuinely fine, or evidence that the incident
   model does not fit.
4. **The proposed fix for #3 was refuted by measurement.** Run-queue pressure was meant
   to catch what CPU busy misses; its threshold fires through every compile, its signal
   is dominated by I/O wait, and it is smoothed over a minute (`TASK-103`,
   `probe/FINDINGS.md`). The founding observation still stands and has no mechanism.
5. **Most of the UI has never been looked at.** See the blocked-on-screen table in
   `CLAUDE.md`. A green test is not a seen screen, and several sessions have been burned
   confusing the two.
6. **Three of the six challenges are unanswered** — C-04, C-05, C-06 in
   `requirements.md` §10.1.
7. **App Review risk is unresolved and untestable** (§10.3). Process enumeration uses a
   sysctl Apple withdrew on iOS 9; `proc_listpids` is explicitly denied. No Apple
   statement blesses the alternative.

## Conventions worth knowing before you judge the code

- **Never fabricate a measurement.** Unavailable data is labelled unavailable, never
  approximated or shown as zero.
- **Every conclusion is labelled** measured fact / derived calculation / heuristic
  hypothesis / user-provided (FR-038).
- Forbidden vocabulary: "optimize", "clean", "boost", "free up memory", "fix", and —
  for process exits — "crashed", "quit", "unexpectedly", "hung".
- Comments here carry *why*, often at length, and frequently record a measurement or a
  defect that motivated the code. They are deliberately not decoration.

## Document paths, in one list

| Path | What it is |
|---|---|
| `requirements.md` | **Authoritative** for scope and behaviour (see its §11). v1.4 |
| `CLAUDE.md` | Operating rules, verified platform facts, current state, UI blockers |
| `REVIEW.md` | This file |
| `design/README.md` | Design index, turn-by-turn, plus the cloud project details |
| `design/live-surfaces.md` | The argument behind FR-057–FR-062. Key for a thesis review |
| `design/screens/*.png` | 30 rendered artboards |
| `design/icons/README.md` | App-icon directions |
| `probe/FINDINGS.md` | Measured platform capability — the empirical base |
| `probe/SEAM-AUDIT.md` | Built-but-unwired capabilities and their staging reasons |
| `probe/seam-allowlist.txt` | Deliberate exceptions, each with a written reason |
| `probe/feedback-swiftui-table-reentrancy.md` | A SwiftUI defect report |
| `.backlog/` | Tasks, milestones and decision records (MCP server `backlog`) |
| `.backlog/decisions/decision-1 - Enumerate-processes-via-sysctl-KERN_PROC_ALL-accepting-the-durability-risk.md` | The process-enumeration risk acceptance |

Backlog is read through the `backlog` MCP server — `task_list`, `task_view`. Milestones
`m-0`…`m-4` map to the spec's phases.
