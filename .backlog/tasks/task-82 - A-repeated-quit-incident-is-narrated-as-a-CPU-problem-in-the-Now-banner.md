---
id: TASK-82
title: A repeated-quit incident is narrated as a CPU problem in the Now banner
status: In Progress
assignee: []
created_date: '2026-08-09 22:54'
updated_date: '2026-08-09 23:58'
labels:
  - core
  - ui
milestone: m-2
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed on screen 2026-08-09 within minutes of TASK-71 landing, on a real incident (`screenshots/verify2/02-now.png`).

The banner headline read **"Repeated unexpected quits for 3 minutes, 15 seconds"** and the body underneath read:

> Calculated. 38% of busy CPU could not be attributed to any process we are permitted to measure…
> Likely, moderate confidence. Xcode was the largest measurable contributor while this was happening, peaking at 380% of one core…

That is a CPU narrative attached to a lifecycle incident. TASK-71's premise is precisely the opposite — 1o exists to say *an application is failing while the machine is fine* — and the task explicitly required that a new detector path must not convert `ResourceVerdict.notObserved` into an assertion either way.

TASK-71 did handle this, but only in `IncidentDetailView`, which "suppresses the unattributed-CPU narrative for an incident with no resource condition". The **banner** goes through `IncidentSummarizer.summarize`, which was not changed. So the same incident is described correctly on one screen and misleadingly on another — and the banner is the one the user sees first.

Two related observations from the same run, both worth deciding on rather than assuming:

- **"Bring Xcode forward" / "Bring claude forward" was offered as the action.** For a repeated-quit episode the leading CPU contributor is not the failing application, so the action names the wrong app. The relevant subject is the command that kept exiting.
- **The incident opened within roughly one minute of launch, twice, on an ordinary developer machine** (once attributed to Xcode, once to `BackgroundShortc…`). Three exits and matched relaunches inside the tracker's 15-minute window is easy to hit while builds are running. Whether that is a true positive or too eager a threshold is a judgement worth making against FR-006 with real observation, not by adjusting a number until it feels right. Record the reasoning either way.

Also seen in the incidents list: the row read **"Repeated unexpected quits — BackgroundShortc…"**. TASK-81 wired `ProcessNaming.nameIsTruncatedCommand` into the two inventory tables but not into incident rows, so a `p_comm` fragment is presented here as if it were the application's name (FR-002).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An incident whose only condition is repeated quits is not described in terms of CPU attribution on any surface, including the Now banner (FR-013, FR-038)
- [x] #2 The summariser and the incident detail derive that decision from one shared rule, so the two surfaces cannot disagree again
- [x] #3 notObserved is still never converted into an assertion that resources were fine
- [x] #4 The banner's action names the application that was quitting, not the largest CPU contributor
- [x] #5 The repeated-quit threshold is re-examined against FR-006 with the two real episodes observed on 2026-08-09, and the conclusion is recorded whether or not the threshold changes
- [ ] #6 An incident row shows a p_comm-truncated command as such rather than as the application's name (FR-002)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Criterion #4 only, done alongside TASK-65.21 on branch `worktree-agent-a1b87f5923549c5c5` (commit eaa667e). The rest of this task (the summariser narrative, #1/#2/#3/#5/#6) is owned by another agent and none of its files were touched — the change is confined to `MacSlowdown/Sources/NowPresentation.swift` and `MacSlowdown/Sources/MainWindowView.swift`.

The Now banner no longer offers "Bring <largest CPU contributor> forward" for a repeated-quit episode. `NowPresentation.leadingRelaunchPattern(_:)` returns the incident's lifecycle finding with the most exits (most recent wins a tie), and when one exists it is the subject of both the headline and the bring-forward action; the CPU leader is used only when there is no repeated-quit finding. Two decisions worth recording:
- The action resolves the **newest** live process with that command (`NowPresentation.familyMember(forCommand:in:)`), because the finding itself is that the earlier pids are gone — an older match would be a process that has already exited. Matching is on the command, since a relaunched process has a new identity by construction.
- When nothing by that name is running the button is **omitted** rather than shown and failed. A control whose only possible outcome is "that is no longer running" is worse than no control.
The headline for such an incident now reads "<command> keeps quitting and reopening", with the pattern's *association* confidence beside it (whether these exits are one application rather than unrelated processes sharing a truncated 16-byte command). Nothing claims to know why it exited. A command at the `p_comm` limit is shown through `ProcessNaming.labelled` so it reads as cut off (FR-002) — that covers the banner only; criterion #6's incident rows are untouched.
Tests in `MacSlowdown/Tests/IncidentBannerTests.swift`: a mixed CPU-saturation + repeated-quit incident is headlined by what quit and not by Xcode, and the newest-instance resolution. Full suite 1044 passing, 0 failing.

