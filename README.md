# AI Usage Bar

Native macOS menu bar app that polls account usage directly from authenticated web sessions.

## Current behavior

- Native menu bar popover UI with horizontal graphs
- Provider colors:
  - ChatGPT: white
  - Claude: orange
  - Google Gemini: blue
  - OpenRouter: purple
- Per-provider sign-in windows using `WKWebView`
- Persisted web sessions via `WKWebsiteDataStore.default()`
- Direct authenticated polling for OpenRouter account credits
- Heuristic web scraping hooks for ChatGPT, Claude, and Gemini

## Important limitation

OpenRouter is wired against an authenticated account endpoint.

ChatGPT, Claude, and Gemini consumer usage counters are not exposed as stable public OAuth APIs for the exact rolling `5h` and weekly counters you asked for, so the app uses authenticated web-session scraping. The provider hooks are in `Sources/AIUsageBar/ProviderClients.swift`.

## Build

```bash
./Scripts/build.sh
```

This produces:

- `./.build/AIUsageBar`
- `./.build/AI Usage Bar.app`

## Install Locally

```bash
./Scripts/install.sh
```

This installs the app to `~/Applications/AI Usage Bar.app`.

## Run

```bash
./Scripts/run.sh
```

## Usage

1. Launch the app.
2. Click `AI Usage` in the menu bar.
3. Use `Sign In` on each provider card.
4. Complete sign-in in the web window for that provider.
5. Click `Refresh` in the dropdown.

## Tuning selectors

If ChatGPT, Claude, or Gemini shows `Needs tuning`, update the provider script for that service in:

`Sources/AIUsageBar/ProviderClients.swift`

Those providers intentionally keep the extraction logic localized so you can adjust the page selectors or internal account fetches without touching the UI.
