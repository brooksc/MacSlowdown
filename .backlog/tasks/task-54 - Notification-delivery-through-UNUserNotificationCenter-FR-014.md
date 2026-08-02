---
id: TASK-54
title: Notification delivery through UNUserNotificationCenter (FR-014)
status: To Do
assignee: []
created_date: '2026-08-02 18:15'
labels:
  - core
  - phase1-catchup
milestone: m-3
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 1 of m-3. NotificationGate decides correctly and is tested, but nothing is ever delivered.

BLOCKED ON A PERMISSION PROMPT: requesting notification authorisation shows a system dialog on the user's machine and is a one-shot decision. Must stop and ask before triggering it.

Everything up to the prompt can be built and tested: the delivery adapter, the request content, and the wiring from detector to gate to centre. Authorisation state must be read back rather than assumed, in the same way FR-033's login item does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Delivery is wired from detector through the existing policy gate
- [ ] #2 Authorisation state is read from the system, never cached from what we last requested
- [ ] #3 A denied or undetermined authorisation degrades honestly and says so in settings
- [ ] #4 No notification is delivered that the policy gate suppressed
<!-- AC:END -->
