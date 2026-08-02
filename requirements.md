# MacSlowdown — Product Definition and Functional Requirements

**Document status:** Greenfield product specification  
**Version:** 1.2  
**Last updated:** August 1, 2026

> **Revision note (1.2):** amended to reflect capabilities measured against a
> sandboxed Mac App Store build rather than assumed. Sources are recorded in
> `probe/FINDINGS.md`. Changes: FR-009 narrowed to aggregate disk I/O; FR-019
> confirmed and strengthened; FR-043 fixed to resident memory; FR-046 narrowed to
> lifecycle and relaunch signals; FR-048 moved out of scope for this release; a
> new FR-055 requires unattributed system activity to be shown; §6 makes
> standalone processes first-class; §7 and §10 updated to measured fact.

> **Purpose:** This document is the authoritative product-definition and implementation specification for **MacSlowdown**, a greenfield macOS performance-monitoring and diagnostic application intended first for distribution through the Mac App Store. It defines the user problem, product boundaries, user outcomes, functional requirements, nonfunctional requirements, release phases, and open product and engineering decisions.

MacSlowdown shall be designed and implemented as a greenfield product. This specification defines desired behavior and acceptance criteria without prescribing a particular interface, internal architecture, algorithm, or visual design except where required for safety, accessibility, privacy, platform compatibility, or testability.

# 1. Problem statement and desired outcome

Mac users frequently experience a computer that feels slow, hot, noisy, unresponsive, or unusually power-hungry without a clear explanation. Existing system tools can show current measurements, but they often require the user to notice the problem while it is happening, understand low-level process terminology, correlate several resource categories manually, and decide whether a high value is actually abnormal. By the time the user opens a diagnostic utility, the responsible process may have stopped, relaunched, or changed its behavior.

The problem is therefore not merely a lack of gauges. The product must shorten the path from **“my Mac feels slow”** to a defensible, understandable answer:

1. What resource or condition was constrained?
2. Which application family or process likely contributed?
3. Was the behavior transient, sustained, expected, or unusual for this Mac?
4. What safe action can the user take now?
5. Did that action improve the condition?

MacSlowdown should continuously and locally observe performance-related conditions, preserve bounded evidence before and during a slowdown, group technical processes into user-meaningful applications, explain observations without overstating causation, and offer only actions that are safe and permitted by the current distribution model. MacSlowdown should remain useful as a monitoring and diagnostic tool even when deeper process control is unavailable.

## 1.1 Primary user outcomes

- Detect sustained performance degradation without requiring the user to watch live charts.
- Explain whether CPU, memory pressure, swap activity, disk I/O, low storage capacity, thermal pressure, application hangs, background activity, or another observable condition contributed.
- Identify likely application-level contributors while preserving access to individual process details.
- Retain enough pre-trigger and recovery history to investigate incidents after they end.
- Reduce false alarms through duration thresholds, hysteresis, user policies, and machine-specific baselines where practical.
- Give the user safe, verifiable remediation choices rather than promising generic optimization or automatic repair.
- Keep sensitive process, path, and incident data local by default.

## 1.2 Product success definition

MacSlowdown succeeds when a user can open an incident and understand, in plain language, what measurable condition occurred, which applications were associated with it, how confident the diagnosis is, and what happened after any user-directed action. It does not need to guarantee that every slowdown can be diagnosed or fixed. Unavailable measurements, ambiguous attribution, and unsupported actions must be stated explicitly.

# 2. Purpose and product boundary

MacSlowdown is a native macOS utility that continuously observes system
resource conditions, detects sustained performance degradation,
identifies likely contributing applications or processes, preserves
recent evidence, explains the incident in clear, measured terms, and offers safe
user-directed remediation. The initial release is a Mac App Store application and shall rely only on capabilities compatible with App Sandbox and current App Review requirements. Privileged-helper and advanced process-control capabilities are deferred and are not part of the initial implementation.

- Primary value: reduce the time between “the Mac feels slow” and a
  defensible explanation of which resource is constrained and which
  application family is contributing.

- Primary resources and contexts: CPU, application and system memory, memory pressure, swap/paging, disk I/O, storage capacity, thermal state, power context, process lifecycle, responsiveness signals, and other public metrics whose collection is technically and legally supportable.

- Primary interaction surfaces: compact persistent status, on-demand
  detail, notifications and retained incident reports.

- Out of scope for the initial release: malware classification,
  antivirus, fan control, hardware repair diagnosis, guaranteed memory
  reclamation, undocumented sensor dependencies, automatic killing of
  protected system services and cloud-based behavioral surveillance.

# 3. Users and roles

| **Role**          | **Objective**                                                                               | **Permissions**                                                                                      |
|-------------------|---------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|
| Standard user     | Understand slowdowns and manage applications they own or launched.                          | View system and process metrics available to the app; configure notifications; request safe actions. |
| Power user        | Create targeted policies, inspect process families, export diagnostics and tune thresholds. | All standard-user permissions plus advanced settings and automation.                                 |
| Support recipient | Review a user-exported, redacted incident report.                                           | No direct access to the Mac; receives only user-approved exported data.                              |
| System            | Collect metrics, evaluate conditions, preserve bounded history and enforce safety policy.   | No discretionary access beyond granted entitlements and authorization.                               |

# 4. Global assumptions and design constraints

- A-01: The supported operating systems are **macOS 26 and macOS 27**. The initial hardware target is Apple Silicon. Intel support is not required unless separately approved.

- A-02: Swift is the preferred implementation language. SwiftUI may be
  used for most UI, with AppKit and public C/Mach interfaces where
  needed.

- A-03: The initial release shall operate without privileged helpers or elevated components. Monitoring, diagnosis, history, notifications, export, and safe user guidance must remain useful within App Sandbox.

- A-04: The initial distribution target is the **Mac App Store**. The shipping build shall be sandboxed, self-contained, and limited to public APIs and entitlements accepted for Mac App Store distribution. Features that require controlling unrelated processes are deferred.

- A-05: All process and incident data remains local by default. No
  telemetry containing process identity, file paths or incident contents
  is transmitted without separate explicit consent.

- A-06: Thresholds are configurable and should be adaptive where
  practical; no single fixed threshold is assumed correct for every
  machine or workload.

- A-07: Presentation design is intentionally unconstrained by this requirements document. UI screens and interaction concepts will be developed separately using **Claude Design**, then reviewed against these requirements for accessibility, feasibility, privacy, and platform compliance.

# 5. Functional and nonfunctional requirements

## FR-001 — The system shall provide a compact persistent status surface that represents current overall performance condition.

| **Field**                     | **Specification**                                                                                                       |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-001                                                                                                                  |
| Requirement statement | The system shall provide a compact persistent status surface that represents current overall performance condition.     |
| User or system objective      | Let the user notice degradation without opening a full window.                                                          |
| Preconditions                 | Application is running and status display is enabled.                                                                   |
| Trigger                       | A new aggregate sample is available.                                                                                    |
| Expected behavior             | Update a compact indicator using a severity model calculated from monitored resources.                             |
| Expected outcome              | User can distinguish normal, elevated and severe conditions at a glance.                                                |
| Acceptance criteria           | Indicator updates within 2 seconds of a severity transition; can be hidden; remains accessible to assistive technology. |
| Confidence level              | High                                                                                                                    |
| Design freedom                | Any menu-bar text, symbol, gauge or combined representation may be used.                                                |
| Open questions or assumptions | Exact severity model and user customization.                                                                            |
| Human-review status           | Approved                                                                                                                |

## FR-002 — The system shall present a current inventory of observable applications and processes with resource measurements.

| **Field**                     | **Specification**                                                                                                        |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-002                                                                                                                   |
| Requirement statement | The system shall present a current inventory of observable applications and processes with resource measurements.        |
| User or system objective      | Identify current consumers.                                                                                              |
| Preconditions                 | Metrics permissions and process APIs are available.                                                                      |
| Trigger                       | User opens the detail surface or an incident requests investigation mode.                                                |
| Expected behavior             | Display process identity and available CPU and memory measurements, with clear units and timestamps.                     |
| Expected outcome              | User can identify leading contributors.                                                                                  |
| Acceptance criteria           | Top consumers agree with an authorized reference tool within defined tolerance; stale or unavailable values are labeled. |
| Confidence level              | High                                                                                                                     |
| Design freedom                | Table, list, outline or another independently designed view.                                                             |
| Open questions or assumptions | Tolerance and unavailable-process behavior.                                                                              |
| Human-review status           | Approved                                                                                                                 |

## FR-003 — The system shall group related processes into a user-meaningful application family while allowing expansion to individual processes.

| **Field**                     | **Specification**                                                                                                                    |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-003                                                                                                                               |
| Requirement statement | The system shall group related processes into a user-meaningful application family while allowing expansion to individual processes. |
| User or system objective      | Prevent helper-heavy applications from being fragmented across many rows.                                                            |
| Preconditions                 | Process identity and relationship signals are available.                                                                             |
| Trigger                       | Process inventory is refreshed.                                                                                                      |
| Expected behavior             | Associate processes using public metadata and confidence-scored heuristics; preserve individual PID records.                         |
| Expected outcome              | User sees both aggregate application impact and underlying contributors.                                                             |
| Acceptance criteria           | Known browser/helper test fixtures aggregate correctly; uncertain associations are labeled and reversible.                           |
| Confidence level              | High                                                                                                                                 |
| Design freedom                | Any grouping algorithm based on public data; do not assume a specific proprietary method.                                            |
| Open questions or assumptions | Handling launchd/XPC-orphaned helpers.                                                                                               |
| Human-review status           | Review required                                                                                                                      |

