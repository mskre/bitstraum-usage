# Bitstraum Usage

Native macOS menu bar app that shows your AI provider usage limits at a glance.

Built with Swift, AppKit, SwiftUI, WebKit, and LocalAuthentication. No Xcode project required — compiles with `swiftc` from Command Line Tools.

## Features

- Battery-style menu bar icon with per-provider fill, configurable OpenAI and Claude colors
- Detached liquid-glass dropdown panel anchored under the menu bar, no blue selected status item
- Real Control Center-style surface using `NSVisualEffectView` behind the SwiftUI card
- Live provider usage with per-window reset timers and percentages
- Downdetector tab with automatic refresh, blocked-state recovery, and in-app unlock browser
- Smart Claude and ChatGPT reconnect that imports and refreshes external credentials in one click
- App-owned keychain storage with Touch ID-capable `SecAccessControl` so most reconnects are silent
- Simplified settings focused on refresh interval, notifications, account info privacy, and provider colors

## Providers

| Provider | Data source | What it shows |
|---|---|---|
| ChatGPT | `/backend-api/wham/usage` + Codex auth | 5h limit, weekly limit, per-model limits with reset times |
| Claude | Anthropic OAuth via Claude Code keychain + `/settings/usage` DOM | Current session, weekly all-models, weekly Sonnet, Claude Design usage |
| Downdetector | downdetector.com scrape | Provider outage indicators with freshness-aware alerts |

Gemini and OpenRouter are not included.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (or full Xcode)
- For ChatGPT reconnect: [Codex](https://developers.openai.com/codex) signed in on the same machine
- For Claude reconnect: [Claude Code](https://www.anthropic.com/claude-code) signed in on the same machine

## Install

### Homebrew (recommended)

```bash
brew tap mskre/tap
brew install --cask bitstraum-usage
```

Upgrade later with `brew upgrade --cask bitstraum-usage`.

### From source

```bash
./Scripts/install.sh
```

Installs to `~/Applications/Bitstraum Usage.app`.

### Run locally without installing

```bash
./Scripts/run.sh
```

## Usage

1. Launch the app. The battery-style icon appears in the menu bar.
2. Click the icon to open the liquid-glass dropdown.
3. Click **Connect** on a provider card.
4. For ChatGPT or Claude:
   - If Codex or Claude Code credentials exist, the app imports and refreshes immediately.
   - If not, the app prompts you to sign into that external tool and waits for fresh credentials.
5. The **Downdetector** tab shows provider outage status. If Downdetector blocks the automated refresh, use **Open Downdetector** to clear the Cloudflare challenge in the in-app browser, then close the window — the app refreshes all providers automatically.
6. Background refresh runs every 5 minutes by default.

## Privacy

The settings panel has a single **Account info** control with three modes:

- **Hidden** — account info is not shown in cards
- **Visible** — account info is shown fully
- **Masked** — account info is shown in masked form

## Keychain

App-owned credentials are stored in the macOS login keychain under `com.bitstraum.usage.credentials` with device-local, user-presence access control. On devices with Touch ID, this path can satisfy the access prompt via biometrics.

The app only reads external tool credentials (Claude Code, Codex) when you explicitly reconnect a provider. Background refresh never touches those external items.

## Build

```bash
./Scripts/build.sh
```

## Release

Pushing a tag `vX.Y.Z` from `main` publishes the app automatically:

1. Builds and zips `Bitstraum Usage.app`
2. Creates a GitHub release in `mskre/bitstraum-usage`
3. Uploads `BitstraumUsage-X.Y.Z.zip`
4. Updates `mskre/homebrew-tap/Casks/bitstraum-usage.rb`

Required repository secret:

- `HOMEBREW_TAP_TOKEN` — fine-grained token with Contents read/write access to `mskre/homebrew-tap`

## Architecture

- **`AppMain.swift`** — status bar item, detached borderless `NSPanel` anchored under the menu bar, keeps the status item from entering the system blue "selected" state
- **`PopoverView.swift`** — SwiftUI dropdown, liquid-glass chrome via `NSVisualEffectView`, provider rows, Downdetector tab, simplified settings
- **`UsageStore.swift`** — `ObservableObject` managing provider cards, refresh loop, Downdetector tab state, and external-login resync flows
- **`AppCredentialStore.swift`** — Touch ID-capable keychain wrapper for app-owned credentials, with migration from legacy unprotected items
- **`KeychainHelper.swift` / `OpenAIAuthHelper.swift`** — read Claude Code and Codex credentials, refresh OpenAI tokens, import into the app-owned keychain
- **`ProviderClients.swift`** — per-provider JS scripts executed inside authenticated WKWebViews; ChatGPT uses `fetch()` against internal APIs, Claude scrapes the usage page DOM
- **`DowndetectorService.swift`** — shared `WKWebView` for both background scrape and in-app unlock window, Cloudflare challenge classification, and post-unlock refresh hook
- **`StatusBarPreview.swift`** — template `NSImage` battery-style icon rendered into the status bar button
- **`ColorSettings.swift`** — persisted settings and opinionated defaults, plus the `PrivacyMode` three-state control

## Adding a provider

1. Add a case to `ProviderID` in `Models.swift` with `loginURL` and `usageURL`.
2. Write a JS script in `ProviderScripts` that returns a JSON string matching `ProviderScrapeResult`.
3. Register it in `ProviderFactory.makeAll()`.
4. The UI, menu bar icon, and refresh loop pick it up automatically.
