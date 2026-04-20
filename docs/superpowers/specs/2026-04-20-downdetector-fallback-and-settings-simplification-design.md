# Downdetector Fallback And Settings Simplification Design

## Goal

Make the Downdetector tab recoverable when automated fetches are blocked, and simplify the settings experience so the app feels opinionated and productized instead of highly tweakable.

## Current Problems

### Downdetector

- Background fetches can be blocked by Cloudflare challenge pages.
- The app correctly avoids foregrounding captcha windows automatically, but the tab currently becomes a dead end when blocked.
- Opening Downdetector in the user’s normal browser does not help because the app uses its own `WKWebView` session.

### Settings

- The settings view exposes too many low-level controls at once.
- Color customization, privacy tuning, Downdetector tuning, and behavior toggles are mixed together in one long screen.
- Important settings are buried behind internal-style knobs that make the app feel less polished.

## Design

### Downdetector Recovery Flow

- Keep background Downdetector refresh non-interruptive.
- When a fetch is blocked, the Downdetector tab should show a recovery state instead of a passive empty state.
- The recovery state includes:
  - a blocked explanation
  - `Open Downdetector`
  - `Retry`
- `Open Downdetector` opens a small in-app window using the same shared `WKWebView` session as `DowndetectorService`.
- The user solves the challenge there if needed.
- After the page becomes usable, a retry fetch should populate the tab with actual report data.

### Downdetector State Model

- Track Downdetector tab state separately from the raw report dictionary.
- The tab should distinguish at least:
  - no data yet
  - blocked
  - unavailable
  - report data available
- Existing report/chart rendering remains unchanged when data exists.

### Simplified Settings Surface

- Replace the current long settings sheet with a compact essentials view.
- Keep only these user-facing controls in the primary settings UI:
  - refresh interval
  - notifications on/off
  - show/hide sensitive info
  - Downdetector on/off
  - quit app
  - reset defaults
- Remove the following from the main settings UI:
  - color pickers
  - mask amount and domain-only tuning
  - Downdetector baseline tuning
  - Downdetector chart-range tuning
  - remember-last-view
  - show reset labels
  - provider labels in menu bar
  - 24-hour time toggle
  - pin Downdetector toggle
  - provider enable/disable toggles

### Opinionated Defaults

- The app should prefer sensible defaults over visible tuning:
  - refresh interval: 5 minutes
  - Downdetector enabled
  - alert dot enabled
  - notifications enabled
  - sensitive info shown, but email masking enabled by default
  - fixed provider colors and background color
  - automatic Downdetector threshold and freshness behavior with no main-UI tuning
- Existing stored settings can remain in code for compatibility, but they should not dominate the UI.

## Architecture

### DowndetectorService

- Continue owning the shared `WKWebView` and the background fetch logic.
- Add a small explicit unlock-window path that reuses the same web view session.
- Keep fetch classification explicit so the UI can react differently to blocked vs unavailable conditions.

### UsageStore

- Publish a simple Downdetector UI state value alongside `downdetectorData`.
- Own retry actions triggered by the Downdetector tab.
- Avoid silently opening any recovery window during background polling.

### PopoverView

- Rewrite `ColorSettingsView` as a concise essentials panel.
- Update `DowndetectorTabView` to render blocked/unavailable actions instead of the current passive placeholder.

## Why This Approach

- It solves the real Downdetector recovery problem inside the app instead of depending on an unrelated browser session.
- It keeps the app quiet during background refresh while still giving the user a path to unblock it.
- It removes internal-style controls from the main settings experience and emphasizes the few choices a normal user actually needs.
- It keeps the implementation incremental by reusing existing storage and rendering where possible.

## Testing

- Add a focused regression test for Downdetector blocked-state classification if needed.
- Build the app after the settings rewrite and Downdetector fallback changes.
- Verify the Downdetector tab shows `Open Downdetector` and `Retry` when blocked.
- Verify solving the challenge in the in-app window allows retry to populate real Downdetector data.
- Verify the settings screen is substantially shorter and only shows the essential controls listed above.
