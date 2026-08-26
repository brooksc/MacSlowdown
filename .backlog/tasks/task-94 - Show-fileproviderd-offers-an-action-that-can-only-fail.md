---
id: TASK-94
title: '"Show fileproviderd" offers an action that can only fail'
status: In Progress
assignee: []
created_date: '2026-08-25 17:49'
updated_date: '2026-08-26 19:49'
labels:
  - ui
milestone: m-3
dependencies: []
priority: medium
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen on screen by the product owner, 2026-08-25, who read it correctly at a glance: "show fileproviderd I assume won't do anything."

`fileproviderd` is a daemon with no `.app` bundle. The `.activate` action goes through `NSRunningApplication`, which exists only for bundled applications, so the button cannot succeed. It does not lie — `ActionPerformer` returns a failure and the popover prints the reason under the row (FR-017) — but the user is offered a control whose only possible outcome is an apology.

`MenuBarContentView.showTarget` breaks the rule written directly above it ("withheld actions are absent rather than shown disabled") with a `?? leader.family.members.first` fallback: when a family has no bundle path the first `first` finds nothing, and the fallback hands back an arbitrary daemon process anyway.

Fix: no bundle, no button. The safety-policy check that follows is unchanged.

Note the same shape exists in `MainWindowView.bringForwardButton`'s `else` branch, which takes `store.attribution?.contributors.first` with no bundle check — worth confirming while here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A family with no application bundle offers no Show button
- [ ] #2 An application family still offers one, targeting the bundle's main executable
- [x] #3 MainWindowView.bringForwardButton is checked for the same fallback
- [ ] #4 Verified on screen: a daemon leading the contributors shows no Show button, and an application still does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC #3 closed under TASK-96 finding 10. `MainWindowView.bringForwardButton`'s `else` branch had the same fallback, and so did `FamilyInspectorView`'s safe-actions list — three sites, one rule, fixed at one of them. The check now lives in `SafetyPolicy.availability(of:for:resolved:)`: no application bundle, no activation, with its own reason ("This runs in the background and has no window") rather than a protection reason, because nothing is being protected. Callers that pass no resolved identity are unaffected, so nothing silently loses an action.
<!-- SECTION:NOTES:END -->
