---
id: TASK-65.17
title: 'Screen 2d — Menu bar icon: four states, shape-led, with an optional readout'
status: In Progress
assignee: []
created_date: '2026-08-09 02:26'
updated_date: '2026-08-09 19:19'
labels:
  - ui
milestone: m-1
dependencies: []
parent_task_id: TASK-65
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reference: `design/screens/2d.png`. Alternatives explored and superseded: `design/screens/2a.png` (gauge ring), `2b.png` (stacked bars), `2c.png` (silhouette swap). 2d is the recommended spec and develops 2b's silhouette. No backlog item exists for 2a-2c — they are rejected options.

Existing implementation: `MacSlowdownApp.swift` renders `Image(systemName: store.severity.symbolName)` with an accessibility label (TASK-11).

**What the design specifies**

The constraint stated up front: the icon is ~16 pt tall in a crowded, sometimes translucent strip, so colour alone cannot carry meaning.

**Four states, not three** — our severity model has three:
| State | Meaning | Colour | VoiceOver |
|---|---|---|---|
| Normal | No rule is close to firing | green | "MacSlowdown, normal" |
| Elevated | A threshold is crossed but hasn't lasted long enough to be an incident | yellow | "MacSlowdown, elevated, CPU" |
| Incident open | Sustained past the duration threshold. Badge appears | red | "MacSlowdown, severe, memory, 11 minutes" |
| Muted or paused | Still recording, just not interrupting. **Never silently invisible** | grey | "MacSlowdown, muted for 41 more minutes" |

**Elevated** is the addition that matters: it is the visible expression of FR-006's sustained-not-transient rule. Without it the icon jumps from fine to incident and the duration threshold is invisible. **Muted** must never mean "looks the same as normal".

**Optional readout**: icon only (default), with CPU percentage, or with a 60-second sparkline.

**Rules, quoted:**
- Shape carries the state; colour only reinforces it. In Increase Contrast the fills go to pure black/white outlines.
- Transitions cross-fade over 250 ms and are rate-limited to one change per 2 s, so the icon never strobes.
- No animation, ever — "a spinning menu bar icon during a slowdown is the single most irritating thing this app could do."
- The icon is drawn on the high-priority path, so it keeps updating even if the main window is busy (the claim screen 1n makes to the user).
- **Red never appears for a workload the user marked expected; that shows as yellow at most.** — the per-app rules of screen 1j reaching the menu bar.

**Gap against what we render today**

We use SF Symbols keyed to a three-value severity. Verified working: the accessibility label reads "MacSlowdown: Normal". Missing: the elevated and muted states, the shape-led custom silhouette, the incident badge, the optional readouts, the rate limiting and cross-fade, the Increase Contrast treatment, and the expected-workload cap.

Note FR-034 requires severity never be conveyed by colour alone, and TASK-15 (accessibility baseline) is parked awaiting someone with VoiceOver — the VoiceOver strings above are part of this spec and cannot be signed off without that.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The icon distinguishes four states including elevated and muted, and muted is never visually identical to normal
- [ ] #2 State is carried by shape, with colour only reinforcing it, and the treatment holds under Increase Contrast and Reduce Transparency (FR-034)
- [x] #3 An open incident carries a badge, and severity plus duration are available to VoiceOver
- [x] #4 State changes are rate-limited and cross-faded so the icon cannot strobe, and nothing animates
- [x] #5 An application the user marked as expected never drives the icon to its most severe state
- [x] #6 The optional readouts (percentage, sparkline) are available and off by default
- [ ] #7 The icon keeps updating while the main window is behind, verified under real load rather than assumed
- [ ] #8 VoiceOver strings verified by a person using VoiceOver, or explicitly recorded as not verified (see TASK-15)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## TASK-65.17 — implementation (branch `worktree-agent-a61207b112d62125d`)

All logic is pure and in new files; the app scene needs one closure changed.

### The state model

`MenuBarIconState` (`MacSlowdown/Sources/MenuBarPresentation.swift`): `.normal` /
`.elevated` / `.incident` / `.muted`. Shape is the carrier — `filledBars` is
1 / 2 / 3 / 0 and `.muted` alone is `isSlashed`, so muted differs from normal in
**two** independent ways and cannot collapse into it under a monochrome render.
`tint` (green / yellow / red / grey) is a name, not a `Color`, so the model is
testable without SwiftUI and the view can drop colour entirely under Increase
Contrast.

`MenuBarIcon.presentation(for: MenuBarIconInputs)` derives it, in order:

1. **muted** → `.muted`. Mute wins the glyph (FR-015: a monitor that has stopped
   interrupting must say so on the only always-present surface).
