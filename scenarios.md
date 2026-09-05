# Scenarios

**Status:** draft for product-owner review, 2026-09-05. Not authoritative until folded into `requirements.md`.

Five journeys, written from the user's side: what they are trying to do, what the app does about it, what they see, and how they get to something they can act on. Where a control already exists, it is named. Where one does not, it is marked **not built**.

Four of the five happened on the owner's machine. The fifth — a healthy Mac, opened anyway — is the most common case by a wide margin and nothing has been designed for it.

---

## The interruption contract

The rules the scenarios below assume. Most of this is built; the gaps are named as they arise.

**We interrupt only when all of these hold.** A condition has been breaching for its sustained duration (CPU 180 s by default); the incident's severity is at or above the user's threshold (high, by default); no per-app rule covers the leading contributor; the machine is not in Focus, playing audio, or muted; and we have not already announced this incident.

**One notification per incident**, unless it materially worsens. An episode that runs for an hour interrupts once.

**Confidence gates the interruption; it never appears in it.** A banner that says "we are 60% sure" is worse than silence — it transfers our uncertainty to someone who cannot resolve it. So a low-confidence finding is *recorded and visible in the app*, and does not interrupt. What appears on the banner is only what we measured.

**Never a bare number as an alert.** No load averages, no "CPU 94%" without what it is 94% of.

---

## S-1 — Something is wrong and I don't know what

**What the user is trying to do.** Keep working. The Mac has been sluggish for a few minutes and they are about to start closing things at random to see what helps.

**What actually happened.** 2026-08-31: an hour at ~99% of eight cores. The app showed "Your Mac is heavily loaded" directly above "No slowdowns since 11:22 AM" — the sustained clock was being cleared by any single sub-threshold sample (TASK-100, fixed 12:37 that day). Post-fix the same machine opened a 9-minute CPU saturation incident at 100% peak, the first the product ever produced.

**Timeline.**

| When | What the app does |
|---|---|
| 0:00 | CPU crosses 85% of machine capacity. Nothing is shown. A threshold crossing is not an event. |
| 0:00–3:00 | Menu bar glyph moves to **elevated** (2 bars). The clock survives dips up to 15 s. |
| 3:00 | Incident opens. Glyph gains the **ring badge**. One notification. |
| 3:00+ | Sampling accelerates to ~1 s (FR-031). Evidence is retained before, during and after. |
| +60 s below threshold | Incident closes. Badge clears. It stays in history for 30 days. |

**The notification.**

> **CPU saturation for 3 minutes**
> Severity high. Xcode is the largest measurable contributor.
>
> `Show details` · `Xcode is usually busy` · `Not now`

The middle action is **not built** — today only *Show details* and *Mute 1 hour* are offered. It matters more than anything else on this page, and S-4 is why.

**Getting to something actionable.** *Show details* opens the incident:

1. **What happened** — the condition, how long, the peak, over what window.
2. **Who** — contributors as application families, CPU as a 60-second mean, with **"Unattributed system activity — 40% of all busy time, not measurable"** as a first-class row, never a remainder.
3. **What you can do** — this is the honest part. The app has no process control at all, so the actions are: **Bring Xcode to the front** (so the user can quit it themselves), **Show in Finder**, **Open Activity Monitor**, **Copy diagnostics**. It hands off; it never claims the hand-off worked.

**The actionable step is the user's, and the app should confirm it.** The user quits Xcode. Lifecycle tracking sees the process go, and the app re-measures over a bounded window and reports what it observed — "Total CPU fell from 94% to 31% over the 60 seconds after you quit Xcode. The two line up, but we cannot prove one caused the other."

That closing loop is **not built**. `ActionVerifier` exists, is tested, and is deliberately unwired because every action *the app* offers is observational. But the *user's* action is not, and it is observable. Without this, the product explains and never confirms — and question 5 of §1 ("did that action improve the condition?") is never answered.

---

## S-2 — It's slow and nothing on screen explains it

**What the user is trying to do.** Understand why the machine is slow when they aren't running anything heavy. This is where most tools quietly lie by showing the top row of a list that accounts for a third of the activity.

**Why it happens.** The busy time belongs to processes running as another user — `backupd`, `mds_stores`, `WindowServer`. Measurability is decided by uid exactly: ~40 percentage points of busy CPU are unattributable, and unsandboxing does not fix it. Design `1h` is the screen.

**The notification.**

> **CPU saturation for 4 minutes**
> Severity high. Most of the activity is system processes we cannot identify.

**Getting to something actionable.** Here the honest answer is that there is very little the user can do, and saying so plainly is the product's differentiator:

- The unattributed share, named, with **why**: "macOS does not report other users' processes to App Store apps."
- What we *can* see — likely-benign correlates: a backup running, Spotlight indexing, the disk busy.
- **Open Activity Monitor**, which runs with privileges we do not have and can name what we cannot.

**The actionable step is "wait, or look in Activity Monitor" — and that is a legitimate answer.** The failure mode to avoid is naming the largest visible contributor as though it were the cause. Users act on that, and they act wrongly.

---

## S-3 — My Mac is thrashing and I have a model loaded

**What the user is trying to do.** Run a local language model on a 24 GB machine and keep working. Two memory-pressure incidents were recorded after the detector fix, at 28 and 13 minutes.

**Timeline.** Memory pressure differs from CPU in one way that matters: the kernel pushes transitions to us through a dispatch source, so pressure reaches the interface within ~2 s even when the sampling loop is behind (FR-007). Sustained duration is 90 s.

