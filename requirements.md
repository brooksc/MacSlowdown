# MacSlowdown — Product Definition and Functional Requirements

**Document status:** Greenfield product specification  
**Version:** 1.6  
**Last updated:** September 9, 2026

> **Revision note (1.6):** the three remaining challenges are closed. **C-06 applied**: FR-051 is narrowed to aggregate-only, because a specification that commits the product to something measurement has shown impossible is a defect rather than a pending decision. **C-05 applied**: FR-053, FR-025 and FR-026 are deferred, each with the reason recorded at the requirement — in two of the three cases the design reached for the same feature independently and then argued itself out of it. **C-04 closed as already answered**: §1.2's v1.5 rewrite says success includes understanding the observed conditions *and their limits*, which is what C-04 asked for. FR-064 gains amendment 1: a user's report is kept until they delete it, because a report is scarce where an incident is plentiful.

> **Revision note (1.5):** amended after two independent product reviews. The governing change is that **a measured resource condition is not a slowdown** — §1.2's success definition is rewritten around supporting a decision rather than around reading an incident, and FR-063 to FR-065 are added: the condition/experience distinction, user-reported slowdowns, and the rule that measurement, attribution and impact confidence may not collapse into one claim. FR-011 and FR-014 are amended so sustained CPU load is recorded but does not interrupt by default. FR-016's per-application suppression is narrowed to a condition type. No requirement was removed.

> **Revision note (1.4):** amended after the first three challenges were answered and
> two of them built. FR-006's run-queue amendment carries the measurement that refutes
> its proposed numbers and stays *proposed*; §10.1 records which challenges are answered
> and which three still are not; §10.0's D-01 is now tracked as a spike. No requirement
> was added or removed. The live-surface requirements FR-057 to FR-062, added in 1.3,
> are the ones now doing most of the work.

> **Revision note (1.3):** amended after two weeks of running the built app on a
> real machine, which contradicted several things this document asserted. Changes:
> FR-046's two drafted amendments approved and two more added, with the
> false-positive evidence recorded; FR-006 and FR-011 now say what *sustained*
> means, because "unbreached at every sample" turned out to be a definition no real
> workload satisfies; FR-031's cadence amendment carries its measured cost; FR-030's
> reference figure no longer names a quantity its own note forbids; §1.1, §2 and §9
> no longer promise capabilities measured as unavailable; FR-051 carries the
> measurement that contradicts it. Open challenges to the product's shape are listed
> in §10 rather than resolved unilaterally.

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
- Explain whether CPU, memory pressure, swap activity, disk I/O, low storage capacity, thermal pressure, repeated application relaunch, background activity, or another observable condition contributed. (**Application hangs are not observable** to a sandboxed build — measured, see FR-046 — and were removed from this list in v1.3. The product must not imply it can detect them.)
- Identify likely application-level contributors while preserving access to individual process details.
- Retain enough pre-trigger and recovery history to investigate incidents after they end.
- Reduce false alarms through duration thresholds, hysteresis, user policies, and machine-specific baselines where practical.
- Give the user safe, verifiable remediation choices rather than promising generic optimization or automatic repair.
- Keep sensitive process, path, and incident data local by default.

## 1.2 Product success definition

**Revised in v1.5.** MacSlowdown succeeds when a user investigating a slowdown can quickly understand the observed conditions and their limits, choose an appropriate next step, and tell whether their experience improved — without unwanted interruptions during work they expected to be heavy.

It does not need to guarantee that every slowdown can be diagnosed or fixed. Unavailable measurements, ambiguous attribution and unsupported actions must be stated explicitly.

> **Why this changed.** The previous definition was *"a user can open an incident and understand what happened."* Two independent reviews found the same fault from different directions: it names an intermediate usability result rather than an outcome. A user who reads an incident and understands it perfectly, and then does nothing differently, has not been helped. It also placed success entirely in the retrospective surface, when the first question a person asks on opening the app is usually whether the problem is still happening.
>
> The new definition is deliberately harder to satisfy. It requires a decision to have been supported, and it makes unwanted interruption a *failure of the product*, not a settings problem for the user.

# 2. Purpose and product boundary

MacSlowdown is a native macOS utility that continuously observes system
resource conditions, detects sustained performance degradation,
identifies likely contributing applications or processes, preserves
recent evidence, explains the incident in clear, measured terms, and offers safe
user-directed remediation. The initial release is a Mac App Store application and shall rely only on capabilities compatible with App Sandbox and current App Review requirements. Privileged-helper and advanced process-control capabilities are deferred and are not part of the initial implementation.

- Primary value: reduce the time between “the Mac feels slow” and a
  defensible explanation of which resource is constrained and which
  application family is contributing.

- Primary resources and contexts: CPU, application and system memory, memory pressure, swap/paging, disk I/O, storage capacity, thermal state, power context, and process lifecycle. (**"Responsiveness signals" was removed in v1.3**: no public API exposes them to a sandboxed build, and listing them here implied a capability the product does not have.)

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
| Open questions or assumptions | **Settled 2026-08-09:** the metric sample series stays in memory (15 minutes, not restored across a restart — a restored series would let a threshold change date an incident to before the app was running). Incident records persist; see FR-029. |
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
| Acceptance criteria           | No alert for a single transient spike shorter than the configured duration; contributor shares sum consistently within tolerance; **a condition that dips briefly below its threshold and returns is one episode, not a restart of the clock** (see the definition below). |
| Confidence level              | High                                                                                                                              |
| Design freedom                | Detection model may be rules, statistics or another explainable approach.                                                         |
| Open questions or assumptions | Default thresholds by core count and power mode. **Whether the default threshold is set where users actually perceive slowness — see the challenge in §10.** |
| Human-review status           | Approved; the definition of *sustained* clarified in v1.3 from measurement.                                                       |

**Amendment — run-queue pressure as a second condition (proposed 2026-08-31, C-02).**

The threshold in this requirement is a share of *busy time*, and busy time is a poor
predictor of the thing the product exists to explain. Measured on the product owner's
Mac on 2026-08-31, 40 samples at one second:

| | |
|---|---|
| Load average, peak | **95.8** on 8 cores — about twelve runnable threads per core |
| CPU busy at that moment | 93% |
| Load average, 30 s later | 45.9 — still nearly six runnable threads per core |
| CPU busy at that moment | **44–51%** |
| Correlation across the run | **0.68** |

A machine with six threads queued per core is unusable, and at 44% busy this
requirement sees nothing whatever: the CPU condition needs 85% sustained for three
minutes. The two signals are related but not the same, and the one currently used is
the weaker of the two for this purpose. Waiting on the run queue is what "slow" feels
like; busy time is what "working" looks like.

**Proposed:** a second, independent condition — *sustained run-queue pressure* —
breaching when runnable threads per logical core stay above a configurable ratio
(initial proposal **2.0**) for a configurable duration (initial proposal **60 s**).
`vm.loadavg` is a public sysctl, costs one call, and is available sandboxed. The CPU
saturation condition and its 85% threshold are unchanged; this adds a case rather than
loosening an existing one.

