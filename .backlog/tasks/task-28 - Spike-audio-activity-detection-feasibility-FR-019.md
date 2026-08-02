---
id: TASK-28
title: 'Spike: audio-activity detection feasibility (FR-019)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-02 04:17'
labels:
  - spike
milestone: m-2
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Untested. Needed to avoid disruptive recommendations during playback/meetings. May be omitted if not reliably available.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AVAILABLE, and better than the spec assumed. FR-019 can be implemented fully rather than omitted.

kAudioHardwarePropertyProcessObjectList (macOS 14.2+) works sandboxed with no microphone permission and no entitlement beyond app-sandbox. Per audio process we get the pid -- resolvable to a name -- plus IsRunning, IsRunningInput and IsRunningOutput.

Verified by measuring twice rather than trusting a single reading, since all-zeros could equally have meant a non-functioning API:
  idle:    28 objects, 0 running, DeviceIsRunningSomewhere = 0
  playing: 28 objects, 1 running, DeviceIsRunningSomewhere = 1
           ACTIVE: afplay [26397] running=1 input=0 output=1

The input/output split is what FR-019 actually needs: output covers playback, input covers microphone use, so 'don't interrupt a call or playback' is implementable per-application rather than as a blunt device-level check. kAudioDevicePropertyDeviceIsRunningSomewhere remains as a fallback.

CAVEAT, stated because it is unverified: output was confirmed against real playback; input was NOT. Triggering it would mean starting a microphone capture on the user's machine. The property is read through the identical code path so the risk is low, but it has not been exercised.

Design implication: 1i's 'Don't interrupt during calls or playback' can drop its 'pending feasibility' marker. FR-019's Medium-High confidence rating can be raised.
<!-- SECTION:NOTES:END -->