## FR-004 — The system shall display process CPU in both core-relative and machine-relative terms or explain the chosen convention.

| **Field**                     | **Specification**                                                                                                       |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-004                                                                                                                  |
| Requirement statement | The system shall display process CPU in both core-relative and machine-relative terms or explain the chosen convention. |
| User or system objective      | Avoid confusion when a process exceeds 100 percent.                                                                     |
| Preconditions                 | CPU topology is available.                                                                                              |
| Trigger                       | CPU values are shown.                                                                                                   |
| Expected behavior             | Normalize and label CPU units consistently.                                                                             |
| Expected outcome              | User understands the share of one core and total system capacity.                                                       |
| Acceptance criteria           | A synthetic two-core workload is represented accurately under the documented convention.                                |
| Confidence level              | High                                                                                                                    |
| Design freedom                | Either dual display or one display plus contextual explanation.                                                         |
| Open questions or assumptions | Treatment of efficiency/performance core asymmetry.                                                                     |
| Human-review status           | Approved                                                                                                                |

## FR-005 — The system shall maintain a bounded rolling history of aggregate and leading-contributor metrics.

| **Field**                     | **Specification**                                                                                                 |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-005                                                                                                            |
| Requirement statement | The system shall maintain a bounded rolling history of aggregate and leading-contributor metrics.                 |
| User or system objective      | Preserve evidence before the user opens the app.                                                                  |
| Preconditions                 | Monitoring is active.                                                                                             |
| Trigger                       | Each sample interval completes.                                                                                   |
| Expected behavior             | Append samples to an in-memory or local persistent ring buffer; evict according to retention policy.              |
| Expected outcome              | Recent behavior can be inspected without unbounded storage growth.                                                |
| Acceptance criteria           | Default history covers at least 15 minutes; memory and disk budgets are met; restart persistence is configurable. |
| Confidence level              | High                                                                                                              |
| Design freedom                | Storage format and visualization are implementation choices.                                                      |
| Open questions or assumptions | Default duration and persistence policy.                                                                          |
| Human-review status           | Approved                                                                                                          |

## FR-006 — The system shall detect sustained aggregate CPU saturation and identify likely contributing process families.

| **Field**                     | **Specification**                                                                                                                 |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-006                                                                                                                            |
| Requirement statement | The system shall detect sustained aggregate CPU saturation and identify likely contributing process families.                     |
| User or system objective      | Recognize CPU-driven slowdowns.                                                                                                   |
| Preconditions                 | CPU samples and process attribution are available.                                                                                |
| Trigger                       | Aggregate CPU exceeds a configurable threshold for a configurable duration.                                                       |
| Expected behavior             | Open or update an incident, rank contributors by interval CPU, and track persistence.                                             |
| Expected outcome              | User receives a defensible CPU incident record.                                                                                   |
| Acceptance criteria           | No alert for a single transient spike shorter than the configured duration; contributor shares sum consistently within tolerance. |
| Confidence level              | High                                                                                                                              |
| Design freedom                | Detection model may be rules, statistics or another explainable approach.                                                         |
| Open questions or assumptions | Default thresholds by core count and power mode.                                                                                  |
| Human-review status           | Approved                                                                                                                          |

## FR-007 — The system shall monitor system memory-pressure state.

| **Field**                     | **Specification**                                                                                            |
|-------------------------------|--------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-007                                                                                                       |
| Requirement statement | The system shall monitor system memory-pressure state.                                                       |
| User or system objective      | Detect memory-related degradation rather than relying on free-memory percentage.                             |
| Preconditions                 | Public memory-pressure API is available.                                                                     |
| Trigger                       | Memory-pressure state changes or periodic verification occurs.                                               |
| Expected behavior             | Record pressure level and transition times; use it in incident severity.                                     |
| Expected outcome              | User can distinguish CPU saturation from memory pressure.                                                    |
| Acceptance criteria           | Pressure transitions are captured within 2 seconds; UI avoids describing cached memory as inherently wasted. |
| Confidence level              | High                                                                                                         |
| Design freedom                | Any neutral status representation.                                                                           |
| Open questions or assumptions | Fallback for API anomalies.                                                                                  |
| Human-review status           | Approved                                                                                                     |

## FR-008 — The system shall monitor swap, compression and paging trends where public metrics are available.

| **Field**                     | **Specification**                                                                                        |
|-------------------------------|----------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-008                                                                                                   |
| Requirement statement | The system shall monitor swap, compression and paging trends where public metrics are available.         |
| User or system objective      | Identify memory churn that can produce disk activity and lag.                                            |
| Preconditions                 | Required counters are available on the target OS.                                                        |
| Trigger                       | Periodic sampler runs or memory pressure rises.                                                          |
| Expected behavior             | Compute interval deltas and rates; retain underlying counters for verification.                                     |
| Expected outcome              | Incident analysis can identify rising swap or paging activity.                                           |
| Acceptance criteria           | Rates never derive from cumulative totals without delta calculation; counter reset and wrap are handled. |
| Confidence level              | Medium-High                                                                                              |
| Design freedom                | Metric selection and storage are open.                                                                   |
| Open questions or assumptions | Public API stability and terminology.                                                                    |
| Human-review status           | Review required                                                                                          |

## FR-009 — The system shall monitor aggregate disk read and write throughput.

| **Field**                     | **Specification**                                                                                               |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-009                                                                                                          |
| Requirement statement | The system shall monitor aggregate disk read and write throughput. Per-process I/O is **not available** to a sandboxed build and is excluded. |
| User or system objective      | Detect I/O-driven slowdowns and contributors.                                                                   |
| Preconditions                 | Public process and disk counters are accessible.                                                                |
| Trigger                       | Sampling interval completes.                                                                                    |
| Expected behavior             | Compute rates from monotonic counters; state plainly that per-application disk activity is unavailable rather than omitting it silently. |
| Expected outcome              | User can see whether disk activity is elevated, and understands why it cannot be attributed to an application.  |
| Acceptance criteria           | Cumulative bytes are not mislabeled as current rate; the absence of per-application attribution is stated in the interface. |
| Confidence level              | High for aggregate; per-process measured as unavailable                                                         |
| Design freedom                | Presentation of the aggregate figure is open.                                                                   |
| Open questions or assumptions | `proc_pid_rusage` is denied under App Sandbox (measured: 1 of 1058 processes, ourselves), which removes per-process I/O entirely. APFS caching interpretation remains open. |
| Human-review status           | Approved — amended in v1.2 from measurement                                                                     |

## FR-010 — The system shall monitor public thermal-pressure state and record changes during incidents.

| **Field**                     | **Specification**                                                                                            |
|-------------------------------|--------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-010                                                                                                       |
| Requirement statement | The system shall monitor public thermal-pressure state and record changes during incidents.                  |
| User or system objective      | Explain performance reductions associated with system thermal conditions.                                    |
| Preconditions                 | Thermal-state API is available.                                                                              |
| Trigger                       | State changes or periodic checks occur.                                                                      |
| Expected behavior             | Record thermal state and incorporate it into analysis without asserting undocumented throttling details.     |
| Expected outcome              | User can see when thermal pressure coincides with degradation.                                               |
| Acceptance criteria           | State changes are time-correlated with incident history; unavailable hardware temperature is not fabricated. |
| Confidence level              | High                                                                                                         |
| Design freedom                | Temperature display is optional; thermal state is sufficient.                                                |
| Open questions or assumptions | Whether to expose raw temperature when safely available.                                                     |
| Human-review status           | Approved                                                                                                     |

## FR-011 — The system shall create an incident when one or more sustained degradation conditions are met.

| **Field**                     | **Specification**                                                                                                                              |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-011                                                                                                                                         |
| Requirement statement | The system shall create an incident when one or more sustained degradation conditions are met.                                                 |
| User or system objective      | Convert continuous metrics into actionable episodes.                                                                                           |
| Preconditions                 | Monitoring and rule evaluation are active.                                                                                                     |
| Trigger                       | A rule crosses its trigger duration.                                                                                                           |
| Expected behavior             | Create one incident with start time, active conditions, severity and leading contributors; merge related signals within a configurable window. |
| Expected outcome              | User receives one coherent episode rather than repeated alerts.                                                                                |
| Acceptance criteria           | Repeated samples do not create duplicate incidents; incident closes only after recovery hysteresis.                                            |
| Confidence level              | High                                                                                                                                           |
| Design freedom                | Rules, statistical detection or hybrid model allowed; must remain explainable.                                                                 |
| Open questions or assumptions | Merge window and hysteresis defaults.                                                                                                          |
| Human-review status           | Approved                                                                                                                                       |

## FR-012 — The system shall preserve pre-trigger, active and recovery-period evidence for each retained incident.

