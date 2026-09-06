# Scenarios

**Status:** draft for product-owner review. Describes what we are trying to accomplish, not how.

Seven situations a person is actually in. Each states the issue as they experience it, what they do, what that lets them do next, and what they walk away with. Each also states how it fails — because a monitoring tool is judged as much by an ordinary day as by a bad one, and the ways it loses people are all quiet ones.

No screens, no settings, no thresholds. If a sentence here could only have been written by someone who had seen the code, it does not belong.

---

## S-1 — It's slow right now and I want it to stop

**The issue.** Something is wrong this minute. Typing lags, the fan is up, and the person is about to start quitting things at random to see what helps. They are not curious about their computer; they are trying to get back to work.

**What they do.** They look, and they expect an answer in a couple of seconds — a name, not a table. If they have to read a chart to find out what is wrong, they have already lost more time than the slowdown was costing them.

**What it enables.** They learn which application is responsible and how sure we are. Then they act on it themselves: switch to it, save their work, quit it, or decide it is worth the wait.

**The outcome.** The machine recovers and they know *why* it recovered — so the next time it happens they recognise it in seconds instead of minutes. The lasting value is not the fix; it is that they learned something about their own machine.

**How it fails.**
- We name the wrong application, they quit it, and nothing improves. Worse than saying nothing: they lost work and trust at once.
- We give them a list of five things instead of a leading answer, and they are back to guessing with extra steps.
- We tell them what is wrong but nothing they can do about it. Informed and powerless is its own frustration.
- We confirm what they already knew. If they were watching a video export run, we have added nothing.

---

## S-2 — It was slow earlier and I don't know if I imagined it

**The issue.** An hour ago the machine felt wrong. It is fine now. They half-suspect they imagined it, and there is nothing left on screen to check. This is the moment every live gauge fails at, and it is the reason to build this rather than a nicer Activity Monitor.

**What they do.** They open it after the fact and ask what happened while they were not looking.

**What it enables.** They see that something did happen — when it started, how long it lasted, what was involved — or that nothing measurable occurred in that window. Both answers are useful. "We watched, and nothing crossed the line" is a real result, not a shrug.

**The outcome.** Either they stop worrying, or they have a specific thing to watch for. If it turns out to happen every day at the same time, they have found something they could never have caught by looking at a live reading.

**How it fails.**
- The episode was real but too brief or too mild to have been kept, so we say nothing happened. We have now told them they imagined it, which is worse than silence.
- We show a record so laden with caveats they cannot tell whether it was serious.
- The history is full of episodes they never cared about, so the one that mattered is buried among them.

---

## S-3 — It's slow and the honest answer is that I can't help

**The issue.** The machine is genuinely struggling, and the cause is the operating system doing something the user has no control over and we cannot even name — indexing, backing up, syncing. A large share of what makes any busy Mac slow is simply not visible to an app distributed the way this one is, and no amount of cleverness changes that.

**What they do.** They ask what is going on, expecting a culprit.

**What it enables.** They learn that the load is real, that it is not one of their applications, and that it will likely end on its own. They also learn, plainly, that some of what is happening cannot be attributed at all — and why.

**The outcome.** They stop hunting. They stop quitting applications that were never the problem. They wait, or go and get a coffee, and that is a good outcome even though we fixed nothing.

**How it fails.**
- We name the largest thing we *can* see as though it were the cause. This is the most dangerous failure in the product: confidently wrong, entirely plausible, and people act on it.
- We hedge so heavily the answer reads as "we don't know", when in fact we knew something useful — that it was not their fault.
- We present the unexplained portion as a rounding error rather than as the largest single thing on the screen.

---

## S-4 — I'm doing something heavy on purpose

**The issue.** They are compiling, exporting video, or running a model. The machine is flat out and that is entirely intended. Nothing is wrong. From the outside this is indistinguishable from S-1 — same load, same duration, same everything — and the only difference is in the person's head.

**This is not a tuning problem.** It is tempting to read it as one: raise a threshold, lengthen a duration, attribute more carefully. None of that helps, because the two situations are not separated by anything we can measure. If we tell this person their machine has a problem, we have not been too sensitive — we have misunderstood what they were doing, and told them so.

**What they do.** Ideally nothing. They should not have to think about us at all.

**What it enables.** If we do speak up, one gesture should end that conversation permanently for this kind of work — not quieten us generally, but teach us that *this* is normal.

**The outcome.** They keep the app installed. That is the whole outcome, and it is not a small one.

**How it fails.**
- We interrupt them for work they deliberately started. Every such interruption is a withdrawal from an account that is never topped up.
- We call their intended work a problem, and then ask *them* to correct our misunderstanding. The apology is the insult.
- The only remedy we offer is a blunt one — be less sensitive overall — so avoiding the annoyance costs them the alerts they actually wanted.
- The remedy exists but sits somewhere they would have to go looking for it while irritated. Nobody goes looking while irritated. They turn the thing off.

