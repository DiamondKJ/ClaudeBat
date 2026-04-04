<p align="center">
  <img src="assets/bat-winking.png" alt="ClaudeBat" width="400">
</p>

<h1 align="center">ClaudeBat</h1>

<p align="center">
  <strong>Your Claude usage. One glance away.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-E8734A?style=flat-square&labelColor=1A1210" alt="macOS 14+">
  <img src="https://img.shields.io/badge/swift-zero%20dependencies-E8734A?style=flat-square&labelColor=1A1210" alt="Zero dependencies">
  <img src="https://img.shields.io/badge/homebrew-tap-E8734A?style=flat-square&labelColor=1A1210" alt="Homebrew">
</p>

---

macOS menu bar app. Shows your Claude session and weekly usage as retro 8-bit battery bars.

## Install

```
brew install diamondkj/tap/claudebat
```

Without an Apple Developer ID, macOS will not trust a downloaded build automatically.
That means there is no true zero-step install path for friends. The minimum working path is one
extra command after install:

If you installed with Homebrew and it still will not open:

```
xattr -cr /Applications/ClaudeBat.app
```

If you grabbed the `.dmg` from [Releases](https://github.com/DiamondKJ/ClaudeBat/releases), drag to Applications, then run:

```
xattr -cr /Applications/ClaudeBat.app
```

Needs macOS 14+ and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) logged in.

If Finder still blocks the first launch, right-click `ClaudeBat.app` and choose `Open` once.

## Release Build

Build the app and DMG:

```
./scripts/build-app.sh --dmg
```

Share the generated DMG from `build/`.

For direct installs, run:

```bash
# 1. Drag ClaudeBat.app to /Applications
# 2. Strip quarantine once
xattr -cr /Applications/ClaudeBat.app

# 3. Launch it
open /Applications/ClaudeBat.app
```

If you want actual "download and it just works" on stock macOS, you need a Developer ID-signed
and notarized build. Apple requires that for trusted outside-App-Store distribution, and
Homebrew's own cask docs reject apps that fail with Gatekeeper on supported Macs.

## What You Get

- Session (5h) and weekly (7d) usage in the menu bar
- Sonnet breakdown, extra usage spend/limit
- Auto-polls every 75s when open, 120s when closed
- No manual refresh. It just works.

## How It Works

Reads your OAuth token from Keychain via `/usr/bin/security` subprocess. Zero prompts.

Polls `GET /api/oauth/usage` on a 5-request/300s sliding window budget. Caches in UserDefaults with 24h TTL. Bypasses local budget on sleep/wake and 5-hour reset boundaries. Always respects server 429.

## Uninstall

```
brew uninstall claudebat
```

---

<p align="center">
  Built by KJ + Claude
</p>