| **Field**                     | **Specification**                                                                                                |
|-------------------------------|------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-012                                                                                                           |
| Requirement statement | The system shall preserve pre-trigger, active and recovery-period evidence for each retained incident.           |
| User or system objective      | Allow post-event diagnosis after the slowdown ends.                                                              |
| Preconditions                 | Rolling history exists.                                                                                          |
| Trigger                       | Incident opens and later recovers.                                                                               |
| Expected behavior             | Attach a bounded window before trigger, all active samples and a bounded post-recovery window.                   |
| Expected outcome              | Incident remains useful after the offender stops.                                                                |
| Acceptance criteria           | Report contains at least 2 minutes pre-trigger and 1 minute post-recovery by default, subject to storage policy. |
| Confidence level              | High                                                                                                             |
| Design freedom                | Exact duration and persistence configurable.                                                                     |
| Open questions or assumptions | Privacy-sensitive retention defaults.                                                                            |
| Human-review status           | Approved                                                                                                         |

## FR-013 — The system shall generate an evidence-based incident summary that distinguishes observations from hypotheses.

| **Field**                     | **Specification**                                                                                                            |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-013                                                                                                                       |
| Requirement statement | The system shall generate an evidence-based incident summary that distinguishes observations from hypotheses.                |
| User or system objective      | Explain what happened without overstating causation.                                                                         |
| Preconditions                 | Incident has sufficient samples.                                                                                             |
| Trigger                       | Incident changes severity, closes or user opens it.                                                                          |
| Expected behavior             | Summarize constrained resource, duration, measured contributors, confidence and alternative explanations.                    |
| Expected outcome              | User can decide what to inspect or close.                                                                                    |
| Acceptance criteria           | Every causal phrase is labeled by confidence; raw measurements and time range are accessible; unsupported claims are absent. |
| Confidence level              | High                                                                                                                         |
| Design freedom                | Template, rules engine or local model allowed; no cloud requirement.                                                         |
| Open questions or assumptions | Whether to use an on-device language model.                                                                                  |
| Human-review status           | Review required                                                                                                              |

## FR-014 — The system shall notify the user according to a configurable notification policy.

| **Field**                     | **Specification**                                                                                                       |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-014                                                                                                                  |
| Requirement statement | The system shall notify the user according to a configurable notification policy.                                       |
| User or system objective      | Surface meaningful incidents without excessive interruption.                                                            |
| Preconditions                 | Notifications are authorized and an incident meets policy.                                                              |
| Trigger                       | Severity threshold and duration are met.                                                                                |
| Expected behavior             | Issue a notification containing resource category, top contributor when confident, and safe actions.                    |
| Expected outcome              | User can inspect, mute or defer.                                                                                        |
| Acceptance criteria           | No more than one notification per incident unless severity materially increases; Focus and user settings are respected. |
| Confidence level              | High                                                                                                                    |
| Design freedom                | Notification text and actions independently designed.                                                                   |
| Open questions or assumptions | Default severity and Focus behavior.                                                                                    |
| Human-review status           | Approved                                                                                                                |

## FR-015 — The system shall allow warnings to be muted for a selected duration and allow automatic controls to be temporarily disabled.

| **Field**                     | **Specification**                                                                                                            |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-015                                                                                                                       |
| Requirement statement | The system shall allow warnings to be muted for a selected duration and allow automatic controls to be temporarily disabled. |
| User or system objective      | Support known heavy workloads and reduce notification fatigue.                                                               |
| Preconditions                 | User has access to controls.                                                                                                 |
| Trigger                       | User selects a mute or disable period.                                                                                       |
| Expected behavior             | Suppress applicable notifications or controls until expiry while optionally continuing passive monitoring.                   |
| Expected outcome              | User can run intentional workloads without reconfiguration.                                                                  |
| Acceptance criteria           | State clearly shows remaining duration; automatic re-enable occurs; incident history remains available unless disabled.      |
| Confidence level              | High                                                                                                                         |
| Design freedom                | Preset durations and presentation are open.                                                                                  |
| Open questions or assumptions | Maximum duration and restart behavior.                                                                                       |
| Human-review status           | Approved                                                                                                                     |

## FR-016 — The system shall provide per-application allow, ignore and expected-workload policies.

| **Field**                     | **Specification**                                                                          |
|-------------------------------|--------------------------------------------------------------------------------------------|
| Requirement ID                | FR-016                                                                                     |
| Requirement statement | The system shall provide per-application allow, ignore and expected-workload policies.     |
| User or system objective      | Prevent repeated false positives for known behavior.                                       |
| Preconditions                 | A process family can be identified.                                                        |
| Trigger                       | User classifies a process or edits policy.                                                 |
| Expected behavior             | Apply policy to future incidents while retaining an audit trail of suppressed detections.  |
| Expected outcome              | Alerts become personalized without hiding all evidence.                                    |
| Acceptance criteria           | Ignored process does not trigger its excluded rule; user can review and revoke the policy. |
| Confidence level              | High                                                                                       |
| Design freedom                | Policy model and labels are open.                                                          |
| Open questions or assumptions | Bundle changes and unsigned executables.                                                   |
| Human-review status           | Approved                                                                                   |

## FR-017 — The system shall provide safe user-directed process actions that are available under the current distribution and permission model.

| **Field**                     | **Specification**                                                                                                                                            |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-017                                                                                                                                                       |
| Requirement statement | The system shall provide safe user-directed process actions that are available under the current distribution and permission model.                          |
| User or system objective      | Let the user investigate and respond to a confirmed contributor without automatic suspension or quitting.                                                                                                                 |
| Preconditions                 | Target process is observable and action is permitted.                                                                                                        |
| Trigger                       | User chooses an action.                                                                                                                                      |
| Expected behavior             | Offer only supported non-destructive actions, such as activate, reveal, open a filtered system monitor, copy diagnostics, mute an alert, ignore an application, or show user guidance; report success or failure. |
| Expected outcome              | User can act without guessing which PID is involved.                                                                                                         |
| Acceptance criteria           | Unavailable actions are not shown as working; action results are verified asynchronously.                                                                    |
| Confidence level              | High                                                                                                                                                         |
| Design freedom                | Action set may differ by build.                                                                                                                              |
| Open questions or assumptions | Exact App Sandbox availability of each non-destructive action.                                                                                                                |
| Human-review status           | Review required                                                                                                                                              |

## FR-018 — The system shall maintain a non-overridable safety policy for protected operating-system processes.

| **Field**                     | **Specification**                                                                                                      |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-018                                                                                                                 |
| Requirement statement | The system shall maintain a non-overridable safety policy for protected operating-system processes.                    |
| User or system objective      | Prevent destabilizing controls.                                                                                        |
| Preconditions                 | Process identity is known.                                                                                             |
| Trigger                       | A user or policy attempts a hazardous action.                                                                          |
| Expected behavior             | Block the action, explain at a category level, and offer observation-only alternatives.                                |
| Expected outcome              | System stability is prioritized.                                                                                       |
| Acceptance criteria           | Protected fixtures cannot be targeted by unsupported control actions; safety policy updates independently from user preferences. |
| Confidence level              | High                                                                                                                   |
| Design freedom                | Classification implementation is open.                                                                                 |
| Open questions or assumptions | Update mechanism and false positives.                                                                                  |
| Human-review status           | Approved                                                                                                               |

## FR-019 — The system shall detect active audio use where public APIs permit and avoid disruptive recommendations during active audio use.

| **Field**                     | **Specification**                                                                                                    |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-019                                                                                                               |
| Requirement statement | The system shall detect active audio use per application and avoid disruptive recommendations and notifications during it. |
| User or system objective      | Prevent playback, meetings and recording from being interrupted.                                                     |
| Preconditions                 | None beyond App Sandbox. Measured available with no microphone permission and no additional entitlement.              |
| Trigger                       | A recommendation or notification concerns an audio-active application.                                                                |
| Expected behavior             | Distinguish output (playback) from input (microphone), defer disruptive recommendations, and explain the risk of interrupting active playback, meetings, or recording. |
| Expected outcome              | Active media remains usable.                                                                                         |
| Acceptance criteria           | Test audio workload receives no suspension or quit action; any guidance is explicit and non-destructive; input and output activity are distinguished rather than conflated. |
| Confidence level              | High — measured, not assumed                                                                                         |
| Design freedom                | Presentation is open. Detection is no longer optional: the capability exists.                                        |
| Open questions or assumptions | `kAudioHardwarePropertyProcessObjectList` (macOS 14.2+) yields a pid plus IsRunning / IsRunningInput / IsRunningOutput per audio process. Output verified against live playback; **input not yet exercised**. No privacy concern: no audio content is read, only whether a device is in use. |
| Human-review status           | Approved — strengthened in v1.2 from measurement                                                                     |

## Deferred requirement FR-020 — The system may support configurable per-application CPU ceilings only in builds and contexts where the capability is lawful, safe and technically supported.

| **Field**                     | **Specification**                                                                                                                                            |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-020                                                                                                                                                       |
| Requirement statement | The system may support configurable per-application CPU ceilings only in builds and contexts where the capability is lawful, safe and technically supported. |
| User or system objective      | Reduce impact of a confirmed CPU-heavy background workload.                                                                                                  |
| Preconditions                 | Feature is enabled, target is eligible and user has configured a policy.                                                                                     |
| Trigger                       | Target exceeds its ceiling under applicable state conditions.                                                                                                |
| Expected behavior             | Apply a bounded, reversible control and release it when conditions clear or the app becomes active, according to policy.                                     |
| Expected outcome              | Foreground responsiveness improves without permanently altering the target.                                                                                  |
| Acceptance criteria           | Stress tests show ceiling tolerance; control is released on app exit, utility exit and policy disable; protected processes are excluded.                     |
| Confidence level              | High capability; medium feasibility                                                                                                                          |
| Design freedom                | Mechanism is entirely open and must use permitted APIs.                                                                                                      |
| Open questions or assumptions | Distribution channel and API mechanism.                                                                                                                      |
| Human-review status           | Escalated                                                                                                                                                    |

