# Bitstraum Usage

Native macOS menu bar app that shows your AI provider usage limits at a glance.

Built with Swift, AppKit, SwiftUI, and WebKit. No Xcode project required — compiles with `swiftc` from Command Line Tools.

## Features

- Battery-style menu bar icon showing current session usage per provider
- Liquid Glass dropdown panel (macOS 26) with per-provider usage breakdown
- Authenticated polling via persistent `WKWebView` sessions
- Auto-refresh every 5 minutes and on app launch
- Live-updating "last updated X seconds ago" footer

## Providers

| Provider | Data source | What it shows |
|---|---|---|
| ChatGPT | `/backend-api/wham/usage` | 5h limit, weekly limit, per-model limits with reset times |
| Claude | DOM scrape of `/settings/usage` | Current session, weekly all-models, weekly Sonnet with reset times |

Gemini and OpenRouter are commented out in the source (no usage counters exposed by those providers).

## Requirements

- macOS 26 (Tahoe) or later
- Xcode Command Line Tools (or full Xcode)
- macOS 26 SDK for Liquid Glass support

## Build

```bash
./Scripts/build.sh
```

## Install

```bash
./Scripts/install.sh
```

Installs to `~/Applications/Bitstraum Usage.app`.

## Run

```bash
./Scripts/run.sh
```

## Homebrew

```bash
brew tap mskre/tap
brew install --cask bitstraum-usage
```

## Releases

Pushing a tag named `vX.Y.Z` from `main` publishes the app automatically:

1. Builds and zips `Bitstraum Usage.app`
2. Creates a GitHub release in `mskre/bitstraum-usage`
3. Uploads `BitstraumUsage-X.Y.Z.zip`
4. Updates `mskre/homebrew-tap/Casks/bitstraum-usage.rb`

Required repository secret:

- `HOMEBREW_TAP_TOKEN` — fine-grained token with Contents read/write access to `mskre/homebrew-tap`

## Usage

1. Launch the app — the battery-style icon appears in the menu bar.
2. Click the icon to open the dropdown.
3. Click **Sign In** on a provider card.
4. Log in through the in-app browser window that opens.
5. Usage data appears automatically after sign-in (or close the window to trigger a refresh).
6. The app polls every 5 minutes in the background.

## Architecture

- **`AppMain.swift`** — status bar item, borderless `NSPanel` with `NSVisualEffectView`, Edit menu for clipboard support in sign-in windows
- **`WebAutomationService.swift`** — one persistent `WKWebView` per provider for both sign-in and polling; `SignInNavigationDelegate` detects auth completion
- **`ProviderClients.swift`** — per-provider JS scripts executed inside authenticated WKWebViews; ChatGPT uses `fetch()` against internal APIs, Claude scrapes the usage page DOM
- **`UsageStore.swift`** — `ObservableObject` managing cards, refresh loop, and persistence
- **`PopoverView.swift`** — SwiftUI dropdown with provider sections, usage bars, and percentages
- **`StatusBarPreview.swift`** — template `NSImage` battery-style icon rendered into the status bar button
- **`Models.swift`** — `ProviderID`, `ProviderUsageCard`, `UsageLimit`, and related types

## Adding a provider

1. Add a case to `ProviderID` in `Models.swift` with `loginURL` and `usageURL`.
2. Write a JS script in `ProviderScripts` that returns a JSON string matching `ProviderScrapeResult`.
3. Register it in `ProviderFactory.makeAll()`.
4. The UI, menu bar icon, and refresh loop pick it up automatically.
