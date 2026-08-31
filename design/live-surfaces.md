# The live surfaces: a proposed requirements addition

**Status:** draft for product-owner review, 2026-08-31. Nothing here is authoritative until it is folded into `requirements.md`.
**Answers:** challenge C-03 in `requirements.md` §10.1.

## Why this document exists

`requirements.md` centres the product on incidents: DR-01 calls incident diagnosis "the primary product", §1.2 defines success as opening an incident afterwards and understanding it, and forty-nine functional requirements describe detection, evidence, summarisation, export and safe response in detail.

In two weeks of using the built product, every piece of feedback concerned something else. What the popover says right now. Whether a number is an instant or a trend. Whether the status word holds still. Whether a table's ordering can be trusted. Whether a figure that changes every second means anything.

Not one concerned an incident report, and there was no legitimate incident to read — the ten recorded were all false.

That is not a criticism of the incident machinery, which is built and works. It is an observation that **the product a person touches every day is a live monitor, and this project has no requirements for it.** The live surfaces are governed only by FR-002's general instruction never to fabricate a measurement. Everything else about them — whether a figure is stable enough to read, whether two surfaces agree, whether an ordering means what it appears to mean — has been decided implementation by implementation, and corrected only when somebody noticed on screen.

The evidence that this is the gap rather than a theory: of the defects found in the last fortnight, the ones that reached the product owner were almost all live-surface defects. A status word cycling through three states while load was steady. A per-application figure changing at sampling cadence. A list sorted by a number that was not on screen. A relaunch count that counted something other than what its label said. None of these violated a requirement, because no requirement covered them.

## What "clear about what's needed" means here

The product owner's question was how to make it clear what is required. Three properties, and they are the reason the existing FRs work well where they apply:

1. **A requirement names a failure it forbids, not a feature it wants.** "Never fabricate a measurement" has caught dozens of defects. "Show CPU usage" would have caught none.
2. **Its acceptance criteria are checkable by someone who is not the author** — ideally by a test, and where that is impossible, by a written on-screen check a person can follow.
3. **It says who decides when it is ambiguous.** Every requirement below that involves a judgement names the judgement rather than hiding it in an implementation.

Each proposed requirement below is written in the same table form as the existing ones so it can be pasted into `requirements.md` unchanged.

## The proposal: six requirements

### FR-057 — A displayed figure shall state which statistic it is and over what interval

**Objective.** A number beside an application's name is read as "right now" unless it says otherwise. "29%" and "29% on average over the last minute" are different claims and only one of them is usually true.

**Expected behavior.** Every numeric figure on a live surface is either an instantaneous reading, labelled as such by context or wording, or a statistic over a stated window. Where the window is shorter than intended — because monitoring has not been running long enough — the figure states the span actually covered rather than the span requested.

**Acceptance criteria.** No figure appears without its statistic being determinable from the surface; a mean over eight seconds never describes itself as a minute; a figure with no readings behind it renders as unavailable rather than as zero.

**Already partly built:** `TrailingPresentation`, the Now table's "Now" and "Last minute" columns.

### FR-058 — A state shown to the user shall be judged over an interval, not a sample

**Objective.** A status word is a claim about the machine's condition. Read from one sample, it changes as often as the machine breathes, and an indicator that cannot make up its mind is not trusted — the product owner's words on 2026-08-31, watching the headline cycle through three states while load was steady.

**Expected behavior.** Any categorical state presented to the user — status word, severity, menu bar glyph, spoken label — is derived from a trailing window and does not oscillate at a band boundary. Escalation may be immediate; de-escalation requires clearing the band being left.

**Acceptance criteria.** A reading hovering at a boundary holds its state across consecutive samples; a machine that goes quiet always reaches the calm state, so the deadband cannot strand a word; escalation is not delayed by the same mechanism that damps de-escalation.

**Already built:** `Severity.settled`. This requirement exists so it cannot be undone by accident.

### FR-059 — Ordering shall be stable, and shall be by a value the user can see