## Deferred requirement FR-021 — The system may support user-configured background suspension only after explicit risk acknowledgment.

| **Field**                     | **Specification**                                                                                                       |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-021                                                                                                                  |
| Requirement statement | The system may support user-configured background suspension only after explicit risk acknowledgment.                   |
| User or system objective      | Stop CPU consumption from a selected idle application.                                                                  |
| Preconditions                 | Non-protected user application; user explicitly enables suspension.                                                     |
| Trigger                       | Application enters configured inactive state.                                                                           |
| Expected behavior             | Suspend and later resume it; clearly mark controlled state and provide immediate escape.                                |
| Expected outcome              | User understands that the apparent unresponsiveness is intentional.                                                     |
| Acceptance criteria           | No default suspension; visible state; resume on activation or timeout; unsaved-data warning; crash/recovery tests pass. |
| Confidence level              | High capability; medium suitability                                                                                     |
| Design freedom                | Implementation and presentation open.                                                                                   |
| Open questions or assumptions | App Store feasibility and app-specific compatibility.                                                                   |
| Human-review status           | Escalated                                                                                                               |

## Deferred requirement FR-022 — The system may support energy-efficient processor preference for eligible background workloads on supported hardware.

| **Field**                     | **Specification**                                                                                                     |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-022                                                                                                                |
| Requirement statement | The system may support energy-efficient processor preference for eligible background workloads on supported hardware. |
| User or system objective      | Preserve high-performance resources and reduce energy use.                                                            |
| Preconditions                 | Supported Apple Silicon hardware and permitted API.                                                                   |
| Trigger                       | Configured app becomes eligible.                                                                                      |
| Expected behavior             | Apply preference; verify observable scheduling state when possible; restore normal policy when no longer applicable.  |
| Expected outcome              | Background work has reduced interference without being starved.                                                       |
| Acceptance criteria           | Feature is hidden when unsupported; tests cover machines with different core topologies; no universal battery claim.  |
| Confidence level              | High capability; medium feasibility                                                                                   |
| Design freedom                | Exact mechanism open.                                                                                                 |
| Open questions or assumptions | Public API availability and OS behavior.                                                                              |
| Human-review status           | Escalated                                                                                                             |

## Deferred requirement FR-023 — The system may support lower-priority execution for eligible workloads.

| **Field**                     | **Specification**                                                                                                  |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-023                                                                                                             |
| Requirement statement | The system may support lower-priority execution for eligible workloads.                                            |
| User or system objective      | Reduce competition from non-urgent background work.                                                                |
| Preconditions                 | User explicitly enables policy and target is eligible.                                                             |
| Trigger                       | Applicable process is running.                                                                                     |
| Expected behavior             | Apply permitted scheduling or QoS adjustment and restore it on policy exit.                                        |
| Expected outcome              | Foreground work receives preference.                                                                               |
| Acceptance criteria           | Original priority is restored; process failure does not persist system-wide changes; protected processes excluded. |
| Confidence level              | Medium                                                                                                             |
| Design freedom                | Mechanism and labels open.                                                                                         |
| Open questions or assumptions | Disk/network priority claims require validation.                                                                   |
| Human-review status           | Escalated                                                                                                          |

## Deferred requirement FR-024 — The system may support inactivity-based hide or normal-quit requests for explicitly selected applications.

| **Field**                     | **Specification**                                                                                                             |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-024                                                                                                                        |
| Requirement statement | The system may support inactivity-based hide or normal-quit requests for explicitly selected applications.                    |
| User or system objective      | Reduce clutter or resource use from forgotten applications.                                                                   |
| Preconditions                 | User opts in per application; target is eligible.                                                                             |
| Trigger                       | Configured inactivity duration expires.                                                                                       |
| Expected behavior             | Request hide or graceful quit; never auto-confirm an application’s unsaved-data dialog.                                       |
| Expected outcome              | User retains control over data loss.                                                                                          |
| Acceptance criteria           | Default off; action logged; failures reported; foreground or audio-active app is not acted upon unless explicitly configured. |
| Confidence level              | High                                                                                                                          |
| Design freedom                | Feature may be deferred or omitted.                                                                                           |
| Open questions or assumptions | Menu-bar apps and background uploads.                                                                                         |
| Human-review status           | Escalated                                                                                                                     |

## FR-025 — The system shall support named configuration profiles.

| **Field**                     | **Specification**                                                                                  |
|-------------------------------|----------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-025                                                                                             |
| Requirement statement | The system shall support named configuration profiles.                                             |
| User or system objective      | Let users switch monitoring and control behavior by context.                                       |
| Preconditions                 | At least one editable profile exists.                                                              |
| Trigger                       | User selects a profile or an activation rule fires.                                                |
| Expected behavior             | Activate a complete, validated configuration set atomically.                                       |
| Expected outcome              | Behavior changes predictably.                                                                      |
| Acceptance criteria           | Profile switch is logged; invalid configuration cannot partially apply; user can restore defaults. |
| Confidence level              | High                                                                                               |
| Design freedom                | Profile UI and naming open.                                                                        |
| Open questions or assumptions | Conflict resolution between manual and automatic selection.                                        |
| Human-review status           | Approved                                                                                           |

## FR-026 — The system may activate profiles using public contextual signals.

| **Field**                     | **Specification**                                                                                      |
|-------------------------------|--------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-026                                                                                                 |
| Requirement statement | The system may activate profiles using public contextual signals.                                      |
| User or system objective      | Adapt behavior to power, time and workflow context.                                                    |
| Preconditions                 | User has created an activation rule.                                                                   |
| Trigger                       | A supported signal changes.                                                                            |
| Expected behavior             | Evaluate ordered rules and select a profile using a documented precedence policy.                      |
| Expected outcome              | Configuration follows user intent without manual switching.                                            |
| Acceptance criteria           | Rules can be simulated; conflicts are visible; unsupported signals fail safely.                        |
| Confidence level              | High                                                                                                   |
| Design freedom                | Signals may include time, idle, power, battery, active app, process presence, Focus and thermal state. |
| Open questions or assumptions | Privacy and precedence.                                                                                |
| Human-review status           | Approved                                                                                               |

## FR-027 — The system shall provide search, filtering and sorting over current processes and retained incidents.

| **Field**                     | **Specification**                                                                                                |
|-------------------------------|------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-027                                                                                                           |
| Requirement statement | The system shall provide search, filtering and sorting over current processes and retained incidents.            |
| User or system objective      | Find a known application or event quickly.                                                                       |
| Preconditions                 | Relevant records exist.                                                                                          |
| Trigger                       | User enters a query or changes a filter.                                                                         |
| Expected behavior             | Update results without disrupting data collection.                                                               |
| Expected outcome              | User can isolate high consumers and historical incidents.                                                        |
| Acceptance criteria           | Search is case-insensitive by default; filters are keyboard accessible; selection remains stable during refresh. |
| Confidence level              | High                                                                                                             |
| Design freedom                | Any interaction model.                                                                                           |
| Open questions or assumptions | Fuzzy search and saved filters.                                                                                  |
| Human-review status           | Approved                                                                                                         |

## FR-028 — The system shall support a diagnostic export that is previewable and redactable before sharing.

| **Field**                     | **Specification**                                                                                                              |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-028                                                                                                                         |
| Requirement statement | The system shall support a diagnostic export that is previewable and redactable before sharing.                                |
| User or system objective      | Enable support without exposing unnecessary data.                                                                              |
| Preconditions                 | An incident exists.                                                                                                            |
| Trigger                       | User requests export.                                                                                                          |
| Expected behavior             | Generate a local report with selected metrics, timestamps, system summary and optional process identities; preview redactions. |
| Expected outcome              | User controls what leaves the device.                                                                                          |
| Acceptance criteria           | No transmission occurs automatically; file paths, usernames and process names can be redacted; export records schema version.  |
| Confidence level              | High                                                                                                                           |
| Design freedom                | PDF, JSON, text or bundle formats may be selected independently.                                                               |
| Open questions or assumptions | Default redactions and support format.                                                                                         |
| Human-review status           | Approved                                                                                                                       |

## FR-029 — The system shall keep monitoring data local by default and provide retention controls.

| **Field**                     | **Specification**                                                                                                          |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-029                                                                                                                     |
| Requirement statement | The system shall keep monitoring data local by default and provide retention controls.                                     |
| User or system objective      | Protect sensitive usage and process information.                                                                           |
| Preconditions                 | Application is installed.                                                                                                  |
| Trigger                       | Data is collected or user opens privacy settings.                                                                          |
| Expected behavior             | Store locally, document categories, permit deletion and configurable retention, and require separate opt-in for telemetry. |
| Expected outcome              | Users can use core features without cloud disclosure.                                                                      |
| Acceptance criteria           | Fresh install sends no process inventory; delete action removes retained incidents; privacy settings are accessible.       |
| Confidence level              | High                                                                                                                       |
| Design freedom                | Encryption-at-rest implementation open.                                                                                    |
| Open questions or assumptions | Crash reporting scope.                                                                                                     |
| Human-review status           | Approved                                                                                                                   |

