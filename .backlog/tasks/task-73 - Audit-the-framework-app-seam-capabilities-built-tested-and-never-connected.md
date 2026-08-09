---
id: TASK-73
title: 'Audit the framework-app seam: capabilities built, tested, and never connected'
status: To Do
assignee: []
created_date: '2026-08-09 18:23'
labels:
  - core
  - risk
milestone: m-3
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Raised as a pattern, not an incident.** Five times in one session, work was found that was fully implemented in the `Metrics` framework, covered by passing tests, and simply never wired into the running app. Twice a requirement had green tests and **could not fire in the product at all**.

The confirmed instances:

| Found | Capability | Consequence |
|---|---|---|
| TASK-66 | `lowStorage` never passed into `SystemObservation` | FR-041/FR-042 could never raise an incident |
| TASK-66 | `MetricsHistory` private, no accessor | every sparkline in the design unbuildable |
| TASK-66 | no `PolicyStore` owner | FR-016 framework-only |
| TASK-66 | `LifecycleTracker` undriven | "relaunches today" had no source |
| TASK-69 | `AlertSettings` unread by the detector | every alert control changed a value and no behaviour |
| TASK-71 | no `IncidentCondition` for repeated quits | design 1o can never be shown |
| (open) | `RetentionPolicy.expired` never called | retention defined, never enforced |

The through-line: **a passing test proves a unit works, not that anything calls it.** Our test suite is strong at the framework level and that strength hid the gap — the code was right, the wiring was absent, and nothing failed.

This is not a request to rewrite anything. It is a request to **look deliberately for the next one** rather than trip over it, and to leave behind something that makes the class of defect visible.

Worth checking specifically: every public type in `Metrics/Sources/` that no file under `MacSlowdown/Sources/` references; every `RedactionOptions`-style options struct whose fields are read nowhere (TASK-70 found `hideFilePaths` was inert — the control existed and did nothing); every setting in `PrivacySettings`; and every FR whose acceptance criteria are satisfied only by framework tests.

Note the honest counter-argument, which should be weighed rather than dismissed: some of these are deliberate staging, where the framework was built first on purpose. The audit's job is to tell staged work apart from forgotten work, and to record which is which — not to treat every unreferenced type as a bug.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every public type and public entry point in Metrics/Sources is classified as: used by the app, deliberately staged for later work, or forgotten -- with the list recorded
- [ ] #2 Each 'forgotten' item gets a task or is removed; dead code is not left in place on the grounds that it is tested
- [ ] #3 Every requirement whose acceptance criteria are met only by framework tests is identified, and it is stated for each whether the behaviour can actually occur in the running app
- [ ] #4 A check exists that would catch the next instance -- whatever form is practical, from a documented review step to a test that asserts a capability is reachable end to end
- [ ] #5 The audit distinguishes deliberate staging from oversight rather than treating every unreferenced type as a defect
<!-- AC:END -->
