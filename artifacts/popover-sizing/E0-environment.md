# E0 Environment Evidence

Recorded: 2026-08-14 (Europe/London)
Repository: `78c7b4e` on `codex/popover-sizing-fix`

## Local implementation runner

| Item | Observed value | Local result |
|---|---|---|
| Xcode | 26.6 (17F113) | pass |
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`) | pass |
| SDK | macOS 26.5 | pass |
| Runtime | macOS 26.5.1 (25F80) | pass |
| Architecture | arm64 | pass |
| WindowServer/AppKit | `NSScreen.screens.count == 1` | pass |
| Visible frame | 1728 × 1084 points | recorded |
| Backing scale | 2.0 | pass for local 2× coverage |
| Package tests | 126 tests in 13 suites | pass |
| Debug build | `swift build` | pass |

The machine-wide `xcode-select` remains `/Library/Developer/CommandLineTools`. All project commands must therefore set:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

This is intentional; the gate does not modify global developer-tool selection.

## Commands used

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --show-sdk-version
sw_vers
uname -m
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift -e \
  'import AppKit; print(NSScreen.screens.count); NSScreen.screens.forEach { print($0.visibleFrame, $0.backingScaleFactor) }'
```

The first user test invocation passed, then attempted the nonexistent concatenated command `swift-buildcd`. That shell typo is not a product or test failure. A separate `swift build` subsequently passed.

## Scope of this pass

The local runner is ready for deterministic fixtures, detached AppKit characterization, coordinator tests, and a synthetic shown-popover harness. It is not sufficient by itself to claim all supported-runtime or display coverage.

Still required before Gate 2 can be declared fully green and before release:

- latest patched macOS 14 on Apple Silicon with a GUI session;
- macOS 15 on Apple Silicon with a GUI session;
- one actual 1× display run;
- Intel on the oldest supported runtime while universal Intel builds remain supported;
- a recorded owner/runner for each tuple.

Missing remote/display tuples do not block safe local G1/G3 work. They remain a hard block on final G2 approval, I0 authorization, and release.

## Safety boundary

No installed app was replaced or launched. No credential store, Keychain item, Claude credentials file, live API, OAuth refresh, Claude CLI recovery, UserDefaults production domain, monitor log, packaging script, signing flow, tag, or release was used.