**Presentation constraint, which is why this needs a spec amendment and not just code.**
A load average must never be shown as though it were a percentage — "18.45" invites
exactly the wrong reading, and this project rejected the figure as a *display* for that
reason. It is expressed to the user as **runnable threads per core**, or as a described
state ("more work queued than this Mac can run at once"), never as a bare number beside
percentages. Under FR-038 it is a measured fact; any statement about what it *causes*
remains a heuristic.

**Known risk:** on macOS the load average counts threads blocked in uninterruptible I/O
as well as runnable ones, so a machine waiting on a slow disk can read high while the
CPU is idle. That is arguably still a slowdown worth reporting, but it means the
condition must not be described as a CPU condition. Validation against real workloads is
required before the ratio and duration are fixed.

> **Measured 2026-09-03 (TASK-103): the proposed numbers are refuted, and this
> amendment remains *proposed*.** On the target machine an ordinary capped, nice'd
> build sits at a **median of 2.87 runnable threads per core, peaking at 8.68**, and
> breaches the proposed 2.0 ratio on **59.2% of samples** — a condition that would
> fire through most of every compile, which is FR-046's false-positive history about
> to repeat. Two further findings change the shape of the requirement rather than
> just its numbers. First, the "known risk" above is not a risk but the normal case:
> **141 of 142** high-queue build samples showed pagein above 1 MB/s, so under load
> the figure is dominated by I/O wait. Second, `getloadavg` is a **one-minute
> exponentially weighted average** — it held 7.43 for 16 s at build start while CPU
> busy swung 62–78% second to second — so it already encodes a minute of history, and
> a 60 s duration on top counts that history twice. **This falsifies the amendment's
> stated premise** that run-queue pressure is felt immediately in a way CPU saturation
> is not: that is true of queue *depth*, and `getloadavg` does not measure depth at an
> instant.
>
> What survives: the founding observation is unchallenged — twelve per core was
> unusable while CPU read 44–51% and this requirement saw nothing — and the
> correlation between the two signals *fell* from 0.68 to 0.34 under load, which
> strengthens the claim that they are different signals. The boundary is real and
> simply far higher than proposed. Before any number is fixed, a prior question must
> be answered: **is an unsmoothed queue-depth reading available to a sandboxed build
> at all?** If not, this condition should be described differently rather than given a
> threshold that implies a precision the input does not have. Evidence:
> `probe/FINDINGS.md`, probe at `probe/Sources/loadavg-probe.swift`.

**What "sustained" means (clarified 2026-08-31).** Two readings are possible and only
one of them describes a real machine.

The implementation originally read it as *unbreached at no sample*: any single reading
below the threshold discarded the accumulated duration. Measured against a real workload,
that is a definition nothing satisfies. A machine sitting steadily at 86% of capacity
crosses an 85% line several times a minute, so the duration clock restarted continuously
and no incident opened — observed 2026-08-31 as a status surface reading "Your Mac is
heavily loaded" above "No slowdowns since 11:22 AM", nearly an hour later.

The reading this document intends is the ordinary one: **an interval during which the
condition held, allowing for brief dips.** A gap longer than a configurable tolerance
(default 15 s) ends the interval; a shorter one does not. The condition must still be
breaching at the moment the duration is judged, so an intermittent spike accumulates
nothing.

The same distinction governs the **status surface** (FR-001): a word describing the
machine's condition is a claim about an interval, and reading it off a single sample made
it change as often as the machine breathed. It is judged over a trailing window, with a
deadband so it does not oscillate at a boundary.

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
| Acceptance criteria           | Repeated samples do not create duplicate incidents; incident closes only after recovery hysteresis; **the opening clock tolerates brief dips as FR-006 defines, so hysteresis applies to both ends of an episode rather than only to its close**.                        |
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
| Open questions or assumptions | **Settled 2026-08-09:** retained incidents persist across restarts and are kept 30 days by default; see FR-029. |
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

**Amendment 1 — sustained CPU load is recorded but does not interrupt by default (2026-09-06).**

Under FR-063 a resource condition is not a slowdown, and CPU load is the condition where the two diverge most: on a developer's machine the most common cause of sustained high CPU is work the user started deliberately. Interrupting for it tells the user we have misread their work, and every such interruption spends trust that is never repaid.

So the default interruption policy is:

| Condition | Default |
|---|---|
| Sustained CPU load | **Recorded, not announced.** Visible on the live surfaces and in history; the user may opt in to announcements. |
| Sustained memory pressure | **Announced**, because a plausible decision attaches to it — something can be closed, and the machine's behaviour will change. |
| Low storage | **Announced.** Actionable and unambiguous. |
| Thermal pressure | **Recorded, not announced** by default; the machine's own behaviour already signals it. |

The test for whether a condition may interrupt is not its severity but whether **a decision plausibly attaches to it**. A condition the user can do nothing about, or that they caused on purpose, is recorded.

**This is a bet with a known risk.** A product that rarely interrupts may rarely be opened, and "opt-in" and "off" are close to the same thing in practice. FR-064's user-reported slowdowns are what will settle whether the default is right; until then it is deliberately conservative, because a noisy product is uninstalled and a quiet one is merely underused.

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

**Amendment 1 — suppression is scoped to a condition, not to an application (2026-09-06).**

"This application's heavy load is expected" is not the same claim as "this application can never cause a problem", and the product must not treat the first as the second. An application marked expected for CPU load must still be able to appear in a memory-pressure finding.

Two further constraints, both from the same review:

- **Suppression keyed on the leading measurable contributor is unstable.** The ranking it depends on is incomplete by construction (FR-055), so a small change in ranking could decide whether otherwise identical conditions announce. A rule must therefore name what it suppresses — a condition type for an application — and its scope must be visible and reversible wherever it was set.
- **A session-scoped option is required alongside the permanent one.** "Quiet for this work session" covers the common case, which is a person doing something heavy now rather than always.

**Acceptance criteria (added).** A rule states the condition it suppresses; a rule for one condition never suppresses another; every rule is visible and reversible from a single place; a session-scoped rule expires without the user having to remember it.

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
| Deferral status | **Deferred 2026-09-09 (challenge C-05).** Returns only on user evidence. The build never had profiles, nobody has asked for them, and the design's argument against them is independent and good: a profile puts a mode switch in the same list as navigation, so a mis-click silently changes what counts as a condition — a setting disguised as a place. Per-application rules (FR-016) already cover the case profiles were invented for, and they say what they do. |
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
| Deferral status | **Deferred 2026-09-09 (challenge C-05).** Returns with FR-025, and not before. Contextual activation is a refinement of a feature that is itself unevidenced. |
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

### FR-029 — settled persistence and retention decision (product owner, 2026-08-09)

This is the product decision the specification previously left open in §10, and it
governs FR-005's retained series, FR-011/FR-012's retained incidents and this
requirement's retention controls.

