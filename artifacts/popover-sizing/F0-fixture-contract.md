# F0 Deterministic Fixture Contract

Status: passed locally. The contract is implemented by `PopoverLayoutFixtureFactory.swift`, its focused isolation suite, and the exact-root AppKit suite.

## Purpose

All sizing tests must render synthetic account shapes without reading or mutating the user's Claude state. A fixture must fail closed if a code path attempts network, OAuth, CLI, credential writes, production defaults, monitor files, or host installation discovery.

## Factory contract

Use one test-only `makeLayoutViewModel` factory. Its call site supplies every `UsageViewModel` initializer argument; no default service is allowed:

| Dependency | Fixture implementation | Constructor budget | Pure-layout budget |
|---|---|---:|---:|
| `TokenProvider` | in-memory synthetic snapshot | `readOAuthSnapshot == 1` | all writes `0` |
| `UsageFetching` | fail-fast fake | `0` | fetches `0` |
| `BudgetTracking` | fail-fast/counting actor | `0` | reservations `0` |
| `UsageCaching` | in-memory fixture cache | `read == 1` | writes `0` |
| `RecoveryStatePersisting` | in-memory fixture store | `read == 1` | writes `0` |
| `AppMonitoring` | in-memory counter only | `0` | records `0` |
| `AuthRefreshing` | fail-fast fake | `0` | refreshes `0` |
| `ClaudeCLIRecovering` | fail-fast fake | `0` | recoveries `0` |
| `NetworkReachabilityChecking` | fixed `.reachable` fake | `0` | reads `0` |
| `AppBuildInfo` | literal synthetic value | n/a | n/a |

Mandatory initializer values:

```text
token = "synthetic-layout-token-do-not-use"
buildInfo = (appVersion: "fixture", buildFlavor: "test", gitCommit: "fixture", bundleIdentifier: "test.claudebat.layout")
wakeCoalescingWindow = 5
wakeAuthRetryInterval = 30
startImmediately = false
```

`UsageViewModel.init` is expected to perform exactly one token snapshot read, one cache read, and one recovery-store read even when `startImmediately` is false. Those reads are not side-effect violations; all other constructor work must remain in memory.

Lifecycle harnesses have a separate declared budget: `onPopoverOpen`/`onPopoverClose` may record their expected in-memory lifecycle events, but the run stays below 65 seconds, uses fresh data with future reset dates, and always calls `shutdown`. Network/auth/CLI/write budgets remain zero.

## Literal content fixtures

Reference instant: `2026-08-14T12:00:00Z`. Display timezone: UTC. Dates are intentionally away from minute, day, and reset boundaries.

Shared compact values:

```text
five-hour utilization = 8       (displays 92 remaining)
seven-day utilization = 50      (displays 50 remaining)
five-hour reset = 2026-08-14T15:59:00.000Z
seven-day reset = 2026-08-21T18:00:00.000Z
fetchedAt = 2026-08-14T11:59:38Z
```

Supported model labels:

```text
ASCII short: "Fable"
ASCII wide: "WWWWWWWWWWWWWWWWWWWWWWWW"
Unicode robustness: "Sonnet e\u{301} — 測試"
```

The ASCII-wide label is inside the supported envelope. The Unicode case is a robustness probe and may trigger a separate scope decision if it cannot fit without redesign.

Extra Usage fixtures:

```text
off: isEnabled=false
normal: isEnabled=true, usedCredits=1234, monthlyLimit=10000, utilization=12.34
wide: isEnabled=true, usedCredits=999999, monthlyLimit=999999, utilization=100
```

Error literals:

```text
short: "Unknown error"
three-line: "The usage service returned an unexpected response.\nClaudeBat kept your synthetic data unchanged.\nTry the fixture again after the test resets."
offline: "ClaudeBat could not reach the synthetic usage endpoint.\nNo network request was made."
```

## Required state matrix

1. Normal compact: no model rows, Extra Usage off, no cached banner, freshness present.
2. Normal expanded: two model rows plus Extra Usage normal.
3. Normal heavy: four model rows, ASCII-wide label, Extra Usage wide.
4. Cached normal: each `CachedDataReason` independently, then off again.
5. Canonical Game Over: session depleted, no banner, Extra Usage off; expected outer height 392.
6. Variable Game Over: weekly depleted, each banner, Extra Usage on/off, long display numbers; expected height at least 392 with all landmarks in bounds.
7. Error: short and explicit three-line literals.
8. Offline: fixed offline literal.
9. Reconnect/setup: Claude installed true and false, injected rather than discovered from files or `PATH`.
10. Loading and recovering: each production message branch.
11. Freshness: empty, fresh, stale, refreshing.
12. Identity: duplicate and reordered model display labels with distinct model IDs.

For every conditional block, run off -> on -> off on one retained host. For the account-shaped regression, run compact A -> expanded B -> compact A. The final compact size must return within 1 point of the initial compact size.

## Deterministic time and installation seams

Current production rendering calls `Date()` internally in `UsagePeriod`, `GameOverView`, `FreshnessIndicator`, and `UsageViewModel`, while static date formatters inherit the process timezone. Exact fixture strings therefore are not yet deterministic.

Before F0 approval, add an unwired/test-injectable display environment carrying:

- `now: () -> Date`, fixed to the reference instant in tests;
- a display `TimeZone`, fixed to UTC in tests;
- Claude installation state, supplied explicitly to the exact reconnect root.

The default production values remain the real current time, current display timezone, and existing installation check. Tests must not change `TZ`, `PATH`, `HOME`, global `UserDefaults`, or system clock. The seam must not alter auth, polling, or API behavior.

## Artifact and teardown rules

- Pure layout tests use no `UserDefaults` instance and never instantiate `MonitorService`.
- A shown-popover harness runs only in a serialized GUI test process with a synthetic anchor window.
- Automation never activates the app, installs global event monitors, uses the clipboard, invokes `openURL`, or clicks Copy/Manage Usage.
- Teardown shuts down the coordinator and view model, closes and releases the popover/anchor window, drains at most two run-loop turns, and verifies weak UI references are nil.
- Screenshots or ledgers use only synthetic values and live under a UUID temporary directory; successful temporary artifacts are removed.
- No artifact contains tokens, fingerprints, account/model data from a live API, filesystem paths outside the synthetic harness, or monitor-log output.

## Approval checklist

- [x] One factory spells every dependency argument.
- [x] Constructor call budgets are asserted.
- [x] Pure-layout zero-call budgets are asserted.
- [x] Fixed clock/timezone seam is compiled and exercised.
- [x] Installed/not-installed state is injected through the exact root.
- [x] Every state fixture above is buildable without private-state mutation.
- [x] Production defaults and live services are absent from the test object graph.
- [x] The source and artifact scan contains no real secret or generated UI artifact.