---

## S-5 — You told me something I didn't need to hear

**The issue.** We interrupted, and we were wrong — or right but pointless. Maybe it was expected work, maybe it passed before they looked, maybe it was never their problem. This will happen. The question is not whether we produce false alarms but what happens on the third one.

**What they do.** They dismiss it, and they form a judgement about whether we are worth listening to. Most people will not go and configure anything. They will start ignoring us, and then silence us.

**What it enables.** The cheapest possible way to tell us we got it wrong — one gesture, right where the annoyance is. And symmetrically a way to tell us we got it right, so the two are comparable.

**The outcome.** We interrupt less, and specifically less about the thing they did not care about. Over a couple of weeks the alerts they get are ones they wanted. And we come to know how often we are right, which today nobody knows — including us.

**How it fails.**
- We never ask, so we never learn, and the only signal we get is the user leaving.
- We ask too often, and the asking becomes the noise.
- We treat every correction as "be quieter overall", so someone who did not want to hear about compiles stops hearing about running out of memory too.
- We wait for them to find a setting. By the time a person opens a preferences window to fix notifications, they have usually already decided against us.

---

## S-6 — Nothing is wrong and I looked anyway

**The issue.** Nothing is happening. They opened it out of habit, or curiosity, or a vague sense the machine has been off lately. **This is what almost every visit looks like**, and it decides whether the app is still installed on the day it finally matters.

**What they do.** They glance for a few seconds and expect to be told, credibly, that things are fine.

**What it enables.** Reassurance actually worth something — not a green light that would look identical if we had stopped working an hour ago. They should be able to tell "we have been watching and nothing crossed the line" from "we have not been watching". And they should learn one thing they did not know: the machine has been steady all morning, or it was busy over lunch and has settled since.

**The outcome.** A small, repeated deposit of trust. They believe us on a good day, which is the only reason they will believe us on a bad one.

**How it fails.**
- A flat "everything is fine" with nothing behind it. Indistinguishable from a broken app showing a default state, and worth nothing on the day it says something else.
- Nothing to look at, so no reason to open it again, so it is not open when it matters.
- We manufacture interest — dramatic charts of an idle machine — and the reassurance becomes untrustworthy in the other direction.

---

## S-7 — It's slow and you're telling me everything is fine

**The issue.** The machine is unmistakably struggling — the beachball, an application that will not respond, everything taking a beat too long — and nothing we watch has crossed a line. Perhaps we cannot see the cause. Perhaps the thing that is slow is not a resource at all. This is the scenario where the user is right and we are wrong, and it is the one we currently have no way to even find out about.

**What they do.** They tell us. Not by configuring anything — by saying, in one gesture, *it's slow now*.

**What it enables.** For them: a marker in the record, so when it happens again there is something to compare against, and so the question stops being "did I imagine it" and becomes "what was different those three times". For us: the only evidence that exists about the slowdowns we miss entirely.

**The outcome.** They feel heard rather than contradicted, which is the difference between a tool that watches the machine and one that argues with its owner. And over weeks, the gap between what people experience and what we detect becomes something we can actually see.

**How it fails.**
- We ask them to describe or categorise it. They are trying to get back to work; the moment it costs them a form, they stop telling us.
- We record it and never refer to it again, so the gesture was extractive — we took data and gave nothing back.
- We respond by insisting nothing was wrong. Everything we measured may well have looked normal; that is a fact about our instruments, not about their afternoon.
- The control is not there when they need it, because it lives somewhere they have to go and find while frustrated.

---

## What runs underneath all seven

**Being wrong costs more than being silent.** A missed slowdown is a disappointment; a confident wrong answer sends someone to quit the wrong application. Where we are unsure, the useful move is to narrow the question rather than guess at the answer.

**Part of the truth is that we cannot see.** A significant share of what makes a Mac slow is invisible to us. Saying so clearly is not an apology — it is what separates us from tools that quietly present a partial list as a complete one.

**Interrupting is the only thing we can truly get wrong.** Everything else waits until someone chooses to look. An alert takes attention without asking, so it needs a higher standard than anything on a screen the user opened deliberately.

**A busy machine and a slow machine are not the same thing, and we cannot tell them apart.** This is the deepest problem in the product. Every measurement we take is of a resource; every claim a user cares about is about their experience. The two coincide often enough to be tempting and diverge often enough to be dangerous. We should say what we measured and let that stand, rather than translating it into a claim about how their day went.

**We do not know how often we are right, and asking about our own alerts would not tell us.** Judging the alerts we sent can only measure the ones we sent. It says nothing about the afternoons someone lost while we recorded nothing unusual — and those are the failures that lose a user for good. Only the person can tell us about those, and only if telling us is free.

**The most common experience is that nothing is wrong.** A product designed only for the bad day gets uninstalled before the bad day arrives.