2. **incident open, not capped** → `.incident`.
3. **incident open, leading application `.expected` or `.ignored`** → `.elevated`.
   The design's "red never appears for a workload the user marked expected".
4. **live severity > .normal, no incident** → `.elevated`. `.severe` without an
   incident is still elevated: that is FR-006's sustained-not-transient rule made
   visible.
5. otherwise `.normal`.

`showsBadge` is `incidentIsOpen`, independent of state — a muted or
policy-capped incident is still badged. The badge says "an episode is being
recorded", a fact we are not entitled to withhold; only the colour is suppressed.

Inputs: live `severity`; `incidentIsOpen` / `incidentSeverity` /
`incidentConditions` / `incidentDuration`; `elevatedConditions` (live breaches);
`isMuted` / `muteRemaining` / `muteIsIndefinite`; `leadingApplicationName` /
`leadingApplicationPolicy`. `MonitorStore.menuBarIconInputs` — an extension in
`MenuBarIconView.swift`, the store file itself untouched — gathers them.

### The expected-workload cap, and where the policy comes from

The leading application comes from `openIncident?.attribution?.leadingApplication`
when an incident is open — what the incident recorded while it was happening,
never live state — and otherwise from
`MenuBarIcon.leadingApplication(attribution:families:)`, which locates the top
contributor's family by scanning rather than sorting (the icon redraws far more
often than the inventory).

It reduces to `MenuBarIcon.LeadingApplication` (bundleID / bundlePath /
displayName) and is matched against `MonitorStore.policies.policies` by
`MenuBarIcon.policy(for:in:)`, which reproduces `ApplicationPolicy.matches`'s
order — bundle identifier, then bundle path, then display name **only** for a
policy carrying neither. Re-implemented rather than reused because `matches`
takes a `ResolvedIdentity`, which an incident recorded weeks ago does not have.

`.ignored` caps as well as `.expected`. The design names "expected", but
`.ignored` is the strictly stronger statement and it would be incoherent for the
weaker rule to cap while the stronger one did not. Flagged as a judgement call.

### The rate limiter

`MenuBarIconRateLimiter.decide(displayed:desired:lastChangeAt:now:minimumInterval:)`
— pure, returns `.unchanged` / `.apply` / `.hold(remaining:)`.
`MenuBarIcon.minimumInterval` is 2 s. `MenuBarIconModel` (`@MainActor
@Observable`) owns `displayed` and `lastStateChangeAt`; on `.hold` it schedules
one task for `remaining` and re-offers, so **a held change is never dropped** —
late by at most 2 s, never lost. A later update cancels the pending one, so the
newest desired state wins.

Only the **state** is rate-limited. The spoken label carries a live duration
("11 minutes") and the badge follows the incident; holding those would make the
icon quietly wrong for two seconds to prevent a flicker a string cannot cause.

Cross-fade is `MenuBarIcon.crossFadeSeconds = 0.25`, applied with
`.animation(.easeInOut, value: state)`. **Nothing moves**: the three bars have
fixed frames and only their fills change, so there is no geometry to interpolate.
That is a property of the view's construction rather than something a test can
observe — asserted only as the constants.

### VoiceOver

The four strings from the design's table are produced verbatim and asserted:
`"MacSlowdown, normal"`, `"MacSlowdown, elevated, CPU"`,
`"MacSlowdown, severe, memory, 11 minutes"`,
`"MacSlowdown, muted for 41 more minutes"`.

Two documented extensions where the table did not consider the combination:

- muted **with an incident open** appends `", incident open, memory, 11 minutes"`
  — dropping the incident from the only always-visible surface would be worse
  than extending the string;
- an elevated state **capped by a policy** appends `", Xcode is marked as
  expected"`, so a user who wonders why it is not red can hear why.

Condition words are `CPU` / `memory` / `storage` / `thermal` (not
`IncidentCondition.label`, which is written for a report sentence), ordered by
`IncidentCondition.allCases` so the label does not swap words between samples.
Durations under a minute read "less than a minute" rather than rounding to 0 or 1.

### Readouts

`MenuBarReadout` — `.iconOnly` (default) / `.cpuPercentage` / `.sparkline`,
`@AppStorage` key `"menuBarReadout"`; an unrecognised stored value falls back to
`.iconOnly`. The percentage is machine-relative and returns **nil** when there is
no attribution yet, rendered as an em dash with the spoken label "CPU not
measured yet" — no reading is not a reading of zero (FR-002). The sparkline is
built by `MenuBarIcon.sparklinePoints(retained:now:window:)` from
`MonitorStore.retainedSamples` via `SparklinePresentation.totalBusySeries`,
windowed to 60 s, and is **not drawn at all** below
`SparklinePresentation.minimumPoints` — a flat line in a 40 pt strip reads as a
quiet machine when the truth is that we have not watched long enough.