- **Incident history persists across restarts, on by default.** It is written to
  `incidents.json` in the application's own Application Support directory, which
  under the App Sandbox is inside the app's container.
- **The default retention period is 30 days.** The period is user-adjustable
  (7 / 30 / 90 days) in the Privacy settings.
- **Retention is bounded on two axes and the interface shall state both.** The
  chosen period, and a count bound on retained incidents; whichever is reached
  first is what is kept. A period alone does not satisfy FR-005's "bounded".
- **Retention shall be enforced whenever the stored set changes and on a schedule
  that does not depend on the user opening any screen.** A configured period that
  nothing applies does not satisfy this requirement.
- **The stored form shall carry a schema version**, so a later format change can
  migrate rather than discard a user's recorded history.
- **Recorded attribution, and the confidence it carried, shall survive persistence
  unchanged and shall never be recomputed from live state on load.** Live state
  describes the machine now, not the machine that was in trouble (FR-013, FR-038).
- **No user-facing copy shall claim the store is encrypted.** FileVault is the
  user's setting and `NSFileProtection` on macOS is not the guarantee the word
  implies. The approved statement is that data is held *in MacSlowdown's own
  container, which no other app can read*.
- **The rolling metric sample series (FR-005) is not persisted.** It is a
  15-minute window whose only consumer re-decides a breach start against readings
  that were actually taken; restoring a series from a previous run could date an
  incident to a period during which the app was not running.

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
| Acceptance criteria           | **Deferred — measured and reported, not gated.** The overhead harness continues to run and its figures are recorded, but no numeric threshold blocks work on functionality or UX. Reference figures, to be revisited before release: idle CPU median ≤1% of one core, measured over ≥300 s; **`phys_footprint` median ≤300 MB over ≥300 s** — not resident size, for the reason in the deferral note below; disk writes ≤10 MB/hour absent incidents. The app itself no longer states or judges any of these on screen (product owner, 2026-08-31); it reports its own cost and leaves the judgement to whoever is optimising. |
| Confidence level              | High                                                                                                                                                                                 |
| Design freedom                | Architecture open; numeric targets are initial recommendations.                                                                                                                      |
| Open questions or assumptions | Reference hardware and acceptable variance. Which memory quantity the budget names — see the deferral note below.                                                                     |
| Human-review status           | Approved; acceptance criteria deferred by the product owner 2026-08-08.                                                                                                              |

**Deferral note (2026-08-08).** The numeric budget is deferred by the product owner so
that functionality and UX are not blocked on optimisation. Overhead is still measured and
still reported; it simply does not gate delivery. Optimise later, against evidence.

The objective — *avoid becoming part of the slowdown* — is **not** deferred. It remains
the reason this requirement exists, and it still governs design choices such as adaptive
sampling (FR-031) and separating sampling cadence from UI refresh (DR-03).

Two measurement findings must survive this deferral, because they change what any future
threshold can even mean:

- **"Resident memory" is not a testable quantity for this app.** Measured over 1191 s, our
  resident size ranged 809–3323 MB while `phys_footprint` ranged 218–397 MB, with no
  change in behaviour. Roughly 3 GB of the peak was clean, shared, file-backed mappings of
  the icon services cache, which the kernel evicts for free. A budget naming resident size
  can be passed or failed by when you happen to look. Any revived budget should name
  **`phys_footprint`**, as a **median over at least 300 s**.
- **The headless harness is not representative.** It runs no SwiftUI. On the same day it
  reported 0.830% CPU and 20.7 MB while the running Debug app showed a 292 MB footprint
  median. A figure this requirement is judged on has to come from the app, not the harness.

Recorded so a later reader does not mistake deferral for absence of a problem: at the time
of deferral the app's footprint median was 292 MB, and a single avoidable allocation
pattern accounted for most of it. See TASK-55.1 and TASK-55.2.

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
| Design freedom                | Normal 1 second and investigation 0.5 seconds (amended 2026-08-25); exact values tunable.                            |
| Amendment — normal cadence is 1 second (product owner, 2026-08-25) | Normal cadence moves from 2–5 s to **1 s**, and investigation cadence from 1 s to **0.5 s**. Reason: the product's purpose is to explain sustained behaviour, not to display instants, and every per-application figure it shows was a single sample — visibly twitching, and impossible to average because no per-application history was retained. A trailing one-minute mean and a per-application curve both require per-second retention, which requires per-second sampling. Investigation cadence tightens in step so that FR-031's own requirement — resolution *increases* during a suspected incident — remains implemented rather than collapsing into a single rate. Note the escalation is now 2× rather than up to 5×, which is gentler on a machine already in trouble (FR-032). "No faster than necessary" is unchanged as a criterion and is now met at a different value: 1 s is what the retained history requires, and nothing faster is taken outside an investigation. |
| Measured cost of the amendment | **Measured, not estimated** — `probe/overhead/run.sh 300` on an M2 MacBook Air, 2026-08-25, 283 sweeps over 300.9 s at the amended cadence: **1.760% of one core steady state** against the ≤1% reference, sweep median 6.22 ms, resident 23.3 MB, disk 0.00 MB/hour. The comparable figure before the amendment was 0.830%, so the cost scaled with the cadence almost exactly — twice the samples, 2.1× the CPU. The pre-amendment estimate of 0.6% was wrong by ~3× because it costed only the sweep and not the rest of the sampling loop; the sweep alone accounts for ~0.58% of the measured 1.76%. Note the harness is headless and under-reads the real app, so the shipping figure is higher again. In machine terms this is ~0.22% of an 8-core Mac. **Over the reference and knowingly accepted**: the numeric budget is deferred and does not gate (product owner, 2026-08-08), and the objective it serves — that the tool not become part of the slowdown — is still met at a fifth of one core out of eight. Revisit before release alongside the deferred budget, and note that decoupling grouping cadence from metrics cadence is the obvious lever if it needs one. |
| Open questions or assumptions | Battery-mode cadence — still open, and now more consequential: 1 s sustained on battery has not been assessed. |
| Human-review status           | Approved — normal cadence amended in v1.3 (2026-08-25) |

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
| Amendment 1 — termination status (**approved 2026-08-23**) | Termination status is not observable. `kqueue`'s `EVFILT_PROC` accepts `NOTE_EXITSTATUS` only for a process the app itself forked — measured, 3 of 527 own-uid processes in a sandboxed build, against 520 of 526 unsandboxed — so a Mac App Store build cannot distinguish a crash from an ordinary exit for any process it did not create. The app must therefore never describe an observed termination as a crash, a failure, or "quit unexpectedly". The only supported statement about a `(pid, start time)` that is no longer present is that it is no longer running, and the only supported pattern claim is repeated relaunch over a bounded window, labelled a heuristic hypothesis under FR-038. |
| Amendment 2 — subject restriction (**approved 2026-08-23**) | A repeated-relaunch finding is raised only where the exiting process resolves to an application bundle. Repeated exits of daemons, launch agents and command-line tools are recorded as lifecycle events and shown in the process inspector, but do not open an incident. Rationale: measured over one 901 s window on a developer Mac, 28 non-application commands reached the exit threshold and one application did; the unrestricted predicate breaches continuously on any machine that compiles. The known cost is that a genuinely crash-looping daemon no longer opens an incident. |
| Amendment 3 — the subject must be a bundle's main executable (2026-08-23) | "Inside a `.app`" is not the same as "is an application". Xcode ships its entire toolchain at `Xcode.app/Contents/Developer/usr/bin/`, so `clang`, `git`, `ld` and `swift-frontend` all satisfied amendment 2 — one build recorded 419 exits of `swift-frontend` and opened an incident for `git`. Chromium-derived applications then produced the same failure one level down: `LM Studio Helper.app` inside `LM Studio.app` recycles renderers as routine work. The subject must therefore be the **outermost** bundle's main executable. Helper exits remain visible as lifecycle events; only the incident is withheld. |
| Amendment 4 — the subject must have been a session (2026-08-31) | Even the outermost-main-executable rule admits a whole class of false positive, because some Apple bundles exist to run many short-lived executables: `XProtect.app/Contents/MacOS/` holds about 34 remediators that macOS runs briefly as a scheduled scan, and `p_comm`'s 16 bytes truncate every one to the same `XProtectRemediat` fragment, so 34 programs running once each were counted as one thing quitting 34 times. No path rule can separate that from a real application, because on disk they *are* applications. An exit therefore counts only where the process had been running for a minimum period (default 60 s), measured from `(pid, start time)`; an exit that cannot be dated does not count. This is FR-006's sustained-not-transient rule applied to the subject rather than to the count. |
| Measured false-positive record (2026-08-31) | Nine days of continuous running on a developer Mac produced **ten incidents, all of them repeated-quit, and all of them false**. No CPU, memory, thermal or storage incident occurred in that period. Each amendment above closed the cause of the previous set and a new one appeared. This history is recorded because it bears directly on whether the requirement should ship at all — see the challenge raised in §10. |
| Amendment 5 — demoted to a record (**approved 2026-08-31, C-01**) | **Repeated relaunch no longer opens an incident and no longer notifies.** It is recorded as a lifecycle finding, shown in the process inspector and available as incident *evidence* where an incident exists for another reason. Rationale: nine days of continuous running produced ten repeated-quit incidents and no others, all ten false, across four successive narrowings. What survives the narrowings is "an application you were using disappeared and came back three times in fifteen minutes" — which the user generally watched happen — while amendment 1 forbids saying why it went and `p_comm`'s 16 bytes leave the subject ambiguous. The value never justified the false-positive cost, and there has yet to be a true positive. The detection code is retained, not deleted: if a second machine produces a genuine crash-loop this decision is cheap to revisit. |
| Human-review status           | Approved — narrowed in v1.2, amendments 1–2 approved 2026-08-23, amendments 3–5 approved 2026-08-31. Amendments 3 and 4 remain in force because they govern what is *recorded*, not only what opened an incident. |

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

