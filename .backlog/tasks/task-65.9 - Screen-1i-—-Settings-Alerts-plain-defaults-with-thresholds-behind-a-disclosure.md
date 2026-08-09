---
id: TASK-65.9
title: >-
  Screen 1i — Settings: Alerts, plain defaults with thresholds behind a
  disclosure
status: In Progress
assignee: []
created_date: '2026-08-09 02:23'
updated_date: '2026-08-09 04:45'
labels:
  - ui
milestone: m-3
dependencies: []
parent_task_id: TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/1i.png`. Current state: `screenshots/05-settings.png`. Existing implementation: a single Form with three rows (TASK-25, TASK-34).

**What the design specifies**

Five tabs: General / Alerts / Apps / Privacy / Advanced. The Alerts tab:

- "Tell me about slowdowns" — "One notification per slowdown, unless it gets noticeably worse."
- "How sensitive should I be?" — a Relaxed / Balanced / Sensitive segmented control, with the current setting spelled out in words underneath: "Balanced: alert after 3 minutes of sustained trouble." The plain-language restatement is the point; the user never has to decode the setting.
- "Stay quiet during Focus" — "Slowdowns are still recorded and waiting when you come back."
- "Don't interrupt during calls or playback" — "Holds notifications while an app is playing audio or using the microphone." This is the FR-019 audio signal, which CLAUDE.md confirms is available sandboxed via `kAudioHardwarePropertyProcessObjectList`, used for a genuinely useful purpose rather than as a metric.
- **"Exact thresholds"** behind a disclosure, labelled "Overrides 'Balanced' for the Everyday profile": Total CPU above 85% of 10 cores, for at least 3 min 0 s; Memory pressure Warning or above for 90 s.
- "Also compare to — What's normal for this Mac", "Learned locally over 14 days. Incidents will say whether they crossed the fixed number, the learned normal, or both." with "Reset what it learned". That is FR-053 / TASK-37.
- Footer tying the whole tab to the active profile: "These settings belong to the **Everyday** profile. Switch profiles in the sidebar…"

**Gap against what we render today**

Our Settings is one untabbed pane with "Show in menu bar", "Start at login" and a Notifications status line. Nothing about sensitivity, thresholds, Focus, audio suppression, or learned baselines exists. See also TASK-64 for the layout defect in the current pane.

The two-layer structure — a plain choice up top, exact numbers behind a disclosure — is what keeps FR-006's duration thresholds configurable without putting a control panel in front of an ordinary user.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings is organised into tabs rather than a single pane
- [ ] #2 Alert sensitivity is chosen in plain language, with the resulting behaviour restated in words
- [ ] #3 Exact duration and level thresholds are reachable behind a disclosure and stated in the same units the incident detail later reports
- [ ] #4 Notifications can be held during Focus and during audio or microphone use, without suppressing recording
- [ ] #5 Where a learned baseline is used, incidents state whether a fixed threshold, the learned normal, or both were crossed (FR-053)
- [ ] #6 The tab makes clear which profile the settings belong to (FR-025, FR-026)
- [ ] #7 Verified on screen against design/screens/1i.png
<!-- AC:END -->