### Increase Contrast / Reduce Transparency

`MenuBarIconTreatment.resolve(increaseContrast:reduceTransparency:)`: Increase
Contrast drops the tint entirely (glyph in `.primary`, i.e. pure black/white) and
strokes the unfilled bars; Reduce Transparency keeps colour but also strokes
rather than dimming. `MenuBarIconTreatment.current` reads
`NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` /
`...ShouldReduceTransparency`; the view reads the equivalent SwiftUI environment
values. Tested for the mapping and that reading the system settings is total.
**The visual result is not verified** — that needs eyes on a menu bar.

### Files and tests

Added: `MacSlowdown/Sources/MenuBarPresentation.swift`,
`MenuBarIconRateLimiter.swift`, `MenuBarIconReadout.swift`,
`MenuBarIconView.swift`, `MacSlowdown/Tests/MenuBarIconTests.swift`. Nothing else
changed.

`nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .build -only-testing:MacSlowdownTests`
→ **499 passing, 0 failures** (466 before; 33 new). Nothing in the new tests
starts monitoring or inserts a status item — the store is built with an isolated
`PolicyStore` and `StorageScreenModel`, and `AppDelegate.isHostingTests` is
asserted true in the view-construction test.

### The wiring, for `MacSlowdownApp.swift` (owned by another agent)

Replace lines 42–50 — the `} label: { … }` closure of the `MenuBarExtra`, from
`} label: {` through the `.accessibilityLabel(...)` line and its closing `}` —
with exactly:

```swift
        } label: {
            // Four states, shape-led (design 2d, TASK-65.17). Everything the icon
            // decides — the state, the badge, the 2 s rate limit, the
            // expected-workload cap and the spoken label — lives in
            // `MenuBarPresentation.swift` and `MenuBarIconRateLimiter.swift`, so
            // none of it is reachable only by looking at a menu bar.
            //
            // Monitoring starts here rather than on a window: the menu bar item is
            // the only always-present surface, and FR-001's whole point is noticing
            // degradation without opening anything.
            MenuBarIconLabel(store: store)
        }
```

That is the whole of the wiring. `Severity.symbolName` becomes unused by the app
scene but is left in place — it lives in `MonitorStore.swift`, owned elsewhere.

### Settings control (not applied — `SettingsView.swift` is owned by another agent)

The readout preference has no UI yet. To add it, in `SettingsView.swift`:

```swift
    @AppStorage(MenuBarReadout.storageKey)
    private var menuBarReadout = MenuBarReadout.default.rawValue

    // …inside the General form:
    Picker("Menu bar readout", selection: $menuBarReadout) {
        ForEach(MenuBarReadout.allCases) { readout in
            Text(readout.label).tag(readout.rawValue)
        }
    }
    .accessibilityHint("Adds a CPU percentage or a 60-second trend beside the menu bar icon.")
```

Until that is applied the readouts are reachable only by writing the
`menuBarReadout` default by hand. Criterion #6 is checked because the three
readouts exist, are implemented and default to icon-only; the *control* is
pending that snippet.

### Unverified

- **#7 (icon keeps updating under real load)** — unchecked. Requires running the
  app and loading the machine; nothing was put on screen.
- **#8 (VoiceOver strings)** — unchecked. The strings are asserted by test but
  nobody has heard them. Blocked on TASK-15 (parked, needs a person with
  VoiceOver).
- **#2's visual half** — checked for the implemented and tested behaviour (colour
  dropped, fills become outlines), but whether the result is legible in a real
  menu bar under Increase Contrast is **not verified** and needs eyes.
- The glyph has never been rendered. It compiles and its logic is tested; its
  appearance at 16 pt is unknown.
- macOS may render a `MenuBarExtra` label as a monochrome template regardless of
  the tint we ask for. Survivable by design — shape carries the state — but the
  colour reinforcement may simply not appear. Worth looking at when someone runs
  it.

### Criteria, finally

Checked: **#1, #3, #4, #5, #6** — each is a rule expressed in code and asserted by
the new tests.

Left unchecked, deliberately:

- **#2** — the Increase Contrast / Reduce Transparency treatment *is* implemented
  and its mapping is tested, but the criterion is about how the glyph reads on a
  screen and nothing has been rendered. Correcting the wording above: #2 is
  **not** checked.
- **#7** — needs the app running under real load.
- **#8** — needs a person with VoiceOver; blocked on TASK-15 (parked).
<!-- SECTION:NOTES:END -->
