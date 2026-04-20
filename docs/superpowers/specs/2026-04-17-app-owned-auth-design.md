# App-Owned Auth Design

## Goal

Make Bitstraum Usage launch like a normal macOS app without repeatedly prompting for external Keychain access by moving Claude/OpenAI startup reads to app-owned credential records.

## Current Problem

- Claude credentials are read directly from the `Claude Code-credentials` Keychain item on launch.
- ChatGPT Codex credentials are read from `~/.codex/auth.json` during provider selection and startup refresh.
- `./Scripts/run.sh` launches a rebuilt ad-hoc signed app from `.build`, which is fine for development but not a stable install target.
- Notification permission is requested on startup even before the user opts into notifications.

## Design

### Credential Ownership

- Add an app-owned keychain store for imported provider credentials.
- Claude and OpenAI startup behavior must use only app-owned credentials.
- External credential reads remain available only through explicit import or repair actions.

### Launch Behavior

- `UsageStore.start()` performs a silent refresh using app-owned credentials only.
- Missing credentials leave the provider disconnected instead of triggering external reads.
- Notification permission is deferred until the user enables notifications.

### Connect Flow

- `Sign In` for Claude/OpenAI first attempts an explicit import from the external source.
- On success, imported credentials are persisted into Bitstraum Usage's own Keychain item.
- If no import source is available, fall back to the existing embedded browser flow.

### Refresh Flow

- Provider clients refresh using app-owned credentials.
- Successful token refresh overwrites the app-owned keychain record.
- Refresh failure moves the card back to a reconnect state without silent external probing.

## Implementation Notes

- Keep the change minimal by introducing a dedicated app credential store and routing existing auth helpers through it where appropriate.
- Preserve current browser-based sign-in for providers that do not have importable external credentials.
- Do not add background sync from external tools; resync stays explicit.

## Testing

- Build the app after each code phase.
- Verify startup no longer requests notification permission.
- Verify Claude/OpenAI launch refresh works after importing credentials once.
- Verify reconnect state appears when imported credentials are missing or invalid.