## The shared rule, and where it lives

`IncidentNarrative` (`Metrics/Sources/Incident.swift`), produced by `Incident.narrative`
and nowhere else. Two values — `.resource` and `.applicationLifecycle` — derived from
`conditions.contains(where: \.isResourceCondition)`, never stored, so it cannot fall
out of date with the conditions. `narratesResourceAttribution` is the question every
surface asks.

Six call sites now consult it. Five were narrating a CPU story over a lifecycle
episode; only the first was known:

1. `IncidentDetailView.unattributed` — was the private copy of the rule (TASK-71).
2. `IncidentSummarizer.summarize` — the banner **and** the detail's "what we found",
   which is why the detail contradicted itself on one screen.
3. `IncidentVerdict.paragraph` (`IncidentEvidence.swift`) — "Xcode was the largest
   single user of CPU" in the plain verdict.
4. `EvidenceLegend.entries`, via the caller — advertised "contributor share,
   unattributed remainder" for a screen showing neither.
5. `InvestigationBuilder`, via the caller — offered "Treat Xcode's load as expected",
   a policy about the wrong application. The relaunch findings are handed over in
   its place, so the "who contributed" stage says what was observed.
6. `IncidentHistory.Entry.subject` — see below.

Three of those (3, 4, 5) are inputs to builders that also serve resource incidents,
so the rule is applied at the call rather than inside the builder.

`ResourceSummaryIsUnchangedTests.accountTracksTheNarrative` asserts the rule as a
rule: across every single-condition set, the empty set and the mixed set, whether a
CPU account appears equals `narrative.narratesResourceAttribution`. A seventh surface
that re-derives it fails that test.

## The subject — a second, worse divergence, found mid-task

On one incident the list said "Repeated unexpected quits — Xcode" while the detail
said "yes quit unexpectedly 30 times". `IncidentsView` read
`incident.attribution?.leadingApplication` — the largest **CPU** contributor — for
every row; `RepeatedQuitReport` read the pattern's command. Both real measurements,
different processes.

`Incident.lifecycleSubject` is now the single answer: the finding with the most
exits, ties broken by earliest episode then command, because `lifecycleFindings` is
sorted on exit count alone and leaves ties to dictionary order.
`IncidentHistory.Entry.subject` composes it with the narrative — lifecycle episodes
are about the process that exited, resource episodes about what was busy — and
`IncidentsView` only adopts it. `leadingContributor(for:)` is deleted.
`IncidentRowSubjectTests.listAndDetailAgree` asks both surfaces about one incident
and compares their answers.

**Open, and it needs someone who owns `NowPresentation.swift`.** The agent that did
criterion #4 added `NowPresentation.leadingRelaunchPattern(_:)` — a *second* subject
rule, breaking ties by "most recent" where `Incident.lifecycleSubject` breaks them by
earliest episode then command. Two findings with equal exit counts would make the
banner and the list name different processes. This is criterion #2's failure mode
reappearing in a file outside both briefs. The fix is one line: delete
`leadingRelaunchPattern` and call `incident.lifecycleSubject`.

## Keeping notObserved from becoming an assertion (#3)

The reflex fix — suppress the CPU narrative — would have left the summariser's
ruled-out list intact: "Not a memory problem", "Not a storage problem", "Not thermal
throttling". Said about a slowdown those are fair. Said about an application that
kept exiting they volunteer a clean bill of health for a cause nobody proposed, on
evidence that cannot support one — and they are exactly the assertion TASK-71 forbade
itself.

They are replaced for a lifecycle narrative by one statement,
`IncidentNarrative.noResourceConditionRecorded`: no sustained condition was
**recorded**, that is what we did not observe rather than a finding that the machine
was fine, and nothing here rules a resource cause out. Deliberately narrower than
`ResourceVerdict.notObserved` rather than a copy of it — this speaks only about the
conditions the detector recorded; the verdict speaks about retained samples across
the window and can say more when samples exist.

No hypothesis is emitted at all for a lifecycle episode. The detail screen's ("it
probably met the same problem each time") is built there from
`RelaunchPattern.causeConfidence`; a second copy is how the two surfaces diverged in
the first place.