## FR-030 — The system shall operate with bounded CPU, memory, disk and wake-up overhead.

| **Field**                     | **Specification**                                                                                                                                                                    |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-030                                                                                                                                                                               |
| Requirement statement | The system shall operate with bounded CPU, memory, disk and wake-up overhead.                                                                                                        |
| User or system objective      | Avoid becoming part of the slowdown.                                                                                                                                                 |
| Preconditions                 | Monitoring is active under normal load.                                                                                                                                              |
| Trigger                       | Performance tests run.                                                                                                                                                               |
| Expected behavior             | Use adaptive sampling, bounded queues, batched persistence and reduced UI refresh when hidden.                                                                                       |
| Expected outcome              | Utility remains unobtrusive.                                                                                                                                                         |
| Acceptance criteria           | Idle CPU median ≤1% of one core on reference hardware; resident memory target ≤100 MB; disk writes ≤10 MB/hour absent incidents; thresholds may be revised with documented evidence. |
| Confidence level              | High                                                                                                                                                                                 |
| Design freedom                | Architecture open; numeric targets are initial recommendations.                                                                                                                      |
| Open questions or assumptions | Reference hardware and acceptable variance.                                                                                                                                          |
| Human-review status           | Approved                                                                                                                                                                             |

## FR-031 — The system shall increase sampling resolution during suspected incidents and reduce it after recovery.

| **Field**                     | **Specification**                                                                                                    |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-031                                                                                                               |
| Requirement statement | The system shall increase sampling resolution during suspected incidents and reduce it after recovery.               |
| User or system objective      | Capture useful detail without constant high overhead.                                                                |
| Preconditions                 | Adaptive sampler is enabled.                                                                                         |
| Trigger                       | Pre-trigger condition or severe state appears.                                                                       |
| Expected behavior             | Transition to investigation cadence, then return after recovery hysteresis.                                          |
| Expected outcome              | High-resolution evidence exists where needed.                                                                        |
| Acceptance criteria           | Cadence transition does not lose samples; normal mode is no faster than necessary; user can inspect current cadence. |
| Confidence level              | High                                                                                                                 |
| Design freedom                | Suggested normal 2–5 seconds and incident 1 second; exact values tunable.                                            |
| Open questions or assumptions | Battery-mode cadence.                                                                                                |
| Human-review status           | Approved                                                                                                             |

## FR-032 — The system shall remain responsive under severe resource load and recover monitoring components automatically.

| **Field**                     | **Specification**                                                                                                                |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-032                                                                                                                           |
| Requirement statement | The system shall remain responsive under severe resource load and recover monitoring components automatically.                   |
| User or system objective      | Ensure the diagnostic tool works during the problem.                                                                             |
| Preconditions                 | Stress workload is active.                                                                                                       |
| Trigger                       | CPU, memory or I/O load becomes severe or a monitoring component becomes unavailable.                                                   |
| Expected behavior             | Prioritize minimal sampling/control path, bound work, reconnect safely and preserve last known state.                            |
| Expected outcome              | User can still open status and obtain evidence.                                                                                  |
| Acceptance criteria           | Under a controlled saturation test, status updates continue; no reinstall prompt is required; recovery occurs after load clears. |
| Confidence level              | High                                                                                                                             |
| Design freedom                | Process architecture open.                                                                                                       |
| Open questions or assumptions | Watchdog design and component recovery strategy.                                                                                               |
| Human-review status           | Approved                                                                                                                         |

## FR-033 — The system shall start at login only after explicit user action and shall expose a clear disable mechanism.

| **Field**                     | **Specification**                                                                                           |
|-------------------------------|-------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-033                                                                                                      |
| Requirement statement | The system shall start at login only after explicit user action and shall expose a clear disable mechanism. |
| User or system objective      | Respect user control over background operation.                                                             |
| Preconditions                 | User has installed the application.                                                                         |
| Trigger                       | User enables or disables login behavior.                                                                    |
| Expected behavior             | Register or unregister through supported system mechanisms and reflect actual authorization state.          |
| Expected outcome              | Background monitoring is transparent and reversible.                                                        |
| Acceptance criteria           | No silent registration; System Settings state matches app state; disabling stops future automatic launch.   |
| Confidence level              | High                                                                                                        |
| Design freedom                | Use current supported macOS service APIs.                                                                   |
| Open questions or assumptions | Behavior after application uninstall.                                                                       |
| Human-review status           | Approved                                                                                                    |

## FR-034 — The system shall support VoiceOver, full keyboard operation, increased contrast and reduced transparency preferences.

| **Field**                     | **Specification**                                                                                                        |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-034                                                                                                                   |
| Requirement statement | The system shall support VoiceOver, full keyboard operation, increased contrast and reduced transparency preferences.    |
| User or system objective      | Ensure essential diagnosis and remediation are accessible.                                                               |
| Preconditions                 | Accessibility features are enabled or user navigates without pointer.                                                    |
| Trigger                       | User interacts with any primary workflow.                                                                                |
| Expected behavior             | Expose semantic labels, focus order, status changes and non-color cues; respect system appearance settings.              |
| Expected outcome              | Users can complete incident inspection and safe action workflows.                                                        |
| Acceptance criteria           | Accessibility audit passes; all controls reachable; severity never conveyed by color alone; contrast remains sufficient. |
| Confidence level              | High                                                                                                                     |
| Design freedom                | Visual implementation open.                                                                                              |
| Open questions or assumptions | Formal accessibility conformance target.                                                                                 |
| Human-review status           | Approved                                                                                                                 |

## FR-035 — The system shall expose automation for selected safe operations using public macOS mechanisms.

| **Field**                     | **Specification**                                                                                         |
|-------------------------------|-----------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-035                                                                                                    |
| Requirement statement | The system shall expose automation for selected safe operations using public macOS mechanisms.            |
| User or system objective      | Integrate with user workflows without UI scripting.                                                       |
| Preconditions                 | Automation feature is enabled.                                                                            |
| Trigger                       | Shortcut, intent or supported script command is invoked.                                                  |
| Expected behavior             | Perform documented operations such as show status, switch profile, mute alerts or export latest incident. |
| Expected outcome              | Power users can automate predictable actions.                                                             |
| Acceptance criteria           | Commands are versioned, permission-aware and return structured success/failure.                           |
| Confidence level              | High                                                                                                      |
| Design freedom                | App Intents preferred; AppleScript optional.                                                              |
| Open questions or assumptions | Scope of process-control automation.                                                                      |
| Human-review status           | Approved                                                                                                  |

## FR-036 — The system shall not describe process-control actions as freeing memory unless measured memory is actually released.

| **Field**                     | **Specification**                                                                                                        |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-036                                                                                                                   |
| Requirement statement | The system shall not describe process-control actions as freeing memory unless measured memory is actually released.       |
| User or system objective      | Prevent misleading claims and diagnoses.                                                                                 |
| Preconditions                 | A report or user-facing explanation is generated.                                                                        |
| Trigger                       | Memory and control results are summarized.                                                                               |
| Expected behavior             | Use precise terms for CPU control, resident memory and memory pressure.                                                  |
| Expected outcome              | User receives accurate expectations.                                                                                     |
| Acceptance criteria           | Copy review finds no unsupported memory-reclamation claim; before/after measurements are distinguishable from causation. |
| Confidence level              | High                                                                                                                     |
| Design freedom                | Wording independently authored.                                                                                          |
| Open questions or assumptions | None.                                                                                                                    |
| Human-review status           | Approved                                                                                                                 |

## Deferred requirement FR-037 — The architecture may permit a future non–App Store capability tier.

| **Field**                     | **Specification**                                                                                               |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-037                                                                                                          |
| Requirement statement | The architecture may permit a future non–App Store capability tier without coupling it to the Mac App Store release.                                           |
| User or system objective      | Keep the Mac App Store product independent of any future privileged architecture.                                      |
| Preconditions                 | Build configuration is selected.                                                                                |
| Trigger                       | Application is packaged.                                                                                        |
| Expected behavior             | Compile or configure feature sets so monitoring works independently from restricted process-control components. |
| Expected outcome              | The Mac App Store edition remains complete and maintainable without any future advanced-control edition.                |
| Acceptance criteria           | The shipping build contains no privileged-helper code paths or unreachable privileged UI. Any future direct-distribution work requires a separate approved specification.       |
| Confidence level              | High                                                                                                            |
| Design freedom                | Deferred; no implementation decision is required for the initial release.                                                         |
| Open questions or assumptions | Commercial, licensing and App Review decision.                                                                  |
| Human-review status           | Escalated                                                                                                       |

## FR-038 — The system shall maintain traceable evidence classification for generated conclusions.

| **Field**                     | **Specification**                                                                                                     |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-038                                                                                                                |
| Requirement statement | The system shall maintain traceable evidence classification for generated conclusions.                                |
| User or system objective      | Make diagnoses auditable.                                                                                             |
| Preconditions                 | Incident analysis executes.                                                                                           |
| Trigger                       | A conclusion is produced.                                                                                             |
| Expected behavior             | Classify each conclusion as measured fact, derived calculation, heuristic hypothesis or user-provided classification. |
| Expected outcome              | User and support staff can judge confidence.                                                                          |
| Acceptance criteria           | Report exposes classification and confidence; heuristic changes are versioned.                                        |
| Confidence level              | High                                                                                                                  |
| Design freedom                | Internal schema open.                                                                                                 |
| Open questions or assumptions | Confidence calibration.                                                                                               |
| Human-review status           | Approved                                                                                                              |

