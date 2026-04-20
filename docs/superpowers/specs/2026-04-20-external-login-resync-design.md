# External Login Resync Design

## Goal

Make `Sign In` and `Reconnect` for Claude and ChatGPT feel automatic by importing fresh external credentials immediately when available, and by waiting for the external tool login to complete when they are not yet available.

## Current Problem

- Bitstraum Usage now uses app-owned credentials at runtime, which avoids repeated startup prompts.
- That improves launch UX, but it also means the app-owned record can drift from Claude Code or Codex until the user manually reconnects.
- The current `Sign In` flow already attempts import first, but if no external credentials are available it falls back to the embedded browser flow.
- For Claude and ChatGPT, the desired behavior is different: if external credentials are missing, prompt the user to log into the external tool and wait for those credentials to appear, then import them automatically.

## Design

### Runtime Credential Ownership

- App-owned keychain records remain the runtime source of truth.
- Background refresh continues to use only app-owned credentials.
- There is no return to launch-time probing of external keychain items or auth files.

### Sign-In Behavior

- On `Sign In` or `Reconnect` for Claude or ChatGPT:
  - First attempt immediate import from the external source.
  - If import succeeds, overwrite the app-owned record and refresh the provider immediately.
  - If import fails because external credentials are unavailable, prompt the user to log into the external tool.

### Wait-and-Import Flow

- Claude prompt tells the user to log into Claude Code.
- ChatGPT prompt tells the user to log into Codex.
- After prompting, the app polls for a short time window for fresh external credentials.
- As soon as credentials appear, the app imports them into the app-owned keychain and refreshes the provider.
- If the wait window expires, keep the provider unauthenticated with a clear status message instead of falling back to browser sign-in.

### UI Semantics

- `Sign In` and `Reconnect` remain the user-visible actions.
- The app should not expose import terminology unless useful for debugging.
- The status text should reflect the actual next step, for example asking the user to sign into Claude Code or Codex.

## Why This Approach

- It preserves the improved launch behavior from the app-owned credential model.
- It makes `Sign In` feel automatic and current without reintroducing silent startup probing.
- It keeps Claude and ChatGPT aligned with the external tools that actually own those sessions.
- It avoids the embedded browser path for these providers when the real source of truth is the external tool login.

## Edge Cases

- If the external tool is logged into a different account, the next successful import overwrites the app-owned record with that newer account.
- If the external tool never produces credentials during the wait window, the provider remains disconnected and the user can try again after completing external login.
- If imported credentials later expire, reconnect repeats the same flow: immediate import attempt, then prompt-and-wait.

## Testing

- Verify `Sign In` with already-available Claude Code credentials imports and refreshes immediately.
- Verify `Sign In` with already-available Codex credentials imports and refreshes immediately.
- Verify missing Claude Code credentials produce a prompt and poll for new credentials.
- Verify missing Codex credentials produce a prompt and poll for new credentials.
- Verify timeout leaves the provider unauthenticated with a clear message and no embedded browser fallback.