## FR-051 — The system may monitor aggregate network activity where permitted.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-051 |
| Requirement statement | The system may record **aggregate, machine-wide** network throughput as supporting incident evidence. Per-application network attribution is out of scope: it is measured unavailable, not deferred. |
| User or system objective      | Show whether sustained transfer coincided with a condition, without implying we can say which application was transferring. |
| Preconditions                 | Public and distribution-compatible counters are available. |
| Trigger                       | Sampling interval or investigation mode. |
| Expected behavior             | Compute rates from counter deltas. Report loopback separately from external interfaces. State that per-application attribution is unavailable wherever throughput is shown beside per-application figures, so the absence is not read as zero. Never diagnose network latency from throughput. |
| Expected outcome              | User can see whether sustained transfers coincided with a slowdown. |
| Acceptance criteria           | Cumulative counters are never presented as current rates; counter wrap is handled (see the measurement below); loopback is not summed into external throughput; the feature can be disabled; no surface offers or implies a per-application network figure. |
| Confidence level              | Medium |
| Design freedom                | Supporting context rather than a primary incident category in the initial release. |
| Open questions or assumptions | Sandbox feasibility and privacy implications. |
| Measured 2026-08-09 (TASK-40) | **Per-application network attribution is not merely hard, it is unavailable.** No public API returns a per-process byte counter: `libproc` FD enumeration reads 445/447 own-uid processes unsandboxed and **1/447 sandboxed** — one of the few places the sandbox itself, rather than uid, is the binding limit — the PCB tables return zero entries either way, and `socket_info` carries queue occupancy rather than a differenceable counter. `nettop` reaches it only through a private framework. Aggregate, machine-wide throughput **is** available with no extra entitlement. Two rules came out of the same work: `lo0`'s counters wrap at 2^32 even through the 64-bit `if_data64` field (measured mid-transfer, where naive subtraction produced 1.8×10^19), and loopback must be reported separately or one local file copy reads as a WAN transfer. |
| Narrowing status | **Applied 2026-09-09 (challenge C-06).** Narrowed to aggregate-only, exactly as FR-009 was, on the measurement recorded above. Proposed 2026-08-09, deferred once on 2026-08-23, and applied now because a specification that commits the product to something measurement has shown impossible is a defect in the specification, not a pending decision. Nothing was lost: the aggregate half was always the deliverable half. |
| Human-review status           | Approved 2026-09-09 (challenge C-06). |

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
| Deferral status | **Deferred 2026-09-09 (challenge C-05).** Returns only on user evidence. Nothing in a month of real use has asked for it, and when the design reached for baselines independently it made the case and then defeated it: a learned normal is a *second, invisible line*, so a condition that crosses it but not the fixed one is one the settings screen cannot explain (FR-060), and the period during which it is still learning is a period the coverage record has no way to describe. If it returns it should return as its own idea — "this is unusual for your Mac", with the comparison shown — never as a switch that quietly moves the line. |
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