## FR-039 — The system shall allow users to correct process-family attribution and incident interpretation.

| **Field**                     | **Specification**                                                                               |
|-------------------------------|-------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-039                                                                                          |
| Requirement statement | The system shall allow users to correct process-family attribution and incident interpretation. |
| User or system objective      | Recover from heuristic errors and improve future results locally.                               |
| Preconditions                 | A grouping or explanation is shown.                                                             |
| Trigger                       | User chooses correct, split, merge or mark expected.                                            |
| Expected behavior             | Apply correction to future local analysis and preserve original evidence.                       |
| Expected outcome              | System becomes more accurate without rewriting history.                                         |
| Acceptance criteria           | Corrections are reversible; raw PID samples remain intact; no correction uploads by default.    |
| Confidence level              | Medium-High                                                                                     |
| Design freedom                | Learning mechanism open.                                                                        |
| Open questions or assumptions | Persistence across app updates.                                                                 |
| Human-review status           | Approved                                                                                        |

## FR-040 — The system shall record application version, rules version and metric schema version with each incident.

| **Field**                     | **Specification**                                                                                        |
|-------------------------------|----------------------------------------------------------------------------------------------------------|
| Requirement ID                | FR-040                                                                                                   |
| Requirement statement | The system shall record application version, rules version and metric schema version with each incident. |
| User or system objective      | Support reproducibility and diagnostics across releases.                                                 |
| Preconditions                 | Incident is created.                                                                                     |
| Trigger                       | Incident record is persisted.                                                                            |
| Expected behavior             | Attach version metadata without collecting unrelated personal identifiers.                               |
| Expected outcome              | Reports can be interpreted after product updates.                                                        |
| Acceptance criteria           | Export includes versions; migrations preserve prior records or clearly mark unsupported fields.          |
| Confidence level              | High                                                                                                     |
| Design freedom                | Schema and migration approach open.                                                                      |
| Open questions or assumptions | Long-term backward compatibility.                                                                        |
| Human-review status           | Approved                                                                                                 |

## FR-041 — The system shall monitor storage capacity and available space for relevant mounted volumes.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-041 |
| Requirement statement | The system shall monitor total, available, and used storage capacity for the startup volume and other user-selected relevant volumes. |
| User or system objective      | Identify low-storage conditions that may contribute to degraded performance, failed writes, swap constraints, or update failures. |
| Preconditions                 | Volume metadata is available through public interfaces. |
| Trigger                       | Periodic capacity sample, volume mount/unmount event, or incident investigation. |
| Expected behavior             | Record capacity with clear units and timestamps; distinguish physical capacity, available capacity, and any separately reported reclaimable or purgeable estimate without treating it as guaranteed free space. |
| Expected outcome              | User can determine whether insufficient available storage is part of an incident. |
| Acceptance criteria           | Values agree with an authorized system reference within defined tolerance; unavailable or permission-restricted volumes are labeled; network and removable volumes can be excluded. |
| Confidence level              | High |
| Design freedom                | Volume list, summary card, timeline, or another independently designed representation. |
| Open questions or assumptions | APFS container/volume presentation, purgeable-space terminology, and default handling of external volumes. |
| Human-review status           | Approved |

## FR-042 — The system shall detect sustained low-storage conditions and rapid capacity loss.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-042 |
| Requirement statement | The system shall create or enrich an incident when available startup-volume storage remains below a configurable absolute or proportional threshold, or declines unusually quickly. |
| User or system objective      | Warn before storage exhaustion materially affects operation. |
| Preconditions                 | Storage-capacity history is available. |
| Trigger                       | Threshold and duration criteria are met. |
| Expected behavior             | Record the condition, its duration, recent rate of change, and associated disk-writing applications where defensible. |
| Expected outcome              | User understands whether the issue is persistent low capacity or rapid recent growth. |
| Acceptance criteria           | A transient measurement anomaly does not create an incident; thresholds support both percentage and absolute-space safeguards; predictions are labeled as estimates. |
| Confidence level              | High |
| Design freedom                | Fixed thresholds, adaptive thresholds, or a hybrid explainable model. |
| Open questions or assumptions | Default thresholds by disk size and whether exhaustion forecasting belongs in the first release. |
| Human-review status           | Approved |

## FR-043 — The system shall track application-family memory totals and memory growth.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-043 |
| Requirement statement | The system shall aggregate available memory measurements across related processes and track their change over time. |
| User or system objective      | Identify applications whose helpers collectively consume or steadily accumulate memory. |
| Preconditions                 | Process-family grouping and memory measurements are available. |
| Trigger                       | Sampling interval completes or an incident enters investigation mode. |
| Expected behavior             | Store **resident size** and track its change over time. Physical footprint is unavailable to a sandboxed build and shall not be presented. Because Activity Monitor's "Memory" column reports footprint, the interface shall state that the two measures legitimately differ. |
| Expected outcome              | User can see both current application-family memory and whether it is growing. |
| Acceptance criteria           | Aggregates equal the included process values within rounding tolerance; PID replacement does not erase application-family history; unavailable metric types are not fabricated; the difference from Activity Monitor is explained rather than left to surprise the user. |
| Confidence level              | High |
| Design freedom                | Visualization is open; the metric is settled. |
| Open questions or assumptions | Resolved by elimination: `proc_pid_rusage` is denied under App Sandbox, so `ri_phys_footprint` is unobtainable and `pti_resident_size` is the only per-process memory measure available. This closes the §10 question on the primary memory metric. |
| Human-review status           | Approved — amended in v1.2 from measurement |

## FR-044 — The system may identify suspected abnormal memory growth without claiming a confirmed leak.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-044 |
| Requirement statement | The system may flag sustained, unexplained memory growth as a suspected anomaly and shall distinguish the observation from a confirmed software defect. |
| User or system objective      | Surface recurring applications that gradually drive memory pressure. |
| Preconditions                 | Sufficient bounded history and stable application-family attribution exist. |
| Trigger                       | Explainable growth-rate and duration criteria are met. |
| Expected behavior             | Report measured growth, time range, pressure context, confidence, and alternative explanations such as intentional caching or workload expansion. |
| Expected outcome              | User receives a useful lead without an unsupported “memory leak” diagnosis. |
| Acceptance criteria           | The app never labels growth as a confirmed leak solely from resource measurements; short-lived allocation spikes do not trigger the condition. |
| Confidence level              | Medium-High |
| Design freedom                | Rules, robust trend analysis, or another explainable method. |
| Open questions or assumptions | Minimum observation period and baseline reset behavior. |
| Human-review status           | Review required |

## FR-045 — The system shall record observable process and application lifecycle events.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-045 |
| Requirement statement | The system shall record observable launches, exits, PID replacements, and repeated relaunches for applications and process families relevant to retained incidents. |
| User or system objective      | Preserve evidence when a contributor exits or restarts before the user investigates. |
| Preconditions                 | Public lifecycle notifications or polling evidence are available. |
| Trigger                       | Launch, termination, disappearance, or identity-change event. |
| Expected behavior             | Timestamp the event, associate it with the best-known application family, and retain uncertainty where attribution is incomplete. |
| Expected outcome              | Incident history explains when contributors appeared, disappeared, or repeatedly relaunched. |
| Acceptance criteria           | Relaunch loops in test fixtures are represented as related events rather than unrelated incidents; uncertain associations are labeled. |
| Confidence level              | High |
| Design freedom                | Event store and presentation are implementation choices. |
| Open questions or assumptions | Treatment of very short-lived helpers and orphaned processes. |
| Human-review status           | Approved |

## FR-046 — The system shall detect repeated application failure through observable lifecycle signals.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-046 |
| Requirement statement | The system shall incorporate repeated relaunch and other observable lifecycle failure signals into incident analysis. Application unresponsiveness is **not observable** to a sandboxed build and shall not be claimed. |
| User or system objective      | Explain application failures that occur without aggregate resource saturation. |
| Preconditions                 | Process lifecycle observation is active. |
| Trigger                       | Repeated relaunch pattern, unexpected exit, or user report attached to an incident. |
| Expected behavior             | Record the signal and correlate it with resource history and foreground state. Never describe an application as hung, frozen or unresponsive. |
| Expected outcome              | User can distinguish a repeatedly failing application from a system-wide CPU or memory incident. |
| Acceptance criteria           | No interface text claims an application was unresponsive or hung; a relaunch loop appears as related events rather than unrelated incidents; the UI separates system observations from user-reported symptoms. |
| Confidence level              | High for lifecycle signals; unresponsiveness measured as unavailable |
| Design freedom                | Presentation of relaunch patterns is open. |
| Open questions or assumptions | Measured: no public API reports hang state — `NSRunningApplication` describes a beachballing app identically to a healthy one, Accessibility is untrusted under the sandbox, and `/Library/Logs/DiagnosticReports` is unreadable (the home-relative path redirects into our own container). Crash-log access is therefore also out of scope. |
| Human-review status           | Approved — narrowed in v1.2 from measurement |

