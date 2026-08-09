---
id: TASK-40
title: 'Spike: per-application network attribution (FR-051)'
status: Done
assignee: []
created_date: '2026-08-02 01:07'
updated_date: '2026-08-09 21:45'
labels:
  - spike
milestone: m-4
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Suspect this needs the private NetworkStatistics framework. Likely omit for MAS.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every candidate public route to per-process network bytes is measured, sandboxed and unsandboxed, with counts (not impressions)
- [x] #2 Measurements are taken under a verified real transfer, not on an idle machine
- [x] #3 No private framework is linked or dlopened at any point
- [x] #4 Verdict and evidence appended to probe/FINDINGS.md, reproducible from a checked-in script
- [x] #5 If per-process attribution is unavailable, state whether aggregate-only is deliverable and exactly what it may and may not claim
- [x] #6 Any entitlement that would unlock per-process attribution is named, with whether an ordinary MAS app can obtain it
- [x] #7 Proposed FR-051 wording is written out for the product owner to apply or reject (spike does not amend the spec)
- [ ] #8 Re-validated on macOS 26 as well as 27
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Verdict: per-application network attribution is NOT available to a sandboxed MAS build. Aggregate, machine-wide throughput is** — with no entitlement beyond `app-sandbox`. Evidence in `probe/FINDINGS.md` (section "Per-application network attribution (`net-probe.swift`)"); probe `probe/Sources/net-probe.swift`, runner `probe/run-net-probe.sh`. Measured on macOS 27 / M2 under a verified 256 MB loopback transfer (the runner asserts `200 268435456` before sampling), signed `.app` launched via `open`, entitlements = app-sandbox only.

Routes measured, unsandboxed → sandboxed:
- `getifaddrs`/`if_data`: 26 of 46 entries carry counters, **identical sandboxed**. Per interface, not per process.
- `sysctl NET_RT_IFLIST2`/`if_data64`: 12736 B, 138 messages, 26 interfaces, **identical sandboxed**. Per interface.
- `libproc PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO`: **445/447 own-uid pids, 523 sockets → 1/447 (self only), 649 EPERM, 0 sockets.** One of the few places the sandbox itself is the binding limit rather than uid.
- `sysctl net.inet.{tcp,udp}.pcblist[_n]`: **48 bytes (header, zero entries) both ways**; `netstat -an` as a normal user lists zero Internet connections on macOS 27. Structs (`xinpgen`, `xsocket_n`, `xsockstat_n`) are not in the public SDK.
- `NWPathMonitor`: reachability and interface type only; no counter exists in the API.
- exec `/usr/bin/nettop` (links private NetworkStatistics; nothing linked or dlopened here): **exit 0 / 37 rows unsandboxed → `NStatManagerCreate failed`, exit 70 sandboxed.** The private route is closed by the sandbox as well as by App Review.

It would not have helped anyway: `struct socket_info` carries `sbi_cc` (current queue occupancy), not cumulative bytes — `curl` mid-transfer showed `1 socket, 196608 queued_B`, a queue depth that cannot be differenced into a rate.

**Entitlement that would unlock it, and why it is still a no.** `NEFilterDataProvider` would deliver FR-051 properly: on macOS `NEFilterFlow.sourceAppAuditToken` identifies the originating process and `handleInboundDataFromFlow:readBytesStartOffset:` gives per-flow bytes. It needs **`com.apple.developer.networking.networkextension`**, value `content-filter-provider` (appex, App Store) or `content-filter-provider-systemextension` (Developer ID). That is a restricted entitlement granted only on request for stated use cases, and per Apple DTS/TN3134 a distributed macOS content filter must be configured by an MDM configuration profile, not by the app. A general-purpose diagnostic utility is not a case Apple grants it for. Researched, not measured — flagged as such.

**Measurement rule this produced, which outlives the verdict:** aggregate interface counters wrap at 2^32 **even through the 64-bit `if_data64` field**. Measured: during a 3.9 GB/6 s loopback transfer `lo0` read `before=1688087552 after=1281142784` from `if_data64.ifi_ibytes`; a naive subtraction yields 1.8×10^19. Any FR-051 implementation must detect a counter running backwards, correct modulo 2^32, and label the corrected interval. Loopback also needs separating: one local file copy put 3.9 GB through `lo0` in six seconds, which folded into a single "network" figure would read as a WAN transfer.

**Proposed FR-051 amendment — NOT APPLIED. `requirements.md` was not edited; this is for the product owner to accept or reject.** Same pattern as the FR-009 aggregate-only narrowing in spec v1.2. Verbatim replacement rows:

- **Requirement statement:** "The system may record aggregate, machine-wide network throughput from per-interface counters as supporting incident evidence. Per-application network attribution is unavailable to a sandboxed Mac App Store build and is out of scope."
- **Preconditions:** "Public, distribution-compatible per-interface counters are available (`getifaddrs`/`if_data`, `sysctl NET_RT_IFLIST2`/`if_data64`). Verified sandboxed with no entitlement beyond `com.apple.security.app-sandbox`."
- **Expected behavior:** "Compute rates from deltas of per-interface counters. Detect a counter that has run backwards, correct it modulo 2^32, and label any corrected interval as corrected. Report loopback interfaces separately from external ones. Never attribute throughput to an application or process. Do not diagnose network latency from throughput alone."
- **Expected outcome:** "User can see whether sustained machine-wide network transfer coincided with a slowdown, and can see that which application caused it is not measurable."
- **Acceptance criteria:** "Cumulative counters are not mislabeled as current rates; counter wrap is detected, corrected and labelled; loopback traffic is not folded into external throughput; the feature can be disabled; the absence of per-application attribution is stated explicitly in the interface rather than silently omitted."
- **Confidence level:** "High for aggregate throughput; per-application attribution ruled out by measurement (TASK-40)."
- **Open questions or assumptions:** "Settled on macOS 27 by TASK-40. Re-validate on macOS 26 with TASK-45. Would only change if Apple exposed a public per-process network counter, or if the product accepted the NetworkExtension content-filter entitlement and its distribution constraints — both currently rejected."

If the amendment is accepted, the design's per-app network affordances (if any) must go with it, and CLAUDE.md's "Still unproven: ... per-app network (FR-051)" line should move to the resolved list alongside FR-009 and FR-048. Neither file was touched by this spike.

Closed as Done with acceptance criterion #8 (macOS 26) deliberately unchecked: every finding in `probe/FINDINGS.md` is macOS 27 only, and blanket re-validation on macOS 26 is TASK-45's job, not this spike's. Nothing here was inferred from a macOS 26 run — it is simply not verified there.
<!-- SECTION:NOTES:END -->
