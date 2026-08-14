# T1 Local Test Installation

Date: 2026-08-14

Result: installed and running with explicit user authorization.

## Installed build

- Source branch: `codex/popover-sizing-fix`
- Working-tree base: `78c7b4e`
- Bundle: `/Applications/ClaudeBat.app`
- Bundle version/build: `1.0.16 (31)`
- Architectures: `arm64`, `x86_64`
- Executable SHA-256: `d09da86a117e7bb555692aac40d6d8294f96f861d3e0332bfb1ee02a461f7876`
- Running PID after launch: `14959`

This refresh uses shared lower-section spacing metrics: 28 points around the weekly/model bar group and before freshness, plus 16 points between multiple model rows. The measured compact/expanded/compact round trip is now `327 -> 471 -> 327` points.

The bundle was built from the current implementation working tree, so the embedded `CBGitCommit` records the base commit rather than a commit containing the uncommitted sizing changes. The executable hash above is the authoritative identifier for this test build.

## Rollback

The immediately previous 20/12-point spacing build was moved intact to:

`/Applications/ClaudeBat.app.before-roomier-spacing-tune`

The initial sizing-fix test build remains at:

`/Applications/ClaudeBat.app.before-bottom-spacing-tune`

The original pre-fix installed app remains at:

`/Applications/ClaudeBat.app.before-popover-sizing-fix`

No release, push, tag, DMG, Homebrew update, manual API request, or credential mutation was performed. Once launched, the app resumed its normal credential reads and usage polling. The build script replaced only the repository's explicit `build/` output before assembling the new bundle.
