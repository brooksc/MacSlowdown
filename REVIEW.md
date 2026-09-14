# Reviewing MacSlowdown — a reading order

Written 2026-09-05, revised 2026-09-09, for a reviewer coming to this project cold, who has been asked to
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

> **§1.2 was rewritten, and the new one is the thing to attack.** It used to be
> incident-centred — success meant a user could open an incident afterwards and
> understand it. Two independent reviews found the same fault: that names an
> intermediate usability result, not an outcome. Someone who reads an incident,
> understands it perfectly, and then does nothing differently has not been helped.
>
> Success now turns on **supporting a decision**: understanding the observed conditions
> *and their limits*, choosing a next step, and telling whether things improved — without
> unwanted interruption during work the user expected to be heavy. That last clause makes
> interrupting wrongly a failure of the product rather than a settings problem for the
> user.
>
> The fair attack on the new definition is that it is much harder to satisfy and the
> product may not satisfy it anywhere except the memory case, where there is genuinely
> something to close. Whether any other scenario supports a *decision* rather than
> merely an explanation is open, and it is the question this project most needs
> answered. `design/live-surfaces.md` carries the argument that got us here.

### 2. The scenarios

`scenarios.md` — **seven situations a person is actually in**, each stating the issue as
they experience it, what they do, what it enables, what they walk away with, and *how it
fails*. Read it second; it is short, and it is the closest thing to a statement of what
this product is for.

It carries no requirement numbers, no thresholds and no screens on purpose: if a sentence
in it could only have been written by someone who had seen the code, it was describing our
progress rather than the user's problem. The failure modes are the substantive half — the
happy paths were never the risk.

Supporting material:

| Read | What it gives you |
|---|---|
| `requirements.md` §1 (the five questions) | The intended arc from "my Mac feels slow" to an answer |
| `requirements.md` §3 | Users and roles |
| `design/screens/*.png` — especially `5a`, `5b`, `5d`, `6a` | The screens those scenarios became |
| `requirements.md` §9 | Release phasing, which encodes an assumed order of value |

The two scenarios to read first are **S-4** (heavy work started on purpose, which is
indistinguishable from a real slowdown by any measurement) and **S-7** (the machine is
struggling and nothing we watch has crossed a line). Between them they contain the
product's central problem.

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
| `design/README.md` | The design index: 28 artboards across four turns, which supersedes which, and where the cloud project lives |
| `Metrics/Sources/` | The framework — sampling, identity, grouping, attribution, detection, summarisation |
| `MacSlowdown/Sources/` | The app — menu bar, windows, presentation rules |
| `requirements.md` §5 | The functional requirements — 58 present, numbered to FR-065, each with acceptance criteria. The gaps are deliberate: FR-020–024 (process control) are deferred and escalated, FR-048 (wakeups) was dropped as unmeasurable. FR-063–065 are the newest and the most load-bearing: a measurement is not an experience, the user may report a slowdown, and three kinds of confidence stay apart |

Build and test commands are at the top of `CLAUDE.md`. **1317 tests pass.** Three tests
measure the real machine and fail on a busy one — `CLAUDE.md` names them; re-run in
isolation before treating one as a regression.

---

## Where the weak joints are

Offered so the review can go straight at them, not to pre-empt its conclusions. Revised
2026-09-09; four of the original seven have closed and the list is shorter and sharper
for it.

1. **Almost nothing has been seen running.** This is now the largest risk by a wide
   margin. The build has changed substantially — a new opening view, a coverage record,
   a rewritten first run, new popover states, condition-scoped suppression — and every
   screen-dependent criterion is unchecked. `CLAUDE.md` carries the table. A green test
   is not a seen screen and several sessions have been burned confusing the two.
2. **The product has still never produced a verified true positive.** It has produced
   incidents since the detector defect was fixed, but nobody has judged whether they were
   right. The instrument that would settle it — the user reporting a slowdown as they
   feel it — is now built and has collected nothing yet. Until the field trial
   (`TASK-114`) runs, every threshold in this product is set by argument.
3. **The success definition changed and the product has not caught up everywhere.**
   §1.2 now turns on supporting a *decision*, not on reading an incident. Whether the
   built product actually supports a decision anywhere except the memory case is an open
   question and a fair thing to attack.
4. **A distinct product and a paying audience are unproven.** "Monitoring plus history
   plus alerts" is an occupied feature set; the claim is that the reduction in
   interpretation effort is the product, and nothing measures that yet.
5. **App Review risk is unresolved and untestable** (§10.3). Process enumeration uses a
   sysctl Apple withdrew on iOS 9. `TASK-50` asks the question and has never been sent —
   it gates no code, which is exactly why it keeps slipping.

Closed since the first version of this list, and worth knowing were once open: the
missing scenarios document (now `scenarios.md`), the run-queue threshold (refuted by
measurement, resolved as a displayed figure rather than a condition), and the three
unanswered challenges C-04/C-05/C-06 (all closed in spec v1.6).

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
| `requirements.md` | **Authoritative** for scope and behaviour (see its §11). v1.6 |
| `CLAUDE.md` | Operating rules, verified platform facts, current state, UI blockers |
| `scenarios.md` | Seven user situations and how each one fails. Read second |
| `REVIEW.md` | This file |
| `design/README.md` | Design index, turn-by-turn, plus the cloud project details |
| `design/live-surfaces.md` | The argument behind FR-057–FR-062. Historical: it has been folded into the spec, and is kept because it carries the reasoning the requirements table does not |
| `design/screens/*.png` | 28 rendered artboards |
| `design/icons/README.md` | App-icon directions |
| `probe/FINDINGS.md` | Measured platform capability — the empirical base |
| `probe/SEAM-AUDIT.md` | Built-but-unwired capabilities and their staging reasons |
| `probe/seam-allowlist.txt` | Deliberate exceptions, each with a written reason |
| `probe/feedback-swiftui-table-reentrancy.md` | A SwiftUI defect report |
| `.backlog/` | Tasks, milestones and decision records (MCP server `backlog`) |
| `.backlog/decisions/decision-1 - Enumerate-processes-via-sysctl-KERN_PROC_ALL-accepting-the-durability-risk.md` | The process-enumeration risk acceptance |

Backlog is read through the `backlog` MCP server — `task_list`, `task_view`. Milestones
`m-0`…`m-4` map to the spec's phases.
