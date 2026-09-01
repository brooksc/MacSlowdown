---
id: TASK-108
title: Make notification volume discoverable — the dial exists and nobody finds it
status: To Do
assignee: []
created_date: '2026-09-01 01:23'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
type: enhancement
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised by the product owner on 2026-08-31, looking at four consecutive banners in Notification Centre: "I just want to be sure they are always useful and don't result in the user turning off notifications."

**The dial they asked for already exists.** `AlertSensitivity` has three settings, and `relaxed` is exactly the "fewer notifications" option requested — CPU threshold 0.92, sustained 300 s, and `minimumSeverity: .severe`, so only severe incidents interrupt. `balanced` is the shipped default at `.high`, which is why every banner in the screenshot announced. Recording is unaffected by all three; sensitivity changes interruption only.

So this is **not a missing feature**. The product owner has been running the app for two weeks, hit the exact problem the setting solves, and asked for it to be built — which is as clear a discoverability failure as we are going to get. Building a second control would make it worse.

**What to actually do — decide before implementing:**

1. **Discoverability.** The setting is in Settings → Notifications, found only by someone who opens Settings and reads. Candidates: offer it from the notification itself (the banner already carries a Mute action, so an "Alert me less" action is a small addition); surface it after the app has announced N times in a period; name it in first-run. Any of these is a design question, not a code question — worth asking Claude Design, since 1g is the banner screen and it has just revised the surrounding work.

2. **Whether `balanced` is the right default.** Four announcements in one day on an ordinary working machine is the evidence we have. Changing the default is a bigger call than adding a signpost and should be made on more than one day's observation — but it is the cheaper fix if the observation holds.

3. **Per-condition control** — "don't tell me about memory", "don't tell me about repeated quits" — is **not** requested and should not be built on spec. The screenshot's "Memory pressure and Repeated quits" alert is already being removed by TASK-102, which deletes the repeated-quit incident entirely. Re-check the noise level after that lands; part of the problem may go with it.

**Already done, separately:** the negative clause is gone from the banner body (commit baa99c9). That was the "extra words that don't give me value" half of the report and needed no setting.

**Not to be done:** a second sensitivity control, or a per-notification opt-out, before 1 and 2 are answered. FR-060's failure mode is two surfaces that can disagree, and two volume controls is that defect in settings form.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A user who is being notified more than they want can find the setting that reduces it without opening Settings and reading
- [ ] #2 No second sensitivity control is added; the existing AlertSensitivity stays the single source of notification volume
- [ ] #3 Whether `balanced` remains the default is decided on recorded observation, and the decision is written down either way
- [ ] #4 The noise level is re-assessed after TASK-102 removes the repeated-quit incident, before any further change is made
<!-- AC:END -->
