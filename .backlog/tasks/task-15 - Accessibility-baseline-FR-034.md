---
id: TASK-15
title: Accessibility baseline (FR-034)
status: Out of Scope
assignee: []
created_date: '2026-08-02 01:06'
updated_date: '2026-09-16 02:24'
labels:
  - parked
  - ui
  - risk
milestone: 'null'
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Non-negotiable. Build in from the start rather than retrofitting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 VoiceOver labels, full keyboard operation
- [x] #2 Increased contrast and reduced transparency respected
- [x] #3 Severity never conveyed by color alone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Baseline built in throughout rather than retrofitted, but PARKED: AC#1 cannot be fully verified from here.

- AC#3 (severity never by colour alone) VERIFIED. The SF Symbol changes shape across severities (gauge 33/67/100), every severity is stated as a word, and the live menu bar item's accessibility description reads "status menu, MacSlowdown: Normal" -- confirmed against the running app.
- AC#2 (increased contrast, reduced transparency) VERIFIED BY CONSTRUCTION. There is not a single hardcoded colour in the app: everything uses semantic styles (.secondary, .quaternary, .quinary) and system materials (.bar), which follow the system's contrast and transparency settings automatically. Audited with grep; no Color.red/green/etc and no .foregroundColor calls.
- AC#1 (VoiceOver labels, full keyboard operation) PARTIALLY VERIFIED. Labels are annotated in code -- the figures grid reads each row as one sentence including its evidence class, the unattributed row carries a label plus the full explanation as a hint, inventory CPU cells name their application, and the stale banner reads as one statement. But I could not confirm them at runtime: SwiftUI on macOS 26 exposes the window through a remote accessibility tree that System Events cannot walk, so the traversal returned nothing. Keyboard operation likewise was not exercised end to end.

FR-034's own criterion is "accessibility audit passes", which needs VoiceOver and Xcode's Accessibility Inspector driven by a human. To finish: run Accessibility Inspector's audit against the Now, Apps & Processes and Settings windows, then tab through each surface with VoiceOver on and confirm every control is reachable and every figure reads with its evidence class.

Nothing else depends on this, so it does not block other m-1 work.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-16 02:24
---
**Deferred by the product owner, 2026-09-15: "park for now any accessibility related work... we will revisit it later. Let's first focus on getting the fully functional version working."**

Moved to Out of Scope as this Backlog's nearest equivalent of Won't-Do-For-Now. **This is a sequencing decision, not a scope cut**, and the distinction matters on this task specifically:

- **FR-034 is unchanged and still authoritative.** `requirements.md` calls accessibility non-negotiable and lists VoiceOver labels, full keyboard operation, increased contrast and reduced transparency as acceptance criteria. Nothing here amends the spec; only the order of work changed. Closing this task does not satisfy that requirement, and the requirement will still be unmet when the product is otherwise complete.
- **It is a release gate, so the cost is schedule risk carried later.** Accessibility defects are structural — they surface as missing labels and unreachable controls across every screen already built — so the later this is picked up, the more surfaces it touches at once. That is the trade being accepted, and it is a reasonable one while the product's core value is still unproven.
- **Severity must still never be conveyed by colour alone.** That one rule is already implemented (the severe filled badge, TASK-65 work) and should not regress while this is parked, because it is also a plain legibility property, not only an accessibility one.

**When this is revisited, Xcode 27 changes the approach.** `XCUIVoiceOverService` (new in Xcode 27) drives VoiceOver from UI tests and validates focus, spoken output and navigation — so the baseline no longer strictly requires a person wearing headphones, which is why this task was parked in the first place. Two prerequisites: this project has **no UI test target at all**, and the API is Xcode 27-only, so CI's macOS 26.6 / Xcode 26.6 runners cannot run it. It also makes the machine speak, so it belongs in CI or a VM rather than at the owner's desk.

Related work also moved out of scope: TASK-83.
---
<!-- COMMENTS:END -->