## FR-047 — The system shall record power-source and energy context for incidents.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-047 |
| Requirement statement | The system shall record whether a portable Mac is on battery or external power, relevant low-power state, and available battery context during an incident. |
| User or system objective      | Interpret performance and thermal behavior in the context of power mode and identify workloads associated with unusual battery drain. |
| Preconditions                 | Public power and battery information is available. |
| Trigger                       | Sampling interval, power-source transition, or incident lifecycle event. |
| Expected behavior             | Record supported context and correlate it with resource measurements; avoid presenting an unsupported per-app wattage estimate as fact. |
| Expected outcome              | User can understand whether the Mac was operating under a battery or power-saving condition. |
| Acceptance criteria           | Desktop Macs degrade gracefully; unavailable battery metrics are omitted; power transitions are timestamped. |
| Confidence level              | High |
| Design freedom                | Context may appear in incident metadata, timelines, or filters. |
| Open questions or assumptions | Whether a separate battery-drain incident type is included in the first release. |
| Human-review status           | Approved |

## Out-of-scope requirement FR-048 — Excessive wakeups and sleep-prevention monitoring.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-048 |
| Requirement statement | **Removed from this release.** Wakeup and sleep-prevention indicators require `proc_pid_rusage`, which is denied under App Sandbox, so the data does not exist for a Mac App Store build. |
| User or system objective      | Explain background heat, battery drain, and low-level CPU activity that may not appear as continuous saturation. |
| Preconditions                 | Not satisfiable under App Sandbox. |
| Trigger                       | Sampling interval or relevant system assertion change. |
| Expected behavior             | Display clearly defined measurements and label any attribution limitations. |
| Expected outcome              | User can identify applications that repeatedly wake the system or prevent expected idle behavior. |
| Acceptance criteria           | The feature is omitted, per the spec's own instruction to omit rather than approximate. No interface element implies wakeup data exists. |
| Confidence level              | Measured as unavailable |
| Design freedom                | Not applicable. Would require a distribution model outside this specification. |
| Open questions or assumptions | `ri_interrupt_wkups` and related counters live in `proc_pid_rusage`, denied sandboxed (measured 1/1058, ourselves). Revisit only if the distribution model changes. |
| Human-review status           | Approved — moved out of scope in v1.2 from measurement |

## FR-049 — The system shall record machine and operating-system context with each incident.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-049 |
| Requirement statement | The system shall retain the minimum machine and operating-system context needed to interpret incident measurements. |
| User or system objective      | Make reports reproducible and prevent misleading comparisons across different hardware or system states. |
| Preconditions                 | Context is available locally. |
| Trigger                       | Incident creation, material context change, or diagnostic export. |
| Expected behavior             | Record supported fields such as macOS version, hardware family, chip architecture, logical/physical core counts, installed memory, startup-volume capacity, power context, and application/schema versions. |
| Expected outcome              | Users and support recipients can interpret percentages, thresholds, and capability differences correctly. |
| Acceptance criteria           | Context is versioned, locally stored, previewable before export, and excludes serial numbers or persistent hardware identifiers unless separately justified and consented. |
| Confidence level              | High |
| Design freedom                | Exact field set may vary by platform version. |
| Open questions or assumptions | Whether connected-display count and recent OS-update state materially improve diagnosis. |
| Human-review status           | Approved |

## FR-050 — The system shall verify and report the outcome of user-directed remediation.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-050 |
| Requirement statement | After a user-directed action, the system shall observe relevant metrics for a bounded verification period and report whether the measured condition improved, persisted, worsened, or became unavailable. |
| User or system objective      | Close the loop between diagnosis and action rather than assuming success from an accepted command. |
| Preconditions                 | A supported action was requested and post-action monitoring remains available. |
| Trigger                       | Action completion or timeout. |
| Expected behavior             | Verify action result independently where possible, compare before/after measurements, and avoid claiming causation beyond the evidence. |
| Expected outcome              | User knows whether the intervention corresponded with measurable recovery. |
| Acceptance criteria           | A successful API return alone is not labeled as performance improvement; comparison windows and affected metrics are visible; inconclusive outcomes are allowed. |
| Confidence level              | High |
| Design freedom                | Verification may be shown inline, in the incident timeline, or in a follow-up notification. |
| Open questions or assumptions | Default verification duration by action and incident category. |
| Human-review status           | Approved |

## FR-051 — The system may monitor aggregate and per-application network activity where permitted.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-051 |
| Requirement statement | The system may record aggregate network throughput and, where supported, application-level network deltas as supporting incident evidence. |
| User or system objective      | Identify sync or transfer workloads that coincide with CPU, disk, memory, or responsiveness problems. |
| Preconditions                 | Public and distribution-compatible counters are available. |
| Trigger                       | Sampling interval or investigation mode. |
| Expected behavior             | Compute rates from counter deltas, distinguish local from unavailable attribution where possible, and avoid diagnosing network latency from throughput alone. |
| Expected outcome              | User can see whether sustained transfers coincided with a slowdown. |
| Acceptance criteria           | Cumulative counters are not mislabeled as current rates; feature can be disabled; unavailable per-process attribution is explicit. |
| Confidence level              | Medium |
| Design freedom                | Supporting context rather than a primary incident category in the initial release. |
| Open questions or assumptions | Sandbox feasibility and privacy implications. |
| Human-review status           | Review required |

## FR-052 — The system may monitor GPU activity where supported by public interfaces.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-052 |
| Requirement statement | The system may collect aggregate and defensible application-level GPU activity as supporting evidence on supported systems. |
| User or system objective      | Explain graphics, video, game, external-display, or compute workloads that coincide with heat or interface sluggishness. |
| Preconditions                 | Stable public metrics are available for the supported hardware and distribution channel. |
| Trigger                       | Sampling interval or incident investigation. |
| Expected behavior             | Record available utilization or activity measures with explicit units and limitations; do not invent discrete graphics-memory semantics on unified-memory systems. |
| Expected outcome              | User can see when graphics activity materially coincides with an incident. |
| Acceptance criteria           | Feature is capability-detected; unsupported systems omit it; measurements are validated against an authorized reference where possible. |
| Confidence level              | Medium |
| Design freedom                | May be deferred or limited to aggregate monitoring. |
| Open questions or assumptions | Public API stability and App Store compatibility. |
| Human-review status           | Review required |

## FR-053 — The system shall support explainable machine-specific baselines where practical.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-053 |
| Requirement statement | The system shall permit incident rules to consider recent normal behavior for the machine or application while preserving transparent absolute safeguards. |
| User or system objective      | Reduce false positives and identify behavior that is unusual for this user’s normal workload. |
| Preconditions                 | Sufficient local history exists and baseline learning is enabled. |
| Trigger                       | Rule evaluation or baseline update interval. |
| Expected behavior             | Maintain bounded local summaries, explain whether a finding crossed an absolute threshold, a learned baseline, or both, and allow reset or disable. |
| Expected outcome              | Alerts become more relevant without becoming opaque. |
| Acceptance criteria           | Cold-start behavior is defined; baseline changes are rate-limited; user can inspect and reset learned state; no cloud training is required. |
| Confidence level              | High |
| Design freedom                | Robust statistics, categorized workload baselines, or another explainable method. |
| Open questions or assumptions | Minimum learning period and treatment of seasonal workloads. |
| Human-review status           | Review required |

## FR-054 — The system shall support a guided investigation workflow.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-054 |
| Requirement statement | The system shall organize incident investigation around constrained resource, likely contributors, expectedness, safe actions, and measured outcome. |
| User or system objective      | Help nonexpert users move from symptom to evidence-based action without reading every metric. |
| Preconditions                 | An incident or manual investigation session exists. |
| Trigger                       | User opens an incident or chooses an investigation command. |
| Expected behavior             | Present a progressive workflow that answers what happened, why the app suspects particular contributors, what uncertainty remains, which actions are available, and what changed afterward. |
| Expected outcome              | User can complete a diagnosis without understanding PIDs, kernel terminology, or every raw counter. |
| Acceptance criteria           | Raw evidence remains accessible; no step is required to accept an unsupported conclusion; unavailable actions are not presented as working. |
| Confidence level              | High |
| Design freedom                | Wizard, incident narrative, drill-down panels, or another independently designed interaction. |
| Open questions or assumptions | Whether manual symptom input should be supported. |
| Human-review status           | Approved |

## FR-055 — The system shall account for all measured system activity, including the portion it cannot attribute.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-055 |
| Requirement statement | Wherever the system presents contributors to a resource condition, it shall also present the measured portion that cannot be attributed to any observable process, so that the parts always account for the whole. |
| User or system objective      | Prevent the user from concluding that the listed applications explain the machine's behaviour when a substantial share is unattributable. |
| Preconditions                 | Aggregate and per-process measurements are both available for the interval. |
| Trigger                       | Any presentation of contributors, live or within an incident. |
| Expected behavior             | Show the remainder as a first-class entry, classified as a calculated value rather than a measured one; name the protected processes observed running during the interval, which is a measured fact; explain that per-process usage for those processes is not reported to App Store applications. |
| Expected outcome              | Contributor lists visibly sum, and the user understands both what is unattributable and why. |
| Acceptance criteria           | Attributed plus unattributed equals the measured total within tolerance, including under load; the remainder is never negative; truncating a contributor list does not break the sum; copy claims no cause and implies no fault or waste. |
| Confidence level              | High |
| Design freedom                | Presentation is open, but the remainder may not be visually de-emphasised into insignificance. |
| Open questions or assumptions | Measured: processes owned by other users — `WindowServer`, `mds_stores`, `backupd`, `coreaudiod`, `launchd` — are denied identically whether or not the app is sandboxed, since the binding limit is uid rather than the sandbox. Roughly 40 percentage points of busy CPU is typically unattributable. Users may compare against Activity Monitor, which sees these processes through a privileged helper. |
| Human-review status           | Approved — added in v1.2 |