## FR-056 — The system shall identify memory-holding applications the user is not currently working in, during sustained memory pressure.

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-056 |
| Requirement statement | While memory pressure is sustained above normal, the system shall identify applications holding a substantial share of resident memory that own windows but have not been frontmost for a stated period, and offer them to the user as candidates to close, without claiming they are idle, at fault, or that closing them will recover a stated amount. |
| User or system objective      | Give the user an action they can actually take. Under memory pressure the useful question is not "what is using memory" — it is "what am I holding that I am not using", which requires foreground history the user cannot reconstruct from a sorted list. |
| Preconditions                 | Memory pressure is above normal and has been sustained past its duration threshold (FR-007, FR-011). Resident memory is readable for the process (own-uid only). The application owns at least one window. |
| Trigger                       | Sustained memory pressure, evaluated on the sampling loop. |
| Expected behavior | Rank candidates by resident memory among applications that own windows and whose last-frontmost time exceeds a threshold. State the measured resident figure, the observed time since last foreground, and that both are measurements. Offer only the safe actions FR-018/FR-019 already permit — bring forward, reveal — plus a plain instruction for the user to quit the application themselves. Exclude applications the user has marked expected (FR-016). Exclude the system's own protected processes and anything whose memory is not measurable, and say the list is bounded by what can be read (FR-055). |
| Expected outcome              | The user closes something they had genuinely finished with, on their own decision, and can see afterwards what actually changed. |
| Acceptance criteria | No copy asserts an application is idle, abandoned, leaking or wasteful; the claim is confined to "not frontmost since T" and "holding N of measured resident memory". The system never quits, suspends or signals any process (FR-037). No figure is presented for memory that "would be freed". If the user acts, any follow-up states what was re-measured over a bounded window and reports "inconclusive" where the pressure signal did not move (FR-050, FR-036). Applications without a readable memory figure are named as unmeasurable rather than omitted silently. An application marked expected never appears. Foreground history accumulated for less than the stated threshold yields no candidates rather than a list qualified by a caveat. |
| Confidence level              | High for the inputs; medium for the heuristic that not-frontmost implies not-needed. |
| Design freedom | Where this surfaces — the memory card, the incident detail, or a distinct view — is open. Whether last-frontmost is tracked continuously or only while pressure is elevated is an implementation choice with a cost the FR-030 instrumentation should measure. |
| Open questions or assumptions | Measured and available with no additional entitlement: `kCGWindowOwnerName` is readable for every window without Screen Recording permission (window *titles* are not, so no per-document context), `NSWorkspace.frontmostApplication` gives the foreground application, resident memory is readable for own-uid processes, and the official memory pressure signal is already wired. **The known weakness is the heuristic itself**: a background render, download, build or backup is doing exactly what the user asked, and "not frontmost" cannot distinguish it from an application genuinely finished with. Whether an activity signal (audio output, which is already available per-process) should suppress a candidate is unresolved. |
| Human-review status           | **Drafted 2026-08-09 from a product owner request — awaiting review.** Not to be implemented until this row reads Approved. |

### The live surfaces (FR-057 to FR-062)

Added in v1.3 from challenge C-03. This document described incident diagnosis in detail and the surfaces a person looks at every day not at all: they were governed only by FR-002's instruction never to fabricate a measurement, and everything else about them — whether a figure is steady enough to read, whether two surfaces agree, whether an ordering means what it appears to — was decided implementation by implementation and corrected only when somebody noticed on screen.

The defects that reached the product owner in the first fortnight of real use were almost all of this kind. None violated a requirement, because no requirement covered them. Each of the six below names a failure it forbids rather than a feature it wants, which is the property that has made FR-002 and FR-038 useful.

Origin and fuller reasoning: `design/live-surfaces.md`.

## FR-057 — A displayed figure shall state which statistic it is and over what interval

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-057 |
| Requirement statement | A displayed figure shall state which statistic it is and over what interval. |
| User or system objective      | A number beside an application's name is read as "right now" unless it says otherwise. "29%" and "29% on average over the last minute" are different claims. |
| Preconditions                 | A measurement is available to display. |
| Trigger                       | Any live surface renders a numeric figure. |
| Expected behavior             | Every figure is either an instantaneous reading, evident as such from context or wording, or a statistic over a stated window. Where the window is shorter than intended — monitoring has not run long enough — the figure states the span actually covered rather than the span requested. |
| Expected outcome              | The user can trust what a live surface says without checking it against another. |
| Acceptance criteria           | No figure appears whose statistic cannot be determined from the surface; a mean over eight seconds never describes itself as a minute; a figure with no readings behind it renders as unavailable rather than as zero. |
| Confidence level              | High |
| Design freedom                | Wording and placement are open. Whether the window is named in the figure, its column heading or an adjacent caption is a design choice. |
| Open questions or assumptions | None. Partly built: `TrailingPresentation`, and the Now table's paired columns. |
| Human-review status           | Approved 2026-08-31 (challenge C-03) |

## FR-058 — A state shown to the user shall be judged over an interval, not a sample

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-058 |
| Requirement statement | A state shown to the user shall be judged over an interval, not a sample. |
| User or system objective      | A status word is a claim about the machine's condition. Read from one sample it changes as often as the machine breathes, and an indicator that cannot make up its mind is not trusted. |
| Preconditions                 | Retained history covering at least part of the judging window exists. |
| Trigger                       | Any categorical state is presented — status word, severity, menu bar glyph, spoken label. |
| Expected behavior             | The state is derived from a trailing window and does not oscillate at a band boundary. Escalation may be immediate; de-escalation requires clearing the band being left. |
| Expected outcome              | The user can trust what a live surface says without checking it against another. |
| Acceptance criteria           | A reading hovering at a boundary holds its state across consecutive samples; a machine that goes quiet always reaches the calm state, so the deadband cannot strand a word; escalation is not delayed by the mechanism that damps de-escalation. |
| Confidence level              | High |
| Design freedom                | Window length, deadband width and whether escalation is instantaneous are tunable. |
| Open questions or assumptions | Observed 2026-08-31: the headline cycled through three states while load was steady. Built as `Severity.settled`; this requirement exists so it cannot be undone by accident. |
| Human-review status           | Approved 2026-08-31 (challenge C-03) |

## FR-059 — Ordering shall be stable, and shall be by a value the user can see

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-059 |
| Requirement statement | Ordering shall be stable, and shall be by a value the user can see. |
| User or system objective      | A list that reorders every second cannot be read, and a list ordered by a number that is not on screen invites the reader to conclude the ordering is broken. |
| Preconditions                 | More than one row is displayed. |
| Trigger                       | Any list of applications or processes is presented. |
| Expected behavior             | Lists are ordered by a value displayed in the list. The default ordering derives from a window rather than the newest sample. Where ordering is additionally damped, the damping is explained on the surface. |
| Expected outcome              | The user can trust what a live surface says without checking it against another. |
| Acceptance criteria           | Every sort key is a visible column; a one-second spike does not promote a row to the top; any explanation shown for an ordering delay describes the mechanism actually in use. |
| Confidence level              | High |
| Design freedom                | Which statistic orders the list, and whether the user may change it, are open. |
| Open questions or assumptions | TASK-63 cost an hour to a table that was sorting correctly and could not be seen to be. Design 1c already shows the sort indicator on the column heading. |
| Human-review status           | Approved 2026-08-31 (challenge C-03) |

