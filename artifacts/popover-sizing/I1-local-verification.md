# I1 Local Verification

Date: 2026-08-14

Branch: `codex/popover-sizing-fix`

Base: `78c7b4e`

Environment: Xcode 26.6, Swift 6.3.3, macOS 26.5.1 arm64, 2x display

## Result

The atomic sizing cutover passes the complete local synthetic verification. No live ClaudeBat app was launched, no real credential or API path was used, and no app bundle, DMG, installation, push, tag, or release operation was performed.

## Commands and outcomes

- Focused `UsageModelsTests`: 12 tests passed.
- Full default `swift test`: 157 tests in 18 suites passed; the three GUI suites were intentionally skipped by default.
- G1 `CB_RUN_APPKIT_LAYOUT_TESTS=1`: 7 tests passed.
- G2 `CB_RUN_APPKIT_POPOVER_TESTS=1`: 1 real-shown-popover signal test passed; 112 genuine shape-change callbacks across the retained-host cycle and no stable churn, as recorded in the G2 artifact.
- G3 `PopoverSizeCoordinatorTests`: 11 adversarial state-machine tests passed.
- G4 `CB_RUN_APPKIT_LIFECYCLE_TESTS=1`: 4 real-shown-popover lifecycle tests passed, including explicit preflight-failure callback balancing.
- Debug `swift build`: passed.
- Release `swift build -c release`: passed.
- `git diff --check`: passed.

All Swift commands used the full Xcode toolchain through per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Sandboxed CLI runs also redirected compiler module caches to `/private/tmp` and used SwiftPM's `--disable-sandbox`; GUI-only G2/G4 runs used the logged-in WindowServer because a headless sandbox correctly exposes no `NSScreen`.

## Shipping-path source audit

- Removed bridge symbols have no active consumers: `measuredUsageHeight`, `preferredHeight`, `recordMeasuredHeight`, `onPreferredHeightChange`, `lastReportedPopoverHeight`, and `AppDelegate.PopoverLayout` are absent.
- The old `UsagePopoverView` `GeometryReader` reporter and environment `dismiss()` path are absent.
- `CBSpacing.popupHeightWithBanner` remains only as a zero-consumer legacy definition for release-safe rollback.
- The primary usage popover has one runtime size mutation: the coordinator sink in `ClaudeBatApp.swift`.
- The usage host never assigns `preferredContentSize` and has native preferred-size tracking disabled.
- The separate context-menu host/popover retains its existing, explicitly allowlisted sizing assignments.
- `WeeklyUsageRow` constrains its transparent balancing cell to one point high.
- Model rows use `Identifiable` API IDs with a deterministic fallback rather than display-label identity.

## Remaining release blocks

Local I1 evidence does not replace the required E0-R matrix. macOS 14/15 GUI runners, Intel while universal Intel support remains claimed, a physical 1x display, small-screen overflow evidence, the defined soak/performance run, independent review, and explicit release/install authorization are still outstanding. A missing runner is unresolved evidence, never a pass.
