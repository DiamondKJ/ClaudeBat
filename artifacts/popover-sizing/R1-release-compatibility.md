# R1 Release Compatibility Correction

Date: 2026-08-14

## Failed packaging attempt

The immutable `v1.0.17` tag points to merge commit `1c06a5a386824adf027564cf17c6507f8fbaad83`.
GitHub Actions run `31815502500` failed while compiling the app on the `macos-14` runner with Xcode 15.4. The SDK does not provide SwiftUI's `onGeometryChange`, so packaging stopped before a DMG or GitHub Release was created. The tag will not be moved, reused, or deleted.

## Focused correction

The live invalidation seam now observes the final root with a background `GeometryReader`, `onAppear`, and `onChange(of:)`, all available to the macOS 14/Xcode 15.4 toolchain. The observed size is validated and discarded; the session coordinator remains the only sizing owner and remeasures current content at drain time.

A new pull-request workflow builds the universal app bundle on `macos-14`. This makes the exact release-runner product compilation a pre-merge check instead of discovering SDK incompatibility after a tag is pushed.

The workflow's first pull-request run also showed that Xcode 15.4 does not infer main-actor isolation for the geometry helper as newer Xcode does. The helper now carries an explicit `@MainActor` annotation; this is an isolation declaration only and does not change callback behavior.

The corrected release will use the new immutable `v1.0.18` tag only after local signal characterization, the full local suite, release compilation, and the GitHub macOS 14 compatibility build are green.

## Local verification

- Full default suite: 157 tests in 18 suites passed.
- Real shown-popover G2 signal harness: all 112 intentional shape changes produced exactly 112 callbacks, with no stable-window churn.
- Universal release app bundle: arm64 and x86_64 compilation and bundle assembly passed under Xcode 26.6.
- The exact Xcode 15.4/macOS 14 product build remains the pull-request compatibility gate and must be green before merge or tagging.