## FR-060 — Two surfaces describing one fact shall not be able to disagree

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-060 |
| Requirement statement | Two surfaces describing one fact shall not be able to disagree. |
| User or system objective      | This is the defect this project produces most: a fix lands on one surface and a second site keeps the old behaviour. Each is individually defensible and the pair is incoherent. |
| Preconditions                 | A fact is presented on more than one surface. |
| Trigger                       | Any fact is rendered in two or more places. |
| Expected behavior             | Where a fact is shown on more than one surface it is derived in one place. Where two surfaces deliberately differ — a summary against a detail view — the divergence is recorded at the point of divergence with its reason. |
| Expected outcome              | The user can trust what a live surface says without checking it against another. |
| Acceptance criteria           | A fact rendered on two surfaces has one source; a deliberate divergence carries a written reason at both sites; a test asserts agreement wherever both can be computed in one process. |
| Confidence level              | High |
| Design freedom                | How the single source is structured is an implementation choice. |
| Open questions or assumptions | **Applies as a debt to pay down, not to new work only** (product owner, 2026-08-31). `probe/seam-reachability.sh` catches capabilities built and never wired; nothing yet catches *fixed in one place*. |
| Human-review status           | Approved 2026-08-31 (challenge C-03) |

## FR-061 — A live surface shall not become part of the slowdown

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-061 |
| Requirement statement | A live surface shall not become part of the slowdown. |
| User or system objective      | FR-030's objective survives its deferred budget, and the live surfaces are where it is most easily lost — they redraw often, and they are open precisely when the machine is struggling. |
| Preconditions                 | A surface is visible. |
| Trigger                       | Any redraw. |
| Expected behavior             | Redraw is driven by data changing rather than by a clock, except where a clock is the data — an age counter during a stall. Work proportional to the size of the process table is done once per sample, not once per redraw. |
| Expected outcome              | The user can trust what a live surface says without checking it against another. |
| Acceptance criteria           | No surface rebuilds a whole-table derivation on a timer; overhead is re-measured after any change to a surface's refresh behaviour. |
| Confidence level              | High |
| Design freedom                | Refresh strategy is open. |
| Open questions or assumptions | Found as a real defect: the Now screen rebuilt the whole family tree once a second to redraw a caption that changes only when a reading is late. |
| Human-review status           | Approved 2026-08-31 (challenge C-03) |

## FR-062 — An action offered shall be one that can succeed

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-062 |
| Requirement statement | An action offered shall be one that can succeed. |
| User or system objective      | A control whose only possible outcome is an apology costs more trust than an absent one. |
| Preconditions                 | An action is available in principle for some process. |
| Trigger                       | Any surface offers a user-directed action. |
| Expected behavior             | An action is offered only where the conditions for its success are known to hold. Where withheld, the surface may explain why but does not present the control. Where an action hands off to macOS and the result cannot be observed, it is reported as a request rather than as a result. |
| Expected outcome              | The user can trust what a live surface says without checking it against another. |
| Acceptance criteria           | No offered action fails for a reason determinable before offering it; a hand-off is never reported as a success; the rule lives in one place rather than at each call site. |
| Confidence level              | High |
| Design freedom                | How an absence is explained is open. |
| Open questions or assumptions | "Show fileproviderd" was offered for a daemon that cannot be activated, at three sites, and fixed at one of them twice. |
| Human-review status           | Approved 2026-08-31 (challenge C-03) |

### The condition/experience distinction (FR-063 to FR-065)

Added in v1.5 after two independent reviews reached the same conclusion by different routes: the product measures resource conditions and reports them as slowdowns, and no amount of threshold, duration or attribution work closes the gap, because the gap is not measurement error.

## FR-063 — A measured resource condition shall not be presented as a slowdown the user experienced

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-063 |
| Requirement statement | A measured resource condition shall not be presented as a slowdown the user experienced. |
| User or system objective      | A machine at capacity because someone started a compile and a machine at capacity while someone waits are the same measurement and opposite events. Reporting the first as a problem tells the user we misunderstand their work. |
| Preconditions                 | A resource condition has been detected. |
| Trigger                       | Any surface describes that condition to the user. |
| Expected behavior             | Copy states what was measured and over what interval — "CPU stayed near capacity for 3 minutes" — and does not assert that the machine was slow, that anything was wrong, or that an application was responsible for a degraded experience. Severity describes the measurement, never the impact. Where the user has reported experiencing a slowdown (FR-064), that report may be presented alongside the condition, and the two remain separately labelled. |
| Expected outcome              | A user doing deliberate heavy work is never told their intended work is a problem. |
| Acceptance criteria           | No notification, headline or summary asserts impaired responsiveness from resource measurements alone; a condition and a user-reported experience are distinguishable wherever both appear; severity wording is not used as a proxy for user impact. |
| Confidence level              | High |
| Design freedom                | Wording and presentation are open, provided the two claims stay distinct. |
| Open questions or assumptions | Apple's own documentation describes elevated CPU during intensive calculation as expected. The product's five questions in §1 remain the right questions; this requirement governs how their answers may be phrased. |
| Human-review status           | Approved 2026-09-06 |

## FR-064 — The user shall be able to report a slowdown as they experience it, and evidence shall be preserved regardless of detection

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-064 |
| Requirement statement | The user shall be able to report a slowdown at the moment they experience it, and the system shall preserve the surrounding evidence whether or not any condition was detected. |
| User or system objective      | The product cannot currently distinguish a busy machine from a slow one and has no instrument that would let it learn. Detection-side feedback can only measure how often detected events were judged useful; it can never measure events that were missed. A user-initiated report samples the population that matters. |
| Preconditions                 | Monitoring is running. |
| Trigger                       | The user reports a slowdown now, or reports that one occurred recently. |
| Expected behavior             | The report is recorded locally with the evidence surrounding it, on the same footing as an incident, and marked as user-provided under FR-038. A report that coincides with no detected condition is retained and is a first-class result, not an error. The user is not required to classify or explain the slowdown. |
| Expected outcome              | The product accumulates evidence about slowdowns it did not detect, which is the only route to knowing its recall. |
| Acceptance criteria           | A report can be made in one gesture from a persistently reachable surface; evidence around the report is retained under the same retention and privacy rules as an incident (FR-029); a report with no matching condition is preserved and shown; nothing about a report is transmitted off the machine. |
| Confidence level              | High |
| Design freedom                | Where the control lives, and whether a retrospective report offers a time window, are open. |
| Open questions or assumptions | Whether a separate "was this alert useful?" judgement is also collected is deliberately left open — it answers a different question from "was this a slowdown?", and a real slowdown can still produce an unhelpful alert. |
| Human-review status           | Approved 2026-09-06 |

**Amendment 1 — a report is kept until the user deletes it (2026-09-09).**

FR-064 originally required reports to follow the same retention as incidents, and the build did that. Design 6d disagreed, and it is right.

The reason is scarcity. An incident is machine-generated and plentiful; a report is a deliberate human gesture, likely a handful a month. Ageing one out at thirty days destroys precisely the signal the feature exists to produce — *"this is the fourth time, and all four were within ten minutes of a backup starting"* — which is the one finding no other instrument in this product can reach. Uniform retention is simpler to explain and would quietly delete the evidence we most need.

So reports are kept until deleted. The count bound still applies, so nothing is unbounded; the user can still delete one or all; and the privacy disclosure must state the difference rather than implying reports follow the retention setting shown above them.

**Acceptance criteria (revised).** A report is not removed by the retention setting; the count bound is still enforced; the privacy screen states that reports are kept until deleted and why; deleting all history still removes them.