**Objective.** A list that reorders every second cannot be read. A list ordered by a number that is not on screen cannot be understood, and invites the reader to conclude the ordering is broken — which is exactly what happened in TASK-63, where an hour went into a table that was sorting correctly.

**Expected behavior.** Lists of applications or processes are ordered by a value displayed in the list. The default ordering is derived from a window rather than the newest sample. Where ordering is additionally damped, the damping is explained on the surface.

**Acceptance criteria.** Every sort key is a visible column; a one-second spike does not promote a row to the top; the explanation shown for any ordering delay describes the mechanism actually in use.

### FR-060 — Two surfaces describing one fact shall not be able to disagree

**Objective.** This is the defect this project produces most. A fix lands on one surface and a second site keeps the old behaviour: the popover naming the live CPU leader while the banner named the recorded one; the inventory saying "not retained" beside a drawn curve; a footer denying attribution the rows above it displayed. Each was individually defensible and collectively incoherent.

**Expected behavior.** Where a fact is shown on more than one surface, it is derived in one place. Where two surfaces deliberately differ — a summary against a detailed view — the difference is recorded at the point of divergence with its reason.

**Acceptance criteria.** A fact rendered on two surfaces has one source; a deliberate divergence carries a written reason at both sites; a test asserts agreement wherever the two can be computed in one process.

**Note.** `probe/seam-reachability.sh` catches capabilities built and never wired. Nothing catches *fixed in one place*. A standing check for this is proposed as work rather than assumed.

### FR-061 — A live surface shall not become part of the slowdown

**Objective.** FR-030's objective survives its deferred budget, and the live surfaces are where it is most easily lost: they redraw often, and they are open precisely when the machine is struggling.

**Expected behavior.** Redraw is driven by data changing, not by a clock, except where a clock is the data — an age counter during a stall. Work proportional to the size of the process table is done once per sample, not once per redraw.

**Acceptance criteria.** No surface rebuilds a whole-table derivation on a timer; overhead is re-measured after any change to a surface's refresh behaviour.

**Found by review as a real defect:** the Now screen rebuilt the whole family tree once a second to redraw a caption that changes only when a reading is late.

### FR-062 — An action offered shall be one that can succeed

**Objective.** A control whose only possible outcome is an apology costs more trust than an absent one. "Show fileproviderd" was offered for a daemon that cannot be activated, at three sites, and fixed at one of them twice.

**Expected behavior.** An action is offered only where the conditions for its success are known to hold. Where it is withheld, the surface may explain why, but does not present the control. Where an action hands off to macOS and the result cannot be observed, it is reported as a request rather than as a result.

**Acceptance criteria.** No offered action fails for a reason determinable before offering it; a hand-off is never reported as a success; the rule lives in one place rather than at each call site.

## What this changes about how the work is judged

Today a live-surface defect is found when the product owner looks at the screen and something is wrong. That has worked, in the sense that it found a great many defects — but it puts the whole burden on one person's attention, and the defects that reach them are the ones that happen to be visible in the minute they are looking.

With these requirements the same defects become checkable before that: five of the six can be asserted by tests, and the sixth (FR-059's "visible column") is a question anyone can answer by reading a view. That does not remove the need for on-screen verification, which stays the critical path for anything about layout, legibility or feel. It removes the need for on-screen verification to be the *first* line of defence for honesty.

## Open questions for the review

1. **Do these belong in `requirements.md`, or as a separate design standard?** They are more prescriptive about implementation than most existing FRs, which A-07 and §11 deliberately keep open. My view is that they belong in the spec, because each one names a user-visible failure rather than a technique — but it is a fair objection.
2. **FR-060 is the expensive one.** "Derived in one place" is a real architectural constraint and would require changes where two surfaces currently compute the same thing independently. Worth agreeing whether it is a rule for new work only, or a debt to pay down.
3. **Is six too many?** They could compress to three: *say what a figure is*, *judge states over intervals*, *do not let surfaces disagree*. The longer form is easier to check; the shorter is easier to remember.
4. **What is deliberately not here.** Nothing about visual design, layout, spacing, or copy tone — that remains design's, per A-07. Nothing about which figures to show. These requirements govern honesty and stability, not composition.
