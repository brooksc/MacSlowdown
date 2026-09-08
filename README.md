# MacSlowdown

A native macOS performance monitor that watches for sustained resource conditions, keeps bounded evidence about them, and explains what it measured without overstating what it knows.

> ### ⚠️ Work in progress — not released, not ready to use
>
> This is an unfinished project, published while it is still being built. There is no release, no signed build, and no installer. Parts of the interface have never been run by a person, the product's shape is still being argued about in `requirements.md` §10, and things documented here as decided have in several cases been decided *and then reversed* a week later.
>
> It is public because working in the open is useful, not because it is ready. Please don't judge it as a finished product, and don't expect it to build into something you can use yet.

## What problem it addresses

A Mac feels slow, hot, or unresponsive. Existing tools require you to notice while it is happening, understand process-level terminology, correlate several resource categories by hand, and judge whether a number is abnormal. By the time you open Activity Monitor the cause may have stopped or relaunched.

MacSlowdown watches continuously, keeps evidence from before and during an episode, groups processes into applications, and tries to shorten the path from *"my Mac feels slow"* to a defensible answer.

## The idea it is currently built around

**A measured resource condition is not a slowdown the user experienced.** A capped build and a genuine problem produce the same reading, for the same duration, with the same attribution — the only thing separating them is whether the person started the work on purpose, which the app cannot see.

So it states what it measured and stops. "CPU stayed near capacity for 9 minutes", not "your Mac is slow". Sustained CPU load is recorded but does not interrupt, because interrupting someone about work they started deliberately is the fastest way to be switched off. And the app asks the user to tell it when something *felt* slow, because that is the only way it ever learns about the episodes it could not see.

## What it deliberately cannot do

These are measured constraints, not missing features. `probe/FINDINGS.md` has the evidence.

- **About 40% of a busy Mac's CPU is unattributable.** Processes owned by other users are invisible to a sandboxed app — and equally invisible unsandboxed. Only root sees them. The app shows that share rather than quietly leaving it out.
- **No process control of any kind.** It cannot quit, suspend or limit anything. Every action it offers is observational.
- **Application hangs are undetectable.** macOS reports a beachballing app identically to a healthy one.
- **Per-app network attribution is impossible**, and per-process disk I/O and wakeups are blocked.

## Layout

| Path | What it is |
|---|---|
| `requirements.md` | The authoritative specification. Start at §1 |
| `scenarios.md` | Seven situations a person is actually in, and how each one fails |
| `REVIEW.md` | A reading order for someone assessing the project |
| `CLAUDE.md` | Operating rules and verified platform facts |
| `Metrics/` | The framework — sampling, identity, grouping, attribution, detection |
| `MacSlowdown/` | The app — menu bar, windows, presentation rules |
| `probe/` | Standalone probes and `FINDINGS.md`, the measured platform capability |
| `design/` | Rendered design references and their index |
| `.backlog/` | Tasks and decision records |

## Building

Requires Xcode and [Tuist](https://tuist.dev). Apple Silicon, macOS 26 or 27.

```sh
tuist generate --no-open
tuist xcodebuild test -scheme AllTests -configuration Debug -destination 'platform=macOS'
```

Three tests synthesise CPU load and measure the real machine, so they fail on a busy one and report it honestly rather than passing. Re-run any failure in isolation before treating it as a regression.

## A note on how this was written

Most of the code and documentation here was written by Claude, working from a specification and a running argument with the product owner about what the app is allowed to claim. The commit messages and the backlog notes are unusually candid about mistakes, reversals and things measured and then abandoned — that is deliberate, and it is most of what makes the history worth reading.

## Licence

None yet. All rights reserved until one is chosen.