# 6. Conceptual data requirements

| **Entity**            | **Minimum conceptual fields**                                                                                                               | **Notes**                                                               |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Sample                | timestamp; cadence; aggregate CPU; memory pressure; swap/paging deltas; disk deltas; thermal state; data-availability flags                 | Use monotonic source counters where applicable.                         |
| Process sample        | PID; process start identity; application-family ID; CPU; memory footprint; I/O deltas; foreground/hidden state; eligibility and confidence  | PID alone is insufficient because it can be reused.                     |
| Application family    | stable local identifier; bundle/signing/executable evidence; display name; member processes; attribution confidence; user corrections       | Keyed on the outermost application bundle in the executable path. The signed identifier identifies a process but does not group it, because helpers report their own identifier rather than the parent's. |
| Standalone process    | process identity; display name; executable path; signing evidence where available                                                          | **First-class, not a family of one.** Only about 15% of processes belong to any application bundle; daemons and command-line tools are the majority and must be modelled directly. |
| Unattributable activity | interval; measured total; attributed total; calculated remainder; protected processes observed running                                    | Required by FR-055. The remainder is a calculated value and must never be stored or shown as a measurement. |
| Incident              | ID; start/trigger/recovery/end; active conditions; severity; evidence window; contributors; conclusions; confidence; versions; user actions | Immutable raw evidence plus append-only interpretations preferred.      |
| Policy                | scope; target identity; conditions; thresholds; actions; safety classification; enabled state; provenance; last modified                    | Policies must be reversible and auditable.                              |
| Profile               | ID; name; policy set; activation precedence; manual override state                                                                          | Names and organization are user-defined.                                |
| Privacy settings      | retention duration; export redaction; telemetry consent; crash-reporting consent                                                            | Default local and minimal.                                              |
| Safety classification | process identity rule; permitted actions; rationale category; update version                                                                | Protected classifications cannot be weakened by ordinary user settings. |

# 7. Mac App Store capability matrix

| **Capability** | **Initial Mac App Store status** | **Implementation direction** |
|---|---|---|
| Aggregate CPU, memory pressure, swap/paging, disk I/O, storage capacity, and thermal state | In scope, subject to public API behavior | Prototype and validate on macOS 26 and 27. |
| Per-process CPU and resident memory | In scope, measured working | Available for processes owned by the user (~68% of the table). Enumerate with `sysctl KERN_PROC_ALL`; `proc_listpids` is denied. |
| Per-process I/O, memory footprint, wakeups | **Not available** | `proc_pid_rusage` is denied sandboxed. Excluded from FR-009 and FR-048; FR-043 uses resident size. |
| Per-application audio activity | In scope, measured working | `kAudioHardwarePropertyProcessObjectList`, no microphone permission required. |
| Application hang or unresponsive state | **Not available** | No public API. FR-046 delivers repeated-relaunch detection only. |
| Window titles, per-tab or per-document context | **Not available** | Requires Screen Recording permission; disproportionate for this product and excluded. |
| Application-family grouping and incident attribution | In scope | Use public metadata and confidence-scored heuristics. |
| Notifications, retained incident history, export, and user policies | In scope | Keep data local by default and obtain normal system permissions. |
| Activate or reveal an application; open system tools; copy diagnostics | In scope where supported | Verify action success and remain non-destructive. |
| Automatic suspension, automatic quitting, force quitting, CPU limiting, reprioritization, or arbitrary process control | **Not in scope** | Deferred; do not expose UI or dormant code paths in the initial release. |
| Privileged helper, launch daemon, or elevated component | **Paused / not in scope** | No implementation work for the initial release. |
| Login-at-launch behavior | In scope with explicit user consent | Use current public macOS service APIs and provide a clear disable path. |

# 8. Independent design recommendations

- DR-01: Treat incident diagnosis as the primary product, with safe user guidance and non-destructive actions as remediation. This provides value even in a
  restricted sandboxed edition.

- DR-02: Begin with deterministic, explainable rules and confidence
  scoring before introducing opaque anomaly models.

- DR-03: Separate sampling from display refresh. The system may collect
  at one cadence and redraw only when useful.

- DR-04: Use two-stage sampling: low-overhead baseline mode and
  higher-resolution investigation mode.

- DR-05: Preserve raw measurements separately from generated
  explanations so future analysis can be rerun.

- DR-06: Do not implement automatic suspension, automatic quitting, force quitting, or background process control in the initial release. Prefer explanation, user guidance, reveal/activate actions, and links into system tools.

- DR-07: Personalization should affect alerts, grouping, thresholds, and explanatory guidance—not automatic process control.

- DR-08: Use official memory-pressure and thermal-state signals instead
  of simplistic “percent RAM used” or undocumented temperature
  dependencies.

- DR-09: Provide a local, redacted support export and avoid requiring an
  account or cloud service for core functionality.

- DR-10: Build the core in Swift with concurrency isolation around
  samplers and persistence; use AppKit or public lower-level APIs when
  SwiftUI alone is insufficient.

# 9. Release phasing

| **Phase**                      | **Included scope**                                                                                                        | **Exit criteria**                                                                                          |
|--------------------------------|---------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| Phase 1 — Core monitor         | Status surface, process inventory, CPU and application-family resident-memory display, grouping, standalone processes, unattributable activity (FR-055), lifecycle events, bounded history, search, machine context, and overhead instrumentation. | Measurements validated; idle overhead budget met; accessible UI; contributors survive PID changes. |
| Phase 2 — Incident diagnosis   | Memory pressure, swap/paging, aggregate disk I/O, storage capacity, low-storage detection, thermal and power context, relaunch-failure signals, audio-activity deferral, incident lifecycle, incident-data retention, notifications, guided investigation, and reports. | Controlled slowdowns and low-storage scenarios produce coherent incidents with acceptable false-positive rates. |
| Phase 3 — Safe response and guidance | Activate, reveal, open system tools, ignore/expected policies, mute, export, safe automation, and post-action verification. | Actions are non-destructive, verified, permission-aware, and followed by measurable outcome reporting. |
| Phase 4 — Advanced context | Explainable baselines, optional network and GPU context, profiles, richer comparisons, and contextual guidance compatible with the Mac App Store. | API, privacy, accessibility, performance, and App Store feasibility are validated on macOS 26 and 27. |
| Deferred — Non–App Store controls | Privileged helpers, CPU ceilings, suspension, reprioritization, efficient-core preference, automatic quitting, and other process-control capabilities. | No initial implementation. Requires a separate product decision and specification. |

# 10. Open product and engineering decisions

- The initial commercial target is the Mac App Store. A direct-download edition is deferred.

- Privileged helpers and elevated components are paused and outside the initial release.

- Automatic suspension and automatic quitting are explicitly excluded from the initial release.

- macOS 26 and macOS 27 are supported; Apple Silicon is the initial hardware target.

- Whether raw hardware temperature is necessary beyond public thermal
  state.

- Whether on-device language generation is used for summaries or
  deterministic templates are sufficient.

- Whether incident records persist across restarts and the default
  retention duration.

- Whether telemetry or crash reporting is offered, and the exact opt-in
  and redaction model.

- Whether storage exhaustion forecasting and folder-level growth attribution are included, and what permissions they require.


- Whether GPU, per-process network, raw temperature, or fan metrics are sufficiently public, stable, low-overhead, and App Store-compatible. (Wakeups and sleep-prevention are settled: unavailable — see FR-048.)

- Whether baseline learning is enabled by default, its learning period, and how users inspect or reset it.

- ~~Whether crash logs, hang reports, or other diagnostic artifacts are in scope.~~ **Settled in v1.2:** unreadable from the sandbox, so out of scope.

Answered in v1.2 by measurement, recorded in `probe/FINDINGS.md`:

- Primary memory metric: resident size, by elimination.
- Per-process disk I/O, footprint and wakeups: unavailable.
- Per-application audio: available, without a microphone permission.
- Application unresponsiveness: unavailable; repeated relaunch is available.
- Window titles and per-tab context: unavailable without Screen Recording.

Still open and now the largest single risk: whether App Review accepts
`sysctl KERN_PROC_ALL` for process enumeration, given that `proc_listpids` is
explicitly denied and Apple has stated no entitlement lifts it. The product
requests no entitlements beyond App Sandbox, but no Apple statement blesses the
alternative. This cannot be settled by testing.

# 11. Implementation authority

- This document is the authoritative source for product scope and implementation behavior.
- Product, design, engineering, security, privacy, QA, and release decisions shall be evaluated against the requirements and acceptance criteria in this document.
- Where a requirement is technically infeasible under a target macOS version or distribution model, the implementation team shall document the limitation, propose a compliant alternative, and obtain a product decision before changing scope.
- Features not defined here require an explicit requirements update before implementation.
- UI screens and interaction concepts will be produced separately using Claude Design. Those artifacts are design inputs, while this document remains authoritative for behavior, scope, safety, privacy, accessibility, and acceptance criteria.
- Internal architecture and algorithms remain implementation choices unless constrained by a stated requirement or acceptance criterion.