## "yes quit unexpectedly 30 times"

`ProcessNaming.sentenceSubject(command:applicationName:capitalized:)`. A real
application name is used bare — "Xcode quit unexpectedly" needs no scaffolding. A
bare command becomes `the process “yes”`, so it can never be read as the English
word. A rule about command-named subjects, not a special case: `sh`, `find`, `open`,
`who`, `top`, `make` and `sleep` all fail the same way and are all tested.

## The truncated command (#6)

The observed row read "Repeated unexpected quits — BackgroundShortc…". The ellipsis
was there; nothing said the **kernel** had cut it, and it sat in the position an
application's name occupies. `Subject.text` goes through `ProcessNaming.labelled`,
`Subject.sentenceText` wraps it as `the process “BackgroundShortc…”` — which is the
substantive FR-002 fix, because it says the thing is a command — and the row's
accessibility label appends `ProcessNaming.truncationNote`, the treatment
`AllProcessesView` and `ProcessInventoryView` already give it (TASK-81).

`isShortenedCommand` under-reports on purpose: a resolved application name is taken
at face value even though grouping may itself have fallen back to a labelled
command, because by the time it reaches a row the evidence for that is gone and
guessing from the shape of a string is worse.

## Criterion #5 — the threshold, measured

**Unchanged, and the count is the wrong dial.** Full evidence and the decision to
make are in **TASK-84**. In short: one 901 s window on this machine at a 2 s cadence,
grouping by 16-byte basename as `p_comm` is — **28 commands reached three exits**
(`swift-frontend` 112, `yes` 60, `zsh` 42, `xcodebuild` 19, 24 more). Raising the
count cannot work when normal churn reaches 112 and a real user gives up at three.
Requiring a matched relaunch leaves 23 of 28 — a build spawns the same compiler over
and over. Requiring a 60 s median session life leaves 3. Requiring FR-046's own noun
— **application** — leaves 0, and loses nothing real: exactly one of the 28 lived in
a `.app`, and it was MacSlowdown being rebuilt.

The FR-006 argument: TASK-71 read `minimumExits` as the sustained-not-transient
guard. FR-006 forbids alerting on *one event too short to matter*; what this
predicate admits is *many events that were each entirely normal*. Multiplicity is not
duration. That reasoning is now in `LifecycleTracker.minimumExits`' own
documentation, with the figures, so nobody re-derives it.

Severity worth stating plainly: `breaches(.repeatedApplicationQuits)` is true while
any finding is inside the quiet period, and churn keeps refreshing it — so on a
building Mac this condition breaches **continuously**, one incident that opens within
a minute and never closes. That is exactly the two episodes observed.

Also raised in TASK-84 and not changed here: **"unexpected" is a claim we cannot
support.** An exit is a process vanishing between two snapshots; there is no exit
status, no signal, and no readable crash report. A clean exit and a crash are
identical to us.

## Not verified — #1 and #6 are on-screen criteria and stay unchecked

**Nothing was put on screen.** The machine was in use by the orchestrator. Both
criteria are proven by test across every surface that composes the text, and a
passing test is not a UI criterion.

To check #1: drive a `.app` MacSlowdown can measure through three exit-and-relaunch
cycles, each phase longer than the sampling cadence — `for i in 1 2 3 4; do open -a
TextEdit; sleep 8; osascript -e 'quit app "TextEdit"'; sleep 8; done` — **with a build
running**, so Xcode is genuinely the busiest process and the defect has something to
reappear as. On the Now banner the body must contain no percentage of busy CPU, no
"largest measurable contributor", and no confidence label above low; it must name the
process that exited and carry `RelaunchPattern.limitation`. Open the incident: the
inspector's headline, the plain verdict paragraph, the evidence legend and "what we
found" must all agree, and the list row must name the same process as the inspector
— that last one is the specific regression to watch.

To check #6 the subject must be a command of 16 bytes or more, which TextEdit is not.
Stage it with a copy of a small binary renamed to ≥16 characters, run three times.
The row should read `the process “……”` with the ellipsis inside the quotes — not a
bare fragment in the position an application name occupies — and VoiceOver should say
"name shortened by the system".

One thing no test can settle: whether a real episode's `ResourceVerdict` lands on
`.normal` or `.notObserved` in the running app. Same open question TASK-71 left.
<!-- SECTION:NOTES:END -->
