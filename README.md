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

A macOS menu bar app that shows your Claude usage as a retro 8-bit battery.

## Install

**Homebrew (recommended)**

```
brew install diamondkj/tap/claudebat
```

**Download DMG**

Grab the latest `.dmg` from [Releases](https://github.com/DiamondKJ/ClaudeBat/releases), open it, drag to Applications.

**Build from source**

```
git clone https://github.com/DiamondKJ/ClaudeBat.git
cd ClaudeBat
swift build
swift run ClaudeBat
```

## Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) logged in

## What You Get

- Session (5h) and weekly (7d) usage at a glance
- Sonnet breakdown with mini battery bar
- Extra usage spend / limit when enabled
- 8-bit segmented battery bars
- Pixel bat that winks on refresh
- GAME OVER screen with countdown when maxed out
- Auto-polling — no manual refresh needed
- Launch at login, right-click to quit

## How It Works

Reads your Claude Code OAuth token from macOS Keychain via `/usr/bin/security` — zero prompts, zero setup. Polls the usage API on a sliding window budget to stay within rate limits. Caches data locally so the menu bar number appears instantly on launch.

## Uninstall

**Homebrew:** `brew uninstall claudebat`

**Manual:** Right-click → Quit, then delete from Applications.

---

<p align="center">
  Built by KJ + Claude — April 2026
</p>