## FR-065 — Confidence in measurement, in attribution and in user impact shall be stated separately

| **Field**                     | **Specification** |
|-------------------------------|-------------------|
| Requirement ID                | FR-065 |
| Requirement statement | Confidence in what was measured, in which application it is attributed to, and in whether the user was affected, shall not be combined into a single claim or a single score. |
| User or system objective      | "Sustained memory pressure was measured" and "Xcode is slowing your Mac" differ in three independent ways, and a product that collapses them will be confidently wrong in the one direction that costs most — sending someone to quit the wrong application. |
| Preconditions                 | A statement is being made about a condition, a contributor, or an effect. |
| Trigger                       | Any surface makes such a statement. |
| Expected behavior             | The three are expressed independently and may differ: a measurement may be certain while its attribution is a hypothesis and its user impact is unknown. Numerical confidence scores are not shown to the user; the distinction is carried in wording, consistent with FR-038's evidence classes. |
| Expected outcome              | A reader can tell what we measured from what we inferred from what we are guessing about their experience. |
| Acceptance criteria           | No single label or score stands for all three; a high-confidence measurement never confers confidence on its attribution; no statement about user impact is made from resource measurements alone (FR-063). |
| Confidence level              | High |
| Design freedom                | The vocabulary is open, provided the three remain separable. |
| Open questions or assumptions | Withholding a numerical score is deliberate and is not the same as withholding uncertainty; the uncertainty that matters is expressed in words. |
| Human-review status           | Approved 2026-09-06 |

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
| Phase 1 — Core monitor         | Status surface, process inventory, CPU and application-family resident-memory display, grouping, standalone processes, unattributable activity (FR-055), lifecycle events, bounded history, search, machine context, and overhead instrumentation. | Measurements validated; overhead measured and recorded (the numeric budget is deferred and does not gate — see FR-030); accessible UI; contributors survive PID changes. |
| Phase 2 — Incident diagnosis   | Memory pressure, swap/paging, aggregate disk I/O, storage capacity, low-storage detection, thermal and power context, relaunch-failure signals, audio-activity deferral, incident lifecycle, incident-data retention, notifications, guided investigation, and reports. | Controlled slowdowns and low-storage scenarios produce coherent incidents with acceptable false-positive rates. |
| Phase 3 — Safe response and guidance | Activate, reveal, open system tools, ignore/expected policies, mute, export, safe automation, and post-action verification. | Actions are non-destructive, verified, permission-aware, and followed by measurable outcome reporting. |
| Phase 4 — Advanced context | Explainable baselines, optional network and GPU context, profiles, richer comparisons, and contextual guidance compatible with the Mac App Store. | API, privacy, accessibility, performance, and App Store feasibility are validated on macOS 26 and 27. |
| Deferred — Non–App Store controls | Privileged helpers, CPU ceilings, suspension, reprioritization, efficient-core preference, automatic quitting, and other process-control capabilities. | No initial implementation. Requires a separate product decision and specification. |

# 10. Open product and engineering decisions

Restructured 2026-08-31. This section had become a mix of settled constraints, facts
already answered by measurement, and genuinely open questions, which made it useless for
its one purpose: telling the product owner what still needs an answer. **§10.0 is now the
whole of what is open.** Everything else has moved to §10.2, or was a restatement of §4
and §7 and has been deleted rather than duplicated.

## 10.0 Awaiting a product decision

Nothing else in this document is waiting on the product owner. These are, plus the six
challenges in §10.1.

| # | Question | Governs | Why it is still open |
|---|---|---|---|
| D-01 | Do incident summaries use an on-device language model, or deterministic templates? | FR-013 | **Direction set 2026-08-31:** the product owner is open to a model, on condition it is one shipped *with* macOS 26 or 27 rather than bundled or remote — which points at the Foundation Models framework. A spike is required before this is decided: availability across both target versions, behaviour under App Sandbox and Mac App Store review, what happens on a machine where Apple Intelligence is unavailable or disabled, and above all how a generated sentence is held to FR-038's evidence classification when the generator can produce a fluent claim nothing measured. Templates remain what is built and remain the fallback. |
| D-02 | Is telemetry or crash reporting offered at all? | A-05, FR-029 | **Deferred 2026-08-31.** Revisited once the UX and functionality are right. A-05's default of "no" stands until then and the product works without it. |
| D-03 | Are storage-exhaustion forecasting and folder-level growth attribution in scope? | FR-041, FR-042 | **Deferred 2026-08-31**, tracked in the backlog. Both would need permissions the product does not request. |
| D-04 | Is GPU activity surfaced? | FR-052 | **Recommendation 2026-08-31: as incident context only, in Phase 4, and not as a condition of its own.** The capability is measured working — `IOAccelerator`'s `Device Utilization %`, sandboxed — but it is **machine-wide with no per-process key**, so it can say "the GPU was busy" and never "which application". That answers question 1 of §1's five (*what was constrained*) and cannot answer question 2 (*which application contributed*), which makes it diagnostic context rather than something a user can act on. It also reads up to 68% on an idle desktop from ordinary compositing, so it is only meaningful as a sustained condition. Low value, low cost, no urgency. |
| D-05 | Is baseline learning on by default, over what period, and how is it inspected or reset? | FR-053 | **Recommendation 2026-08-31: defer with FR-053 under C-05.** The question only exists if baselines are built, nothing in two weeks of use has asked for them, and C-05 proposes deferring the requirement itself. Answering this before that would be deciding the details of a feature that may not be wanted. |

## 10.1 Challenges to this specification, raised 2026-08-31

Raised after two weeks of running the built product on a real machine. Each is a
question about whether a requirement still earns its place, not a note that it is
unimplemented. They change the product's shape and that is the product owner's call.

**Status as of 2026-09-09: all six are closed.** This section is now a record rather
than a queue.

| | Answer | Where it went |
|---|---|---|
| C-01 | **Demote**, agreed 2026-08-31 | FR-046 amendment 5. Built: repeated relaunch opens no incident and sends no notification, and remains a record (TASK-102). Design 1o deleted; 4c replaces it |
| C-02 | **Revise**, agreed 2026-08-31 | Amendment drafted at FR-006 and then **refuted by measurement** — see the boxed note there. Stays proposed (TASK-103) |
| C-03 | **Accepted in full**, 2026-08-31 | FR-057 to FR-062, §5. The argument is kept in `design/live-surfaces.md` |
| C-04 | **Already answered**, 2026-09-09 | §1.2's v1.5 rewrite makes success "understand the observed conditions *and their limits*" — which is what C-04 asked for. No further change needed |
| C-05 | **Deferred**, 2026-09-09 | FR-053, FR-025 and FR-026 each carry a deferral note with its reason. Two of the three were independently argued against by the design |
| C-06 | **Applied**, 2026-09-09 | FR-051 narrowed to aggregate-only. Proposed 2026-08-09, deferred once, applied now |

