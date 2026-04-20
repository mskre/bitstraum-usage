# Downdetector Freshness Design

## Goal

Stop Downdetector background refresh from interrupting the user with captcha windows and make alert dots and notifications disappear once the underlying report is no longer recent.

## Root Cause

- `DowndetectorService.fetch()` opens a challenge window when it detects a Cloudflare-style interstitial.
- Alert UI uses `DowndetectorReport.effectiveStatus()` with the latest datapoint only, but it does not consider how old the fetched report is.
- Failed or challenged fetches therefore leave previously fetched warning or danger states visible for too long.

## Design

### Background Fetch Behavior

- Automatic Downdetector refresh must never open a foreground window.
- Challenge pages and failed loads should return no fresh report.
- The service can keep a shared `WKWebView`, but challenge UI remains disabled for background refresh.

### Freshness Rules

- A Downdetector report remains useful only for a short time window after `fetchedAt`.
- While fresh, severity still depends on the latest datapoint exceeding the configured baseline multiplier.
- Once stale, the effective alert status becomes `unknown` instead of `warning` or `danger`.

### UI and Notification Behavior

- Status bar alert dots use fresh-only status.
- Inline provider-card Downdetector badges use fresh-only status.
- Notifications fire only for fresh warning or danger states.
- When the report ages out or refreshes to a non-problem state, the alert dot and notification state clear.

## Implementation Notes

- Keep the existing report model and add freshness helpers instead of introducing a second state store.
- Prefer a single helper used by all call sites so the status bar, popover, and notifications stay consistent.
- Preserve the current baseline-threshold setting and existing chart rendering.

## Testing

- Add a small executable Swift test harness for freshness logic.
- Verify the harness fails before the new helper exists and passes afterward.
- Run a full `zsh Scripts/build.sh` after updating the service and UI call sites.
