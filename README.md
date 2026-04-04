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
  <img src="https://img.shields.io/badge/tests-28%20passing-E8734A?style=flat-square&labelColor=1A1210" alt="28 tests">
</p>

---

A macOS menu bar app that shows your Claude usage as a retro 8-bit battery. Pixel bat. Anthropic orange. Zero setup.

## Install

**Homebrew (recommended)**

```
brew install diamondkj/tap/claudebat
```

**Download DMG**

Grab the latest `.dmg` from [Releases](https://github.com/DiamondKJ/claudebat/releases), open it, drag to Applications. Then run this once to clear the Gatekeeper flag (app is not code signed yet):

```
xattr -cr /Applications/ClaudeBat.app
```

**Build from source**

```
git clone https://github.com/DiamondKJ/claudebat.git
cd claudebat
swift build
swift run ClaudeBat
```

## Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) logged in

If you don't have Claude Code yet, the app will walk you through installing it.

## What You Get

- **Session (5h)** and **weekly (7d)** usage at a glance in the menu bar
- Sonnet model breakdown with mini battery bar
- Extra usage section (spend / limit) when enabled on your account
- 8-bit segmented battery bars with smooth per-percent fill
- Pixel bat that winks when refreshing
- Freshness indicator: pixel dot + age text, color shifts by staleness
- GAME OVER screen with countdown when you're fully rate-limited
- Cached data on launch — never stares at a loading screen
- Auto-polling — no manual refresh needed, ever
- Right-click context menu: launch at login, about, quit

## How It Works

### Keychain: Zero Prompts

Claude Code stores OAuth tokens in macOS Keychain. Every third-party tool using Apple's `SecItemCopyMatching` API gets a Keychain prompt that returns every ~8 hours when the token rotates. 10+ community projects share this pain ([#22144](https://github.com/anthropics/claude-code/issues/22144)).

ClaudeBat shells out to `/usr/bin/security` instead. macOS checks the *subprocess's* identity against the ACL, not the parent app's. Since `/usr/bin/security` is always in the `apple-tool:` partition (Claude Code uses it to create the entry), it's always allowed. No prompts, no setup, no hooks.

### Polling: Smart, Not Spammy

The `/api/oauth/usage` endpoint is undocumented and rate-limited. The community concluded "~5 requests per token lifetime" ([#31637](https://github.com/anthropics/claude-code/issues/31637)). We ran controlled experiments and found it's actually a rolling window:

- **5 requests per 300s** sliding window
- **Fixed 300s** cooldown (poking during cooldown doesn't extend it)
- **1 req/60s** is sustainable indefinitely
- **Per-token** — logging out and back in (`claude /logout` then `claude`) resets the window

ClaudeBat polls at 75s (popover open) or 120s (closed) — using 4 of 5 budget slots, always keeping 1 spare. There is no manual refresh button — the app handles everything automatically:

- **Popover open**: fetches if data is >60s old
- **Sleep/wake**: fetches immediately if data is >5min stale
- **5-hour reset**: bypasses the local budget when the usage window resets
- **Rate limited**: respects server Retry-After, shows cached data, never shows an error

Data is cached in UserDefaults with a 24h TTL. The menu bar number appears instantly on launch from cache.

## Uninstall

**Homebrew:** `brew uninstall claudebat`

**Manual:** Quit ClaudeBat (right-click → Quit, or `killall ClaudeBat`), then delete from Applications.

---

<p align="center">
  Built by KJ + Claude (Opus 4.6) — April 2026
</p>
