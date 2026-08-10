---
id: TASK-78
title: 'Decide FR-050: wire post-action verification, or record why it is staged'
status: In Progress
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-10 02:00'
labels:
  - core
  - decision
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the TASK-73 seam audit (`probe/SEAM-AUDIT.md`).

FR-050 — "verify and report the outcome of user-directed remediation" — is built and tested in the framework and cannot occur in the running app.

- `ActionVerifier.verify` (`Metrics/Sources/ActionOutcome.swift:89`) has 22 test references and zero callers.
- `ActionPerformer.perform` (`MacSlowdown/Sources/ActionPerformer.swift:16`) returns an `ActionResult` and stops.
- `MonitorStore.record(action:)` (`MacSlowdown/Sources/MonitorStore.swift:165`) is written and documented, with a careful comment about not reading `false` as "it worked anyway", and is never called.
- `IncidentDetailView.verification` (`MacSlowdown/Sources/IncidentDetailView.swift:28`) defaults to `nil` and nothing supplies it.

**This is a decision, not automatically a defect.** With FR-020–024 deferred and escalated, every action the app offers is observational — activate, reveal in Finder, open Activity Monitor, copy diagnostics. None of them changes how a process runs, so arguably there is no outcome to measure, and staging the verification apparatus until there is would be correct.

The problem is that nobody wrote that down. Compare `PrivacySettings.persistAcrossRestarts`, which is staged properly: `AlertSettings.swift:215` states the reason, `SettingsView.swift:512` tells the user the truth, and `CLAUDE.md` lists the open question. Undocumented staging and having forgotten are indistinguishable six weeks later, which is the whole finding of TASK-73.

Two acceptable outcomes, and the product owner picks:

1. **Wire it.** `activate` is a real candidate: bringing a runaway app forward is followed by a measurable window, and "inconclusive" is an allowed result under FR-050.
2. **Stage it explicitly.** Add the reason to `probe/seam-allowlist.txt` and a note in `CLAUDE.md` under Undecided, and say in `ActionOutcome.swift` that the verifier waits on FR-020–024.

What is not acceptable is leaving 22 green tests standing in for a behaviour the product cannot perform.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The product owner has chosen between wiring FR-050 and staging it explicitly, and the choice is recorded
- [ ] #2 If wired: an action taken from the UI produces an ActionVerification through ActionVerifier.verify and MonitorStore.record(action:), and the incident detail shows the comparison window and the affected metric
- [ ] #3 If wired: a successful API return alone is never labelled an improvement, and an inconclusive outcome is shown as inconclusive (FR-050 acceptance criteria)
- [x] #4 If staged: probe/seam-allowlist.txt carries the reason and the task that will connect it, and CLAUDE.md records the open question
- [x] #5 probe/seam-reachability.sh reports ActionVerifier and verify either not at all, or as allowlisted with a reason
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Left for the product owner, deliberately.** This is the one item the TASK-73 audit produced that is a decision rather than a defect, and criterion #1 says so. Untouched on 2026-08-09.

One thing that changed since it was written, and it slightly strengthens the "stage it" case: `IncidentHistory.Entry` now reads an incident's own recorded suppressions (TASK-76), so `.suppressedByRule` is derivable and `.recoveredAfterAction` is the **only** outcome that still cannot occur. The gap is therefore narrow and well isolated rather than diffuse.

`probe/seam-reachability.sh` reports exactly one unexplained item as of this session: `ActionVerifier.verify`. Whichever branch is chosen closes the audit's last open thread.

## Decided: **staged**, branch `worktree-agent-a4fb2da76881b13b3` (commit dc11b36)

Product owner, 2026-08-09: stage FR-050, do not wire it. Criteria #1, #4, #5 met;
#2 and #3 are the wired branch and do not apply.

The reason, in the form the decision has to survive in: every action the app offers
is observational — activate, reveal in Finder, open Activity Monitor, copy
diagnostics — because FR-020–024 are deferred and escalated and FR-037 forbids even
a dormant path for them. There is no outcome to measure. Wiring the verifier to
"Reveal in Finder" would manufacture a before/after around an action that could not
have moved the number, which is precisely the false causal claim FR-050 exists to
prevent.

Written down in the three places TASK-73's model case (`PrivacySettings.
persistAcrossRestarts`) uses:

1. **`Metrics/Sources/ActionOutcome.swift`** — a doc comment on `ActionVerifier`
   saying it waits on FR-020–024, why the comparison rule is kept rather than
   deleted, and "do not call this to make the seam audit quiet".
2. **`probe/seam-allowlist.txt`** — the reason plus the task that connects it: the
   one that lifts the FR-020–024 deferral. Until such a task exists, TASK-78 holds
   the decision.
3. **`CLAUDE.md`** — under "Settled, and not to be re-opened", so the next session
   finds the decision rather than the silence.

### One thing learned about the audit tool itself

The first draft of the doc comment spelled `verify` in prose. `seam-reachability.sh`
matches by bare name, so the comment counted as a caller and the symbol vanished from
the report **entirely** — quieter, and wrong: the allowlisted line *is* the record,
and a symbol silently dropped is the failure mode TASK-73 exists to prevent. The
comment now avoids the token and says why in the comment itself.

### #5, measured

- Before: `1 unexplained; 3 allowed` — the unexplained one being `verify`.
- After: `0 unexplained; 4 allowed` — listed as allowlisted with a reason, which is
  the branch of #5 that keeps it visible.

The TASK-73 audit's last open thread is closed.
<!-- SECTION:NOTES:END -->