**C-01 — FR-046 (repeated application failure) may not be shippable at acceptable
precision.** In nine days of continuous running it produced ten incidents, every one
false, and no other kind of incident occurred at all. Three successive narrowings each
closed one cause and revealed another: compiler toolchains inside `Xcode.app`, Chromium
helper bundles, then Apple's own multi-executable bundles. The fourth narrowing
(session lifetime) may hold, but its precision is unproven and its recall is now very
low. Consider what remains after all four: *an application you were using disappeared
and came back, three times, within fifteen minutes*. A user generally knows this already
— they watched it happen. Meanwhile we cannot say **why** it went (amendment 1: exit
status is unobservable), and `p_comm`'s 16 bytes leave the subject ambiguous. The
options are to ship it with the current narrowing and watch, to reduce it to a lifecycle
*record* in the inspector with no incident and no notification, or to cut it from the
initial release. **Recommendation: reduce to a record.** The evidence is that its false
positives cost more trust than its true positives have yet earned — there have been
none.

**C-02 — the CPU threshold may sit well above where users perceive slowness.** FR-006's
default is 85% of total machine capacity sustained for three minutes: on an eight-core
Mac, roughly 6.8 cores busy continuously. Observed on 2026-08-31, a machine at 86% with
a load average of 26 was described by its owner as loaded and by this product as barely
qualifying. Perceived slowness correlates with contention — run queue depth, scheduling
latency — more closely than with a busy-time percentage, and a machine at 60% with 40
runnable threads feels far worse than one at 95% running two. This document mentions run
queue nowhere. It was previously rejected as a *displayed* figure for good reason (a load
average of 18 invites exactly the wrong conclusion), but that is an argument about
presentation, not about whether it should inform detection. **Recommendation: a spike to
compare run-queue depth against busy-time as a slowdown predictor, before the default
threshold is settled.**

**C-03 — the document treats incident diagnosis as the primary product; observed use
does not.** DR-01 and §1.2 both centre the product on opening an incident afterwards and
understanding it. In two weeks of real use, every piece of product feedback concerned the
*live* surfaces: what the popover says now, whether a figure is an instant or a trend,
whether the status word is steady, whether a table's ordering can be trusted. Not one
concerned an incident report, and no legitimate incident was recorded to read. That may
be because the detection thresholds are wrong (C-02), or because a well-behaved machine
genuinely has few incidents — but either way the product a user touches daily is a live
monitor, and this specification's acceptance criteria barely describe it. **Recommendation:
either add first-class requirements for the live surfaces' honesty over time — trends,
settling, ordering stability, which are currently governed only by FR-002's general
"never fabricate" rule — or state explicitly that they are secondary and accept that the
product's daily value rests on requirements this document does not have.**

**C-04 — the success definition does not survive the attribution ceiling.** §1.2 says the
product succeeds when a user can understand "which applications were associated with"
a condition. Measured: roughly 40 percentage points of busy CPU is unattributable in a
Mac App Store build, because per-process data is denied for every process owned by
another user and that is a uid boundary, not a sandbox one. FR-055 handles this honestly
on screen. The *success definition* has not been updated to match, and as written it sets
a bar the distribution model forbids clearing. **Recommendation: reword §1.2 so success
includes stating what could not be attributed and why, which is what the product actually
does well.**

**C-05 — three Phase 4 requirements have no evidence of need.** FR-053 (explainable
baselines), FR-025 (named profiles) and FR-026 (contextual profile activation) were
written before anything was built. Nothing in two weeks of use has suggested a user wants
them, and each is substantial. **Recommendation: move all three to Deferred with a note
that they return only on user evidence.** No work is lost; the backlog simply stops
implying they are planned.

**C-06 — FR-051 promises what cannot be built.** See the measurement recorded against it.
The narrowing to aggregate-only has been proposed since 2026-08-09 and deferred once.
Until it is applied, this document commits the product to per-application network
attribution that no public API can provide.

## 10.2 Settled, and not to be reopened without evidence

Kept because a later reader will otherwise ask again, not because anything is pending.

- **Distribution, sandboxing and process control.** Mac App Store first, direct download deferred; no privileged helpers or elevated components; no automatic suspension, quitting or other process control. These restate A-03, A-04 and §7 and are not separate decisions.
- **Platform.** macOS 26 and 27, Apple Silicon. Restates A-01.
- **Raw hardware temperature: not exposed.** Public thermal state only — raw values need undocumented SMC keys, which A-03 and FR-010 both rule out.
- **Incident persistence** (2026-08-09): records persist across restarts, on by default, kept 30 days, user-adjustable 7/30/90, additionally count-bounded. See FR-029.
- **Crash logs and hang reports:** out of scope. Unreadable from the sandbox.
- **Wakeups and sleep-prevention:** unavailable. See FR-048.
- **Fan metrics and per-process network:** unavailable. See FR-051's measurement.
- **FR-050 post-action verification is staged, not wired** (2026-08-09): every action this build offers is observational, so there is no outcome to measure and a before/after around one would be the false causal claim FR-050 exists to prevent.

Answered by measurement, recorded in `probe/FINDINGS.md`:

- Primary memory metric **for other processes**: resident size, by elimination — `phys_footprint` is denied for anything but ourselves. Not to be confused with FR-030's rule that **our own** cost must be stated in `phys_footprint`: the two differ because different data is available about other processes than about this one.
- Per-process disk I/O, footprint and wakeups: unavailable.
- Per-application audio: available, without a microphone permission.
- Application unresponsiveness: unavailable; repeated relaunch is available.
- Window titles and per-tab context: unavailable without Screen Recording.

## 10.3 The largest single risk, which is not a decision

Whether App Review accepts `sysctl KERN_PROC_ALL` for process enumeration, given that
`proc_listpids` is explicitly denied and Apple has stated no entitlement lifts it. The
product requests no entitlements beyond App Sandbox, but no Apple statement blesses the
alternative, and **this cannot be settled by testing** — it needs a DTS incident, which
is the product owner's action rather than a work item. Recorded here as a risk rather
than an open question because there is nothing to decide until Apple answers.

Mitigation in place: `ProcessSampler.processTable()` is the single point of contact, so
the day this breaks there is exactly one place to change. See `.backlog/decisions/decision-1`.

# 11. Implementation authority

- This document is the authoritative source for product scope and implementation behavior.
- Product, design, engineering, security, privacy, QA, and release decisions shall be evaluated against the requirements and acceptance criteria in this document.
- Where a requirement is technically infeasible under a target macOS version or distribution model, the implementation team shall document the limitation, propose a compliant alternative, and obtain a product decision before changing scope.
- Features not defined here require an explicit requirements update before implementation.
- UI screens and interaction concepts will be produced separately using Claude Design. Those artifacts are design inputs, while this document remains authoritative for behavior, scope, safety, privacy, accessibility, and acceptance criteria.
- Internal architecture and algorithms remain implementation choices unless constrained by a stated requirement or acceptance criterion.
