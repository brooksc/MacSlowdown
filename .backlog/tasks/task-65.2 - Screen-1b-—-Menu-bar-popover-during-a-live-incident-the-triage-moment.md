---
id: TASK-65.2
title: Screen 1b — Menu bar popover during a live incident (the triage moment)
status: In Progress
assignee: []
created_date: '2026-08-09 02:21'
updated_date: '2026-08-09 05:10'
labels:
  - ui
milestone: m-2
dependencies: []
modified_files:
  - MacSlowdown/Sources/MenuBarContentView.swift
  - MacSlowdown/Sources/PopoverPresentation.swift
  - MacSlowdown/Tests/IncidentPopoverTests.swift
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1b.png`. No implementation exists — the popover renders the same way whether or not an incident is open.

**What the design specifies**

This is the screen the product exists for. The popover changes shape during an incident:

- Headline states the condition and how long it has lasted: "CPU has been maxed for 6 min".
- A sentence naming the likely cause with its magnitude and the consequence in the user's terms: "Most of it is **Xcode** — 412% CPU, about 4 of your 10 cores. Your Mac will feel sluggish until it finishes."
- A sparkline of total CPU over the last 15 minutes, with the incident start marked on the axis ("12:26 … started 12:35 … now").
- "Share of the busy time" — a contributor list explicitly labelled as adding up to 100%, so the arithmetic is checkable. Unattributed system activity is in it at 38%.
- A note reconciling the two percentage conventions in play: Xcode at 412% of one core versus its 44% share of busy time. The design does not hide the ambiguity, it explains it.
- Three actions: "See the evidence", "Show Xcode", "Mute".
- A standing line: "MacSlowdown doesn't quit or pause apps for you — you stay in control of anything with unsaved work."

**Why it matters**

FR-013 and FR-038 require causal language to carry confidence labelling and evidence. This screen is where that lands in front of the user. The two-convention note is the design solving a problem CLAUDE.md flags as easy to get wrong (FR-004).

Depends on incident state already exposed by MonitorStore (`openIncident`), so the data is there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 While an incident is open the popover leads with the condition and its duration, not the normal-state layout
- [x] #2 The cause sentence names the contributor, its magnitude, and the expected consequence, and carries a confidence label per FR-013
- [ ] #3 A short history sparkline shows the incident start relative to now
- [x] #4 The contributor list is labelled as a share of busy time that sums to 100%, and reconciles that with the per-core percentages shown elsewhere (FR-004)
- [x] #5 The three actions are present and none of them quits, pauses or otherwise controls another process (FR-037)
- [ ] #6 Verified on screen against design/screens/1b.png with a real incident, not a fixture
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was built

The popover now branches on `store.openIncident`. During an incident the verdict,
four-up strip and "using the most CPU now" list are replaced by the triage layout
of design 1b; the healthy layout is untouched. All copy and derivation went into
`PopoverPresentation.swift` alongside 65.1's, so the view stayed render-only.

**Headline.** `incidentHeadline(_:now:)` — "CPU has been maxed for 6 min". Duration
runs from `beganAt` (first breach), not `triggeredAt`, because a user asking how
long means the slowdown, not the moment our sustained-duration threshold elapsed.
Conditions are emitted in a fixed order (`IncidentCondition.allCases`), since a
`Set` would otherwise reword the headline between samples. Elapsed time is coarse
— "less than a minute" / "6 min" / "1 hr 15 min" — because second resolution would
imply a precision the cadence does not have. Severity word and symbol sit under it
(FR-034: never colour alone).

**The one causal sentence.** `cause(...)` returns a `Metrics.Conclusion`, not a
`String`. That is the FR-013/FR-038 mechanism the project already has: `Conclusion`
forces a confidence onto anything `.heuristic`, so the sentence is unrenderable
without "Likely · moderate confidence" above it, and `conclusion.display` carries
the same to VoiceOver. Content: name, magnitude in both conventions
(`CPUPresentation.percentOfOneCore` + `machineRelative`), and the consequence.

Three honesty constraints on it:
- "Most of it is X" only when the leader is >50% of busy CPU. Below that the
  sentence says "the largest contributor we can measure is X", which is what is
  actually true.
- Above 30% unattributable it appends the caveat that the leader may only be the
  largest thing we are permitted to see.
- The design's "Your Mac will feel sluggish until it finishes" became "While that
  continues, other apps are likely to feel slower". We cannot see whether the work
  is finite, so predicting an end would be a claim with no measurement behind it.
  There is a test asserting "until it finishes" never appears.

**Confidence provenance.** Not recomputed here. The view passes
`store.currentSummary?.hypotheses.first?.confidence`, so the popover and the
incident report cannot disagree about how sure we are. No hypothesis → no cause
sentence at all. One wrinkle recorded deliberately: `IncidentSummarizer` computes
confidence from the leading *process*, while the popover names the leading
*family* (so the sentence names what the list beneath it ranks). A family's share
is never smaller than its largest process's, and the summariser's confidence only
rises with share, so the figure shown is a floor — it can understate our
confidence, never overstate it. That is the safe direction, but it is a real
inconsistency and belongs to whoever unifies process- and family-level summaries.

**Share of the busy time.** `shareRows(...)` — whole-number shares that sum to
exactly 100, rounded by largest remainder. "Adds up to 100%" is a promise the user
can check, so rounding each share independently (the usual way a list lands on 99)
was not acceptable. Unattributed system activity is a peer row with the info
toggle, present even at 0% — an absent row would read as "everything is accounted
for", a different claim from "nothing was unattributable". Unlike the healthy
screen's residual, "Other applications" here has no 0.5% threshold: an omitted row
would break the stated sum. A family that rounds to 0% is folded into that
residual rather than dropped.

**Reconciling the conventions (FR-004).** `conventionReconciliation(...)`: "Xcode
is at 412% CPU — percentages there are of one core, and this Mac has 10. The
shares above are of the busy CPU during this slowdown, which is why they add up to
100%." No second convention was introduced; the shares are a different *quantity*,
and the note is what stops them reading as a rival unit.

**Three actions (FR-037).** "See the evidence" opens the main window; "Show ⟨app⟩"
calls `ActionPerformer.perform(.activate,…)` on the leading family's main
executable and reports what actually happened rather than assuming it worked
(FR-017); "Mute" offers 30 min / 1 hr / 4 hrs via `store.mute(forMinutes:)` with a
line stating monitoring continues (FR-015). The button is absent, not disabled,
when `SafetyPolicy` withholds `.activate` — matching the policy's own rule. No
code path in the file can affect how another process runs. The standing line
("MacSlowdown doesn't quit or pause apps for you…") sits under them.

Quit is kept as a small link, the same deliberate divergence 65.1 recorded: no
Dock icon by default, so removing it strands the user.

## Sparkline: not built, criterion #3 unchecked

`MonitorStore.history` is `private let MetricsHistory` with no accessor, so the
series FR-005 retains is unreachable from the view. `MetricsHistory.samples` is
public — only the store's handle is not — so this is one property away. TASK-66
was fixing it in parallel and had not landed in this branch.

Accumulating a series in the view was rejected: it would draw a *different* curve
from the one retained as evidence, so the popover and the incident report would
show two different histories of the same minutes. That is a quiet fabrication.
Omitted, not approximated. Once `MonitorStore` exposes the samples this is a
contained addition — the incident start is already in hand as `beganAt`.

## 65.1's structure: held, with one correction

The closing note said 1b "should only need to swap the verdict block" and that the
row and tile builders were reusable. Mostly right: the file split is exactly the
right shape, the `ContributorRow.Kind` enum, the icon builder and the
partial/process-count qualifiers were reused unchanged, and the whole screen went
in without touching the healthy path.

The overstatement is "only the verdict block". The share list is a genuinely
different derivation — percent-of-busy rather than percent-of-one-core, integer
shares that must sum to 100, no residual threshold — so `contributorRows` could
not be reused, only its shape. The tiles are not used at all: design 1b drops the
four-up strip. Net, roughly 290 new lines of presentation rather than a swap.

**One thing 65.1 got wrong administratively, not technically: its commit was never
merged to main.** `1f3982e`'s parent was exactly this branch's HEAD, so it was
fast-forwarded in cleanly, but this branch now carries both commits. Whoever
merges should expect 65.1's commit to arrive with 65.2's.

## Tests

`MacSlowdown/Tests/IncidentPopoverTests.swift` — 21 tests in four suites, all
passing. Headline copy and stable condition ordering; duration measured from
`beganAt`; elapsed-time boundaries; the cause is a well-formed heuristic with a
confidence and reads as "Likely, moderate confidence."; it names contributor,
magnitude and consequence; "most of it" requires a majority; the unattributable
caveat appears above 30%; no end-of-work prediction; shares sum to exactly 100 on
a realistic five-family split; largest-remainder rounding on thirds; unattributed
is a peer and survives at zero; the residual keeps the sum honest under truncation;
no busy time means no claims; process count and partial marker carry through; the
convention note contains both figures; the standing line promises no process
control; mute status states monitoring continues.

Full suite: **429 passing, 0 failing** (`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist
xcodebuild test -scheme AllTests -configuration Debug -destination
'platform=macOS' -derivedDataPath .build`). Baseline on this branch was 408, so
all 21 additions are accounted for. The first run of the pair failed
`EndToEndIncidentTests.realSlowdownProducesOneIncident` — the documented
load-synthesising flake, with several agents building concurrently — and passed on
re-run.

## Criteria

- #1, #2, #4, #5 met and covered by test.
- **#3 not met** — sparkline omitted; retained history unreachable (above).
- **#6 NOT verified — nothing was looked at.** This session was barred from the
  screen.

## What on-screen verification needs

This screen only exists during a real incident, and the default policy is 85% of
machine capacity sustained for 3 minutes. To stage one: run a load that saturates
the machine for over 3 minutes (e.g. `yes > /dev/null` once per logical core, or a
large clean build) with the app running, then open the popover before the 60 s
recovery hysteresis closes the incident. Lowering `IncidentPolicy` thresholds in a
debug build would make it reachable in seconds, but the layout should be judged
under a real load because the contributor set and the unattributable share are
what the arithmetic has to survive.

Specifically unverified: whether the popover grows too tall at 340 pt with the
headline, cause paragraph, five share rows with bars, the reconciliation note and
the action row; whether three buttons plus the Mute menu fit on one line; whether
the evidence/confidence caption reads as a label or as clutter; and fidelity
against `design/screens/1b.png` generally.
<!-- SECTION:NOTES:END -->