**The notification.**

> **Memory pressure for 2 minutes**
> Severity high. LM Studio holds the most resident memory.

**Getting to something actionable.** This is the one scenario where the user has a genuinely effective move, and the app should make it obvious:

- Pressure level and **how long it has held** — built.
- Swap and paging as rates from counter deltas, never a cumulative total.
- Resident memory by family, labelled **resident size** — not the footprint Activity Monitor shows, so our numbers will legitimately differ and we say so.
- **FR-056** (drafted, awaiting review) is exactly the right action here: name the memory-holding applications the user is *not currently working in*. "You have not used Photos in 3 hours; it holds 1.1 GB." That is a decision the user can make in a second, and it is the only place this product can offer a genuinely useful action rather than an explanation.

**Must never say** memory was "freed", that cached memory is wasted, or that growth is a leak. It is a suspected anomaly with ordinary explanations.

---

## S-4 — The alert that fires every time I compile

**This is the scenario that decides whether the product survives on this machine.**

**What the user is trying to do.** Build their project, capped at six jobs and `nice`d. CPU busy median 63%, peaking at 100% for four minutes. **The machine is not slow. It is working.** But it is indistinguishable from S-1 by threshold alone.

**What happens today.** The build runs long enough and hot enough to open a CPU saturation incident, and the user gets a banner for something they started deliberately. FR-046 produced ten false positives in nine days and the owner's response was to question the whole feature. That is the pattern to avoid: **people don't tune noisy software, they turn it off.**

**The fix is targeted, not global.** Three layers, in the order they should be reached for:

**1. Per-app rules — the primary control.** `PolicyClassification.expected` already exists and `NotificationPolicy` already suppresses on it: heavy load from that app is recorded but never interrupts. The gap is that it is only reachable from Settings, and nobody goes to Settings to fix a notification. **Offer it in the notification itself** — `Xcode is usually busy` — one tap, at the moment of annoyance. This kills one false-positive class permanently without dulling anything else, which is what a global control cannot do.

**2. The verdict tap — how the product learns.** Every incident carries two buttons: **This was a real slowdown** / **This was fine**. Stored locally as user-provided evidence (FR-038, FR-039). Two purposes, one gesture: it gives the product a true-positive rate it has never had, and it lets the app notice it is being noisy.

**3. The sensitivity setting — the backstop.** `AlertSensitivity` already exists with three options. It should be reachable from the notification and restated in plain words:

| Setting | Alerts when | Sustained for |
|---|---|---|
| Only when it's bad | Severe only | 5 min |
| **Balanced** (default) | High or worse | 3 min |
| Tell me early | Moderate or worse | 1 min |

**Three named options, not a continuous slider.** A slider's intermediate positions mean nothing the user can predict, and they cannot tell what they will get until they have lived with it. Three options each restate what they do, in a sentence generated from the thresholds themselves so the words cannot drift from the behaviour — `AlertSensitivity.restatement` already does this.

**The app should ask before the user gives up.** After three "This was fine" verdicts in a week:

> **Alerting less often?**
> You've marked 3 of the last 5 alerts as fine. Alert only when it's bad?
>
> `Yes, alert less` · `Keep as is`

This is the whole point of layer 2. Reaching for the system notification switch is the failure we are designing against, and the app noticing first is the only thing that prevents it. **All three of these are not built** — the rules and the dial exist, their placement does not, and the verdict does not exist at all.

**Pass for this scenario:** a capped build produces no notification, and after one *Xcode is usually busy* tap it never produces one again.

---

## S-5 — Nothing is wrong and I opened it anyway

**What the user is trying to do.** Satisfy a suspicion. They think the fan is loud, or the machine felt off an hour ago, or they are simply curious. **This is the most common scenario by a wide margin and nothing has been designed for it.** `1a` shows a healthy popover; no screen describes what the app is *for* on a good day.

**What they should get.**

- **A settled state, with how long it has held** — "Working normally · 22 min at this state" — built this week. A state word alone says nothing about whether it is steady or changed four seconds ago.
- **What was observed and for how long**, so "nothing found" is distinguishable from "not watching yet".
- **The recent past.** The single most valuable thing here: "Nothing since 11:22 this morning, when Xcode ran hot for 9 minutes." That answers *"was I imagining it an hour ago?"* — which is the actual question, and the one thing a live gauge like iStat Menus cannot answer.

**Must not say** that the Mac is fine in absolute terms — only that nothing was observed. Must not invent activity to look useful, or draw a flat line where no series is retained.

**This is where the product's memory earns its keep**, and it is the weakest screen today. A user who opens the app on a good day and learns nothing stops opening it, and then the incident history has no audience when it finally matters.

---

## What these scenarios expose

- **The most important missing control is one tap in a notification.** Per-app "expected" rules exist and work; they are reachable only from a screen nobody visits while annoyed. Fixing placement is cheap and addresses S-4 directly.
- **Nothing records whether an alert was right.** Every "false positive" in this project is one person's after-the-fact judgement, written in a task note. Without the verdict tap there is no true-positive rate, no false-positive budget, and no way to close S-1 versus S-4 with evidence rather than argument.
- **S-1 and S-4 are the same measurement.** Both are "very busy for minutes". Only the user knows which was which, so the product must ask rather than tune thresholds blind.
- **The loop never closes.** The user's own action is observable and is never verified, so §1's fifth question is unanswered in every scenario above.
- **S-5 has no requirement and no screen**, and it is the scenario that decides whether the app is still installed when S-1 happens.
